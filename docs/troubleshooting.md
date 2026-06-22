# トラブルシューティング

セットアップ中に発生しやすい問題と、その解決方法をまとめています。

---

## `winget` が見つからない

### 症状

```
winget : 用語 'winget' は、コマンドレット、関数、スクリプト ファイル、
または操作可能なプログラムの名前として認識されません。
```

### 原因と対処

1. **App Installer がインストールされていない**

   `winget` は Microsoft Store の「アプリ インストーラー」(App Installer) に含まれています。Microsoft Store から最新版をインストールしてください。

   ```powershell
   # Microsoft Store から手動インストールできない場合
   Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
   ```

2. **PATH が通っていない**

   ```powershell
   # winget のパスを確認
   Get-Command winget -ErrorAction SilentlyContinue

   # 見つからない場合、以下のパスを確認
   Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
   ```

3. **Windows のバージョンが古い**

   `winget` は Windows 10 1709 以降で利用可能です。`winver` コマンドで確認してください。

---

## Scoop インストール失敗

### 症状

Scoop のインストールスクリプトが途中で失敗する、またはパッケージのインストールに失敗する。

### 原因と対処

1. **実行ポリシーの問題**

   ```powershell
   # 現在のポリシーを確認
   Get-ExecutionPolicy -List

   # CurrentUser スコープで RemoteSigned に変更
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
   ```

2. **インターネット接続の問題**

   ```powershell
   # 接続確認
   Test-NetConnection -ComputerName github.com -Port 443
   Test-NetConnection -ComputerName raw.githubusercontent.com -Port 443
   ```

3. **プロキシ環境**

   企業ネットワークなどプロキシ環境では、プロキシの設定が必要です。

   ```powershell
   # プロキシを設定してから Scoop をインストール
   [Net.WebRequest]::DefaultWebProxy = New-Object Net.WebProxy("http://proxy:8080")
   [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultCredentials

   # Scoop のプロキシ設定
   scoop config proxy proxy:8080
   ```

---

## PowerShell 実行ポリシー

### 症状

```
このシステムではスクリプトの実行が無効になっているため、
ファイル *.ps1 を読み込むことができません。
```

### 対処

```powershell
# 現在のポリシーを確認
Get-ExecutionPolicy -List
```

### スコープの説明

| スコープ        | 説明                                       |
| --------------- | ------------------------------------------ |
| `MachinePolicy` | グループポリシーで設定 (管理者が管理)       |
| `UserPolicy`    | ユーザーのグループポリシー                  |
| `Process`       | 現在の PowerShell セッションのみ            |
| `CurrentUser`   | 現在のユーザーに対して永続的に適用          |
| `LocalMachine`  | すべてのユーザーに対して適用 (管理者権限必要) |

### 推奨設定

```powershell
# CurrentUser スコープで設定 (管理者権限不要)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# 確認
Get-ExecutionPolicy -List
```

`RemoteSigned` は、ローカルで作成したスクリプトはそのまま実行でき、インターネットからダウンロードしたスクリプトには署名が必要になるポリシーです。

---

## `sshd` が起動しない

### 症状

SSH サーバーが起動せず、リモートから接続できない。

### 確認と対処

1. **サービスの状態を確認**

   ```powershell
   Get-Service sshd
   ```

2. **OpenSSH Server がインストールされているか確認**

   ```powershell
   Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH*'
   ```

   `OpenSSH.Server` の State が `NotPresent` の場合:

   ```powershell
   # OpenSSH Server をインストール
   Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
   ```

3. **イベントログを確認**

   ```powershell
   Get-WinEvent -LogName Application -MaxEvents 20 |
     Where-Object { $_.ProviderName -like '*ssh*' -or $_.Message -like '*ssh*' } |
     Format-List TimeCreated, Message
   ```

4. **サービスを開始して自動起動に設定**

   ```powershell
   Start-Service sshd
   Set-Service -Name sshd -StartupType Automatic
   ```

---

## Port 22 が Listen していない

### 症状

`sshd` サービスは動いているが、接続できない。

### 確認と対処

1. **ポートの Listen 状態を確認**

   ```powershell
   # PowerShell で確認
   Test-NetConnection -ComputerName localhost -Port 22

   # netstat で確認
   netstat -an | findstr :22
   ```

2. **ファイアウォールを確認**

   ```powershell
   # SSH 関連のファイアウォール規則を確認
   Get-NetFirewallRule -Name *ssh* | Format-List Name, Enabled, Direction, Action

   # 規則がない場合は作成
   New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" `
     -DisplayName "OpenSSH Server (sshd)" `
     -Enabled True `
     -Direction Inbound `
     -Protocol TCP `
     -Action Allow `
     -LocalPort 22
   ```

3. **別のプロセスがポート 22 を使用していないか確認**

   ```powershell
   netstat -ano | findstr :22
   # 表示された PID を確認
   Get-Process -Id <PID>
   ```

---

## `Permission denied (publickey)`

### 症状

```
user@host: Permission denied (publickey).
```

### 確認と対処

1. **authorized_keys ファイルが存在するか確認**

   ```powershell
   # 一般ユーザーの場合
   Test-Path C:\Users\<username>\.ssh\authorized_keys

   # 管理者ユーザーの場合 (Windows の OpenSSH 特有)
   Test-Path C:\ProgramData\ssh\administrators_authorized_keys
   ```

2. **authorized_keys の内容を確認**

   公開鍵が正しく記述されているか確認してください。1行に1つの鍵が記述されている必要があります。

3. **ファイルのエンコーディングを確認**

   `authorized_keys` は **UTF-8 (BOM なし)** で保存する必要があります。メモ帳で編集した場合、BOM 付きで保存される可能性があります。

   ```powershell
   # BOM の有無を確認 (先頭3バイトが EF BB BF なら BOM 付き)
   $bytes = [System.IO.File]::ReadAllBytes("C:\Users\<username>\.ssh\authorized_keys")
   if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
       Write-Host "BOM が検出されました。BOM なし UTF-8 で保存し直してください。"
   }

   # BOM なし UTF-8 で保存し直す
   $content = Get-Content C:\Users\<username>\.ssh\authorized_keys -Raw
   [System.IO.File]::WriteAllText("C:\Users\<username>\.ssh\authorized_keys", $content, [System.Text.UTF8Encoding]::new($false))
   ```

4. **ファイルのパーミッションを確認**

   ```powershell
   icacls C:\Users\<username>\.ssh\authorized_keys
   ```

   所有者がそのユーザーであり、他のユーザーにアクセス権がないことを確認してください。

---

## `administrators_authorized_keys` のACL問題

### 症状

管理者ユーザーで公開鍵認証が通らない。`sshd` のログに権限エラーが記録されている。

### 原因

Windows の OpenSSH では、管理者グループ (Administrators) に属するユーザーの公開鍵は `C:\ProgramData\ssh\administrators_authorized_keys` から読み取られます。このファイルの ACL (アクセス制御リスト) が正しくないと認証に失敗します。

### 要件

- ファイルの所有者が **SYSTEM** または **Administrators** であること
- **SYSTEM** と **Administrators** のみが読み取りアクセスを持つこと
- 他のユーザーやグループにはアクセス権がないこと

### 対処

```powershell
# 現在の ACL を確認
icacls C:\ProgramData\ssh\administrators_authorized_keys

# 継承を無効化し、既存の ACL を削除
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r

# SYSTEM にフルコントロールを付与
icacls C:\ProgramData\ssh\administrators_authorized_keys /grant "SYSTEM:(F)"

# Administrators に読み取り権限を付与
icacls C:\ProgramData\ssh\administrators_authorized_keys /grant "BUILTIN\Administrators:(R)"

# 設定後の確認
icacls C:\ProgramData\ssh\administrators_authorized_keys
```

正しい状態の出力例:

```
C:\ProgramData\ssh\administrators_authorized_keys
    NT AUTHORITY\SYSTEM:(F)
    BUILTIN\Administrators:(R)
```

---

## `cursor` コマンドが見つからない

### 症状

```
cursor : 用語 'cursor' は、コマンドレット、関数、スクリプト ファイル、
または操作可能なプログラムの名前として認識されません。
```

### 原因と対処

Cursor エディタは、インストール時に PATH へ自動で追加されない場合があります。

1. **インストール場所を確認**

   ```powershell
   # 一般的なインストール先
   Test-Path "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe"
   Test-Path "$env:LOCALAPPDATA\cursor\Cursor.exe"
   ```

2. **Cursor から手動で PATH に追加**

   Cursor を起動し、コマンドパレット (`Ctrl+Shift+P`) で「Shell Command: Install 'cursor' command in PATH」を実行してください。

3. **手動で PATH に追加**

   ```powershell
   # ユーザーの PATH に追加 (パスは実際のインストール先に合わせてください)
   $cursorPath = "$env:LOCALAPPDATA\Programs\cursor"
   $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
   if ($currentPath -notlike "*$cursorPath*") {
       [Environment]::SetEnvironmentVariable("Path", "$currentPath;$cursorPath", "User")
   }
   ```

   PATH を変更した後は、新しいターミナルを開いてください。

---

## `claude` コマンドが見つからない

### 症状

```
claude : 用語 'claude' は、コマンドレット、関数、スクリプト ファイル、
または操作可能なプログラムの名前として認識されません。
```

### 原因と対処

1. **npm でグローバルインストールした場合**

   ```powershell
   # npm のグローバル bin パスを確認
   npm config get prefix

   # claude がインストールされているか確認
   npm list -g @anthropic-ai/claude-code
   ```

   npm のグローバル bin パスが PATH に含まれていない場合:

   ```powershell
   $npmPrefix = (npm config get prefix)
   $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
   if ($currentPath -notlike "*$npmPrefix*") {
       [Environment]::SetEnvironmentVariable("Path", "$currentPath;$npmPrefix", "User")
   }
   ```

2. **公式インストーラーでインストールした場合**

   インストール先が PATH に追加されているか確認してください。

   ```powershell
   Get-Command claude -ErrorAction SilentlyContinue
   ```

新しいターミナルを開いて再度確認してください。

---

## Tailscale が PATH にない

### 症状

```
tailscale : 用語 'tailscale' は、コマンドレット、関数、スクリプト ファイル、
または操作可能なプログラムの名前として認識されません。
```

### 原因と対処

Tailscale のデフォルトインストール先は `C:\Program Files\Tailscale\` です。

```powershell
# インストール先の確認
Test-Path "C:\Program Files\Tailscale\tailscale.exe"

# フルパスで実行
& "C:\Program Files\Tailscale\tailscale.exe" status
```

PATH に追加する場合:

```powershell
# システム PATH に追加 (管理者権限が必要)
$tailscalePath = "C:\Program Files\Tailscale"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($currentPath -notlike "*$tailscalePath*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$tailscalePath", "Machine")
}
```

---

## AutoHotkey が管理者アプリで効かない

### 症状

AutoHotkey のスクリプト (Win+Space での IME 切り替えなど) が、管理者権限で実行されたアプリケーション (タスクマネージャー、管理者として実行したターミナルなど) に対して動作しない。

### 原因

通常のユーザー権限で動作している AutoHotkey は、UAC (ユーザーアカウント制御) により、管理者権限で動作しているアプリケーションにキー入力を送信できません。

### 対処

**方法1: AutoHotkey を管理者として実行**

AHK スクリプトを右クリック -> 「管理者として実行」で起動します。ただし、毎回手動で実行するのは不便です。

**方法2: タスクスケジューラで最上位の特権で実行**

ログオン時に自動的に管理者権限で AHK スクリプトを起動するタスクを作成します。

```powershell
# タスクスケジューラに登録する例
$action = New-ScheduledTaskAction `
    -Execute "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" `
    -Argument "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\win-space-ime.ahk"

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit 0

Register-ScheduledTask `
    -TaskName "AutoHotkey-IME-Toggle" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Force
```

この方法を使う場合、スタートアップフォルダに配置されている AHK スクリプトのショートカットは削除してください (二重起動を防ぐため)。

---

## 固定IP設定後に通信できない

### 症状

`config/local.psd1` の Network 設定で固定 IP を設定した後、インターネットやネットワークに接続できなくなった。

### 確認と対処

1. **IP アドレスの競合**

   設定した IP アドレスが、他のデバイス (ルーター、別の PC、プリンターなど) と重複していないか確認してください。

   ```powershell
   # 設定された IP を確認
   Get-NetIPAddress -InterfaceAlias "イーサネット" | Format-List IPAddress, PrefixLength

   # ARP テーブルで競合を確認
   arp -a
   ```

2. **デフォルトゲートウェイの確認**

   ゲートウェイが正しく設定されていないと、ローカルネットワーク外と通信できません。

   ```powershell
   # ゲートウェイを確認
   Get-NetRoute -DestinationPrefix "0.0.0.0/0"

   # ゲートウェイへの疎通確認
   Test-NetConnection -ComputerName <ゲートウェイIP>
   ```

3. **DNS サーバーの確認**

   DNS が設定されていない、または間違っていると、名前解決ができません。

   ```powershell
   # DNS 設定を確認
   Get-DnsClientServerAddress

   # DNS の疎通確認
   Resolve-DnsName google.com
   ```

---

## DHCP へ戻す方法

固定 IP の設定を元に戻して、DHCP (自動取得) に変更する方法です。

```powershell
# 1. ネットワークアダプター名を確認
Get-NetAdapter | Format-List Name, Status, InterfaceIndex

# 2. IP アドレスを DHCP に戻す
Set-NetIPInterface -InterfaceAlias "イーサネット" -Dhcp Enabled

# 3. 既存の固定 IP とゲートウェイを削除 (残っている場合)
Remove-NetIPAddress -InterfaceAlias "イーサネット" -Confirm:$false
Remove-NetRoute -InterfaceAlias "イーサネット" -Confirm:$false -ErrorAction SilentlyContinue

# 4. DNS も DHCP に戻す
Set-DnsClientServerAddress -InterfaceAlias "イーサネット" -ResetServerAddresses

# 5. アダプターを再起動して設定を反映
Restart-NetAdapter -Name "イーサネット"

# 6. 新しい IP が割り当てられたか確認
Get-NetIPAddress -InterfaceAlias "イーサネット" | Format-List IPAddress, PrefixLength, PrefixOrigin
```

`PrefixOrigin` が `Dhcp` になっていれば、DHCP に正しく戻っています。

アダプター名が「イーサネット」ではない場合は、手順 1 で確認した名前に置き換えてください (例: `Wi-Fi`、`Ethernet` など)。
