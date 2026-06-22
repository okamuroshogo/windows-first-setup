# Windows 初期セットアップ

Windows 11 を新規インストールした直後に、最低限の操作で開発環境を構築するためのスクリプト集です。

Windows 本体では OpenSSH Server の有効化だけを行い、残りのセットアップは Mac などの別 PC から SSH 経由で自動実行します。

## 最短手順

### 1. Windows 本体で OpenSSH を有効化

管理者 PowerShell を開き（右クリック → 「管理者として実行」）、以下を実行します。

**方法A: スクリプトをダウンロードして確認してから実行（推奨）**

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/okamuroshogo/windows-first-setup/main/scripts/00-bootstrap-openssh.ps1" -OutFile "$env:TEMP\00-bootstrap-openssh.ps1"
# 内容を確認
Get-Content "$env:TEMP\00-bootstrap-openssh.ps1"
# 確認後に実行
powershell -ExecutionPolicy Bypass -File "$env:TEMP\00-bootstrap-openssh.ps1"
```

**方法B: ワンライナー（リポジトリの内容を信頼している場合のみ）**

```powershell
irm "https://raw.githubusercontent.com/okamuroshogo/windows-first-setup/main/scripts/00-bootstrap-openssh.ps1" | iex
```

> **セキュリティ警告**: `irm | iex` はダウンロードしたスクリプトを直接実行します。中間者攻撃やURL内容の改ざんのリスクがあります。初回は方法Aで内容を確認してから実行することを強く推奨します。詳細は [docs/security.md](docs/security.md) を参照してください。

スクリプトが GitHub (`github.com/okamuroshogo.keys`) から SSH 公開鍵を自動取得して `administrators_authorized_keys` に登録します。GitHub への接続に失敗した場合のみ、手動で公開鍵を貼り付けるプロンプトが表示されます。

> **Microsoft アカウントの場合**: パスワードではなく PIN でサインインするため、SSH のパスワード認証が使えません。Bootstrap スクリプトが公開鍵の登録まで自動で行います。

### 2. Mac から SSH 接続

```bash
# ユーザー名とIPは自分の環境に合わせて変更してください
ssh shogo@192.168.1.100
```

### 3. Windows 側でリポジトリをクローン

```powershell
git clone https://github.com/okamuroshogo/windows-first-setup.git
cd windows-first-setup
Copy-Item .\config\local.psd1.example .\config\local.psd1
notepad .\config\local.psd1
```

`local.psd1` を開いて、Git のユーザー名・メールアドレスなど自分の環境に合わせて編集してください。

### 4. セットアップ実行

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\setup-all.ps1
```

> **注意**: 管理者権限が必要です。SSH 接続時に管理者権限がない場合は、Windows 本体で管理者 PowerShell から実行してください。

```powershell
# Windows本体の管理者PowerShellで実行する場合
cd C:\Users\<ユーザー名>\windows-first-setup
pwsh -ExecutionPolicy Bypass -File .\scripts\setup-all.ps1
```

---

## 前提条件

- Windows 11（クリーンインストール直後を想定）
- インターネット接続
- 管理者権限のあるアカウント（Microsoft アカウント / ローカルアカウント どちらでも可）
- SSH 接続元の PC（Mac/Linux）に SSH 鍵ペアがあること

## リポジトリ構成

```text
windows-first-setup/
├── README.md              # このファイル
├── LICENSE                # MIT License
├── .gitignore
├── config/
│   ├── example.psd1       # 設定例（全項目記載）
│   └── local.psd1.example # コピーして local.psd1 を作成
├── scripts/
│   ├── _helpers.ps1       # 共通ヘルパー関数
│   ├── 00-bootstrap-openssh.ps1  # OpenSSH Server 有効化
│   ├── 01-base-setup.ps1         # 基本環境
│   ├── 02-install-winget-apps.ps1 # WinGet アプリ
│   ├── 03-install-scoop-tools.ps1 # Scoop CLI ツール
│   ├── 04-configure-git.ps1      # Git 設定
│   ├── 05-configure-sshd.ps1     # SSHD 設定
│   ├── 06-configure-ime.ps1      # IME/AutoHotkey 設定
│   ├── 07-configure-network.ps1  # 固定IP設定（手動実行）
│   ├── 08-install-claude-code.ps1 # Claude Code
│   ├── 09-verify.ps1             # 検証
│   └── setup-all.ps1             # 一括実行
├── assets/
│   └── win-space-ime.ahk # AutoHotkey IME切替スクリプト
└── docs/
    ├── security.md        # セキュリティ注意事項
    └── troubleshooting.md # トラブルシューティング
```

## 各スクリプトの説明

| スクリプト | 説明 | 管理者権限 |
|---|---|---|
| `00-bootstrap-openssh.ps1` | OpenSSH Server のインストール・起動・Firewall 設定 | 必要 |
| `01-base-setup.ps1` | PowerShell 7, Git, Windows Terminal, PC名変更, スリープ設定 | 必要 |
| `02-install-winget-apps.ps1` | Chrome, Slack, Cursor, 1Password 等の GUI アプリ | 不要* |
| `03-install-scoop-tools.ps1` | 7zip, jq, ripgrep, Node.js 等の CLI ツール | 不要 |
| `04-configure-git.ps1` | Git のユーザー名・メール・デフォルトブランチ設定 | 不要 |
| `05-configure-sshd.ps1` | SSHD の自動起動・デフォルトシェル設定 | 必要 |
| `06-configure-ime.ps1` | AutoHotkey IME 切替スクリプトの配置・起動 | 不要 |
| `07-configure-network.ps1` | 固定 IP アドレス設定（`setup-all.ps1` からは呼ばれない） | 必要 |
| `08-install-claude-code.ps1` | Claude Code のインストール | 不要 |
| `09-verify.ps1` | インストール済みツール・サービスの検証 | 不要 |
| `setup-all.ps1` | Phase 1〜8 + 検証を順番に実行 | 必要 |

\* 一部アプリはインストール時に管理者権限が必要な場合があります。

## 設定ファイル

### config/local.psd1

`config/local.psd1.example` をコピーして作成します。`.gitignore` に含まれているため Git にコミットされません。

```powershell
@{
    GitUserName  = "Your Name"        # Git のユーザー名
    GitUserEmail = "you@example.com"  # Git のメールアドレス
    ComputerName = ""                 # PC名（空欄で変更しない）
    DisableSleep = $false             # $true でスリープ無効化
    SetDefaultShell = $true           # SSH デフォルトシェルを pwsh にする
    EnableAutoHotkey = $true          # Win+Space IME トグルを有効化

    WinGetApps = @{                   # $false でスキップ
        GoogleChrome = $true
        # ...
    }

    ScoopTools = @{                   # $false でスキップ
        "7zip" = $true
        # ...
    }

    Network = @{                      # 07-configure-network.ps1 でのみ使用
        Enabled = $false
        # ...
    }
}
```

全設定項目は `config/example.psd1` を参照してください。

## SSH 接続方法

### LAN 内からの接続

```bash
ssh <ユーザー名>@<WindowsのIPアドレス>
```

### Tailscale 経由の接続（推奨）

LAN 外からの接続には Tailscale を推奨します。TCP 22 をルーターでポート開放する必要がなく、安全です。

1. Windows 側で Tailscale にログイン:
   ```powershell
   tailscale login
   ```

2. Tailscale の IP を確認:
   ```powershell
   tailscale ip -4
   ```

   > `tailscale` コマンドが見つからない場合は、`C:\Program Files\Tailscale\tailscale.exe` を試してください。

3. Mac 側でも Tailscale に接続し、Tailscale IP で SSH:
   ```bash
   ssh <ユーザー名>@<TailscaleのIP>
   ```

## 固定 IP 設定

**固定 IP は `setup-all.ps1` には含まれません。** 意図的に別実行としています。

ネットワーク設定の変更は接続断のリスクがあるため、十分に理解した上で実行してください。

### 設定方法

1. `config/local.psd1` の `Network` セクションを編集:

```powershell
Network = @{
    Enabled        = $true
    IPAddress      = "192.168.100.5"   # 自分の環境に合わせて変更
    PrefixLength   = 16                # /16 = 255.255.0.0
    Gateway        = ""                # 空欄で現在の値を使用
    DnsServers     = @()               # 空で現在の値を維持
    AdapterName    = ""                # 空欄で対話的に選択
    InterfaceIndex = $null             # 指定する場合は整数
}
```

> **注意**:
> - `/16` は `255.255.0.0` に相当します（65,534 ホスト）
> - `192.168.100.5` はサンプル値です。自分のネットワーク環境に合わせて変更してください
> - 設定する IP アドレスは、ルーターの DHCP 配布範囲外であるか、DHCP 予約されている必要があります

2. Dry Run で確認:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\07-configure-network.ps1 -WhatIf
```

3. 実行:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\07-configure-network.ps1
```

### DHCP へ戻す方法

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\07-configure-network.ps1 -RevertToDHCP
```

または手動で:

```powershell
# InterfaceIndex は Get-NetAdapter で確認
Set-NetIPInterface -InterfaceIndex <InterfaceIndex> -Dhcp Enabled
Set-DnsClientServerAddress -InterfaceIndex <InterfaceIndex> -ResetServerAddresses
```

## IME 設定 / Win+Space

このリポジトリには、AutoHotkey v2 で `Win + Space` を日本語 IME のオン・オフトグルに置き換えるスクリプトが含まれています。

- **IME オフ**: 英数入力
- **IME オン**: ひらがな入力

> **注意**:
> - Windows 標準の `Win + Space` による言語切替を上書きします
> - 管理者権限で起動したアプリ（管理者 PowerShell 等）では、通常権限で実行中の AutoHotkey が効かない場合があります。この場合は AutoHotkey を管理者として実行するか、タスクスケジューラで最高権限で起動する設定にしてください。
> - スクリプトは Windows の Startup フォルダに配置され、ログイン時に自動起動します

## CopyQ 設定

CopyQ はクリップボードマネージャーです。WinGet でインストールされますが、以下は手動で設定してください。

### 推奨設定

1. **表示ショートカット**: `Win + Alt + V` に変更
   - CopyQ を起動 → File → Preferences → Shortcuts → Show/hide main window
2. **Windows 標準クリップボード履歴との重複回避**:
   - Settings → System → Clipboard → Clipboard history を OFF にする
3. **秘密情報の除外**: 1Password などのパスワードマネージャーのウィンドウを除外する
   - File → Preferences → Items → 除外するウィンドウタイトルに `1Password` を追加

> **セキュリティ**: クリップボード履歴にパスワードや API キーが保存されないよう、除外設定を必ず行ってください。

## アップデート方法

```powershell
cd windows-first-setup
git pull
pwsh -ExecutionPolicy Bypass -File .\scripts\setup-all.ps1
```

スクリプトは冪等に設計されているため、複数回実行しても安全です。既にインストール済みのツールはスキップまたはアップグレードされます。

## 再実行方法

個別のスクリプトを再実行できます:

```powershell
# 例: WinGet アプリだけ再インストール
pwsh -ExecutionPolicy Bypass -File .\scripts\02-install-winget-apps.ps1

# 例: 検証だけ実行
pwsh -ExecutionPolicy Bypass -File .\scripts\09-verify.ps1
```

## アンインストール / ロールバック

このリポジトリにはアンインストールスクリプトはありません。個別にアンインストールしてください。

```powershell
# WinGet でインストールしたアプリ
winget uninstall --id <PackageId>

# Scoop でインストールしたツール
scoop uninstall <tool-name>

# Scoop 本体
scoop uninstall scoop

# AutoHotkey スクリプトの削除
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\win-space-ime.ahk"

# SSH デフォルトシェルを元に戻す
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'DefaultShell'
Restart-Service sshd

# 固定IPをDHCPに戻す
.\scripts\07-configure-network.ps1 -RevertToDHCP
```

## Claude Code への引き継ぎ

セットアップ完了後、Claude Code を使って以降の作業を進められます。

```powershell
# 初回はブラウザー認証が必要（Windows本体のデスクトップで実行）
claude

# ログイン後は SSH 経由でも利用可能
claude
```

Claude Code に以下のような作業を依頼できます:

- 追加のツールやアプリのインストール
- 開発環境のカスタマイズ
- プロジェクトのセットアップ
- シェルスクリプトの作成

## セキュリティ注意事項

詳細は [docs/security.md](docs/security.md) を参照してください。

- **公開リポジトリに秘密情報を含めない**: パスワード、API キー、SSH 秘密鍵、メールアドレスなど
- **`config/local.psd1` をコミットしない**: `.gitignore` に含まれています
- **TCP 22 をルーターでポート開放しない**: 外部からの接続には Tailscale を使用してください
- **`irm | iex` の危険性**: リモートスクリプトの直接実行にはリスクがあります
- **公開鍵ログイン確認前にパスワード認証を無効化しない**

## トラブルシューティング

詳細は [docs/troubleshooting.md](docs/troubleshooting.md) を参照してください。

### よくある問題

| 問題 | 解決方法 |
|---|---|
| `winget` が見つからない | Microsoft Store から App Installer をインストール |
| Microsoft アカウントで SSH できない | Bootstrap スクリプトで公開鍵を貼り付けて登録 |
| `sshd` が起動しない | `Get-Service sshd` で状態確認、イベントログ確認 |
| `Permission denied (publickey)` | `administrators_authorized_keys` の ACL を確認 |
| `claude` が見つからない | `npm install -g @anthropic-ai/claude-code` を再実行 |
| `tailscale` が見つからない | `C:\Program Files\Tailscale\tailscale.exe` を試す |
| 固定 IP 後に通信できない | `.\scripts\07-configure-network.ps1 -RevertToDHCP` |

## ライセンス

[MIT License](LICENSE)
