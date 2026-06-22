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
        -Profile @('Domain', 'Private') | Out-Null
    Write-OK "Firewall ルール 'OpenSSH-Server-In-TCP' を作成しました (Domain/Private プロファイルのみ)"
    Write-Warn "Public プロファイルでは TCP 22 を許可していません。外部からの接続には Tailscale の利用を推奨します。"
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

# --- SSH公開鍵の登録方法 ---
Write-Step "SSH 公開鍵の登録方法"
Write-Host ""
Write-Host "  別のPCから以下のコマンドで公開鍵を登録できます:" -ForegroundColor White
Write-Host ""

# 管理者ユーザーの場合
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$adminGroupMembers = @()
try {
    $adminGroupMembers = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*\$currentUser" }
} catch {
    # Get-LocalGroupMember が失敗する場合がある
}

$authKeysPath = Join-Path $env:USERPROFILE '.ssh\authorized_keys'
$adminAuthKeysPath = 'C:\ProgramData\ssh\administrators_authorized_keys'

if ($adminGroupMembers -or $isAdmin) {
    Write-Host "  ※ $currentUser は Administrators グループのメンバーです。" -ForegroundColor Yellow
    Write-Host "  ※ 管理者ユーザーの場合、以下のファイルに公開鍵を登録する必要があります:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    $adminAuthKeysPath" -ForegroundColor White
    Write-Host ""
    Write-Host "  【Mac/Linux から実行】" -ForegroundColor White
    Write-Host "  # 公開鍵をWindowsへコピー" -ForegroundColor DarkGray
    foreach ($ip in $ipAddresses) {
        Write-Host "  scp ~/.ssh/id_ed25519.pub ${currentUser}@${ip}:C:\ProgramData\ssh\" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  【Windows側で管理者PowerShellから実行】" -ForegroundColor White
    Write-Host "  # 公開鍵ファイルを administrators_authorized_keys に追加" -ForegroundColor DarkGray
    Write-Host "  Get-Content C:\ProgramData\ssh\id_ed25519.pub | Add-Content $adminAuthKeysPath" -ForegroundColor White
    Write-Host "  Remove-Item C:\ProgramData\ssh\id_ed25519.pub" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  # ACLを正しく設定 (重要)" -ForegroundColor DarkGray
    Write-Host '  icacls $env:ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"' -ForegroundColor White
    Write-Host ""
    Write-Host "  【または、Mac/Linux から ssh-copy-id 風に実行 (標準ユーザー用)】" -ForegroundColor White
    Write-Host "  ※ 管理者ユーザーでは ssh-copy-id は administrators_authorized_keys に書き込まないため、上記の手動方法を推奨します。" -ForegroundColor Yellow
} else {
    Write-Host "  【Mac/Linux から実行】" -ForegroundColor White
    foreach ($ip in $ipAddresses) {
        Write-Host "  ssh-copy-id -i ~/.ssh/id_ed25519.pub ${currentUser}@${ip}" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "  【接続テスト】" -ForegroundColor White
foreach ($ip in $ipAddresses) {
    Write-Host "  ssh ${currentUser}@${ip}" -ForegroundColor White
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  Bootstrap 完了!" -ForegroundColor Green
Write-Host "  SSH接続後、リポジトリをcloneしてセットアップを続けてください。" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
