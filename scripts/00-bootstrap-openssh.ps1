#Requires -RunAsAdministrator
<#
.SYNOPSIS
    OpenSSH Server をインストール・起動し、SSH接続できる状態にする。
.DESCRIPTION
    Windows 11 新規インストール直後に管理者PowerShellで実行する最初のスクリプト。
    Windows PowerShell 5.1 でも動作する。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PowerShell 5.1 では TLS 1.2 がデフォルトでないため、GitHub 等への HTTPS 接続に必要
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step  { param([string]$Msg) Write-Host "`n[*] $Msg" -ForegroundColor Cyan }
function Write-OK    { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "[WARN] $Msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Msg) Write-Host "[FAIL] $Msg" -ForegroundColor Red }

# --- 管理者権限チェック ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Fail "このスクリプトは管理者として実行してください。"
    Write-Host "PowerShellを右クリック → 「管理者として実行」で開き直してください。"
    exit 1
}

# --- OpenSSH Client ---
Write-Step "OpenSSH Client の確認"
$sshClient = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Client*' }
if ($sshClient.State -eq 'Installed') {
    Write-OK "OpenSSH Client は既にインストール済み"
} else {
    Write-Host "OpenSSH Client をインストール中..."
    Add-WindowsCapability -Online -Name $sshClient.Name | Out-Null
    Write-OK "OpenSSH Client をインストールしました"
}

# --- OpenSSH Server ---
Write-Step "OpenSSH Server の確認"
$sshServer = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }
if ($sshServer.State -eq 'Installed') {
    Write-OK "OpenSSH Server は既にインストール済み"
} else {
    Write-Host "OpenSSH Server をインストール中..."
    Add-WindowsCapability -Online -Name $sshServer.Name | Out-Null
    Write-OK "OpenSSH Server をインストールしました"
}

# --- sshdサービスの設定 ---
Write-Step "sshd サービスの設定"
$sshdService = Get-Service -Name sshd -ErrorAction SilentlyContinue
if (-not $sshdService) {
    Write-Fail "sshd サービスが見つかりません。OpenSSH Server のインストールに失敗した可能性があります。"
    exit 1
}

# 自動起動に設定
if ($sshdService.StartType -ne 'Automatic') {
    Set-Service -Name sshd -StartupType Automatic
    Write-OK "sshd を自動起動に設定しました"
} else {
    Write-OK "sshd は既に自動起動に設定済み"
}

# サービス開始
if ($sshdService.Status -ne 'Running') {
    Start-Service sshd
    Write-OK "sshd サービスを開始しました"
} else {
    Write-OK "sshd サービスは既に実行中"
}

# --- Firewall ルール ---
Write-Step "Windows Defender Firewall の確認"
$firewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($firewallRule) {
    if ($firewallRule.Enabled -eq 'True') {
        Write-OK "Firewall ルール 'OpenSSH-Server-In-TCP' は既に有効"
    } else {
        Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
        Write-OK "Firewall ルール 'OpenSSH-Server-In-TCP' を有効化しました"
    }
} else {
    # OpenSSH Server インストール時に自動作成されない場合のフォールバック
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
        -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 `
        -Profile Any | Out-Null
    Write-OK "Firewall ルール 'OpenSSH-Server-In-TCP' を作成しました"
}

# ネットワークプロファイルが Public の場合でも接続できるよう、既存ルールを全プロファイルに更新
$existingRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($existingRule -and $existingRule.Profile -ne 'Any') {
    Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile Any
    Write-OK "Firewall ルールを全プロファイル (Any) に更新しました"
}

# --- SSH 公開鍵の登録 ---
# Microsoft アカウントではパスワード認証が使えないため、
# この段階で公開鍵を登録しないと SSH 接続できない。
Write-Step "SSH 公開鍵の登録"

$adminAuthKeysPath = 'C:\ProgramData\ssh\administrators_authorized_keys'

# 既に公開鍵が登録済みかチェック
$existingKeys = $false
if (Test-Path $adminAuthKeysPath) {
    $content = Get-Content $adminAuthKeysPath -ErrorAction SilentlyContinue
    if ($content -and ($content | Where-Object { $_ -match '^ssh-' })) {
        $existingKeys = $true
        Write-OK "administrators_authorized_keys に既に公開鍵が登録されています"
        Write-Host "  既存の鍵:" -ForegroundColor DarkGray
        foreach ($line in $content) {
            if ($line -match '^ssh-') {
                # 鍵の末尾コメント部分だけ表示
                $parts = $line -split '\s+'
                $keyType = $parts[0]
                if ($parts.Count -ge 3) { $comment = $parts[2..($parts.Count-1)] -join ' ' } else { $comment = '(no comment)' }
                Write-Host "    $keyType ... $comment" -ForegroundColor DarkGray
            }
        }
    }
}

if (-not $existingKeys) {
    # GitHub から公開鍵を自動取得
    $githubUser = 'okamuroshogo'
    $githubKeysUrl = "https://github.com/${githubUser}.keys"
    $keysToRegister = $null

    Write-Host "  GitHub (${githubKeysUrl}) から公開鍵を取得中..." -ForegroundColor White
    try {
        $rawKeys = Invoke-RestMethod -Uri $githubKeysUrl -TimeoutSec 10
        if ($rawKeys) {
            $keysToRegister = ($rawKeys.Trim() -split "`n") | Where-Object { $_ -match '^ssh-' }
        }
    } catch {
        Write-Warn "GitHub からの取得に失敗しました: $($_.Exception.Message)"
    }

    if ($keysToRegister -and @($keysToRegister).Count -gt 0) {
        Write-OK "GitHub から $(@($keysToRegister).Count) 個の公開鍵を取得しました"
        foreach ($key in $keysToRegister) {
            $parts = $key -split '\s+'
            Write-Host "    $($parts[0]) $($parts[1].Substring(0, 20))..." -ForegroundColor DarkGray
        }

        # ssh ディレクトリの確認
        $sshDir = Join-Path $env:ProgramData 'ssh'
        if (-not (Test-Path $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        }

        # 公開鍵を書き込み (BOM なし UTF-8)
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        $newContent = ($keysToRegister -join "`n") + "`n"
        [System.IO.File]::WriteAllText($adminAuthKeysPath, $newContent, $utf8NoBom)

        # ACL を設定 (SYSTEM と Administrators のみ)
        icacls $adminAuthKeysPath /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

        Write-OK "公開鍵を administrators_authorized_keys に登録しました"
        Write-OK "ACL を設定しました (Administrators:F, SYSTEM:F)"
    } else {
        Write-Fail "GitHub から公開鍵を取得できませんでした。"
        Write-Host "  https://github.com/settings/keys に SSH 鍵が登録されているか確認してください。" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  手動で登録する場合、接続元で以下を実行して公開鍵をコピーしてください:" -ForegroundColor White
        Write-Host "    cat ~/.ssh/id_ed25519.pub" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  コピーした公開鍵を貼り付けて Enter を押してください。" -ForegroundColor White
        Write-Host "  (スキップする場合はそのまま Enter を押してください)" -ForegroundColor DarkGray
        Write-Host ""

        $pubKey = Read-Host "  公開鍵"

        if ($pubKey -and $pubKey -match '^ssh-(ed25519|rsa|ecdsa)') {
            $sshDir = Join-Path $env:ProgramData 'ssh'
            if (-not (Test-Path $sshDir)) {
                New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
            }

            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($adminAuthKeysPath, "$pubKey`n", $utf8NoBom)

            icacls $adminAuthKeysPath /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

            Write-OK "公開鍵を administrators_authorized_keys に登録しました"
            Write-OK "ACL を設定しました (Administrators:F, SYSTEM:F)"
        } elseif ($pubKey) {
            Write-Fail "公開鍵の形式が正しくありません。ssh-ed25519, ssh-rsa, ssh-ecdsa で始まる文字列を貼り付けてください。"
        } else {
            Write-Warn "公開鍵の登録をスキップしました"
        }
    }
}

# --- 接続情報の表示 ---
Write-Step "接続情報"

$currentUser = $env:USERNAME
Write-Host "  ユーザー名: $currentUser"

# IPv4アドレスを取得 (物理NICのみ)
$ipAddresses = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -ne '127.0.0.1' -and
        $_.InterfaceAlias -notmatch 'Loopback|Tailscale|vEthernet|WSL|Hyper-V'
    } |
    Select-Object -ExpandProperty IPAddress

if ($ipAddresses) {
    foreach ($ip in $ipAddresses) {
        Write-Host "  IPv4 アドレス: $ip"
    }
} else {
    Write-Warn "IPv4 アドレスが見つかりません。ネットワーク接続を確認してください。"
}

Write-Host ""
Write-Host "  【接続テスト (Mac/Linux から実行)】" -ForegroundColor White
foreach ($ip in $ipAddresses) {
    Write-Host "  ssh ${currentUser}@${ip}" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  Bootstrap 完了!" -ForegroundColor Green
Write-Host "  SSH接続後、リポジトリをcloneしてセットアップを続けてください。" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
