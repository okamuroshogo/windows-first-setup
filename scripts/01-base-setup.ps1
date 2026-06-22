#Requires -RunAsAdministrator
<#
.SYNOPSIS
    基本環境のセットアップ (PowerShell 7, Windows Terminal, Git, WinGet更新)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 1: 基本環境セットアップ"

# --- 設定読み込み ---
$config = Read-Config

# --- WinGet source 更新 ---
Write-Step "WinGet source の更新"
try {
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        winget source update | Out-Null
        Write-OK "WinGet source を更新しました"
    } else {
        Write-Warn "winget が見つかりません。Microsoft Store から App Installer をインストールしてください。"
    }
} catch {
    Write-Warn "WinGet source の更新に失敗: $_"
}

# --- PowerShell 7 ---
Write-Step "PowerShell 7 の確認"
$pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwshPath) {
    $pwshVersion = & pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
    Write-OK "PowerShell $pwshVersion が既にインストール済み"
} else {
    Write-Host "PowerShell 7 をインストール中..."
    $result = Install-WinGetApp -PackageId 'Microsoft.PowerShell' -AppName 'PowerShell 7'
    if (-not $result) {
        Write-Fail "PowerShell 7 のインストールに失敗しました。後続処理に支障があります。"
        exit 1
    }
    # PATH を更新
    Refresh-PathEnv
    Write-OK "PowerShell 7 をインストールしました"
}

# --- Git ---
Write-Step "Git の確認"
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $gitVersion = git --version
    Write-OK "$gitVersion が既にインストール済み"
} else {
    Write-Host "Git をインストール中..."
    $result = Install-WinGetApp -PackageId 'Git.Git' -AppName 'Git'
    if (-not $result) {
        Write-Fail "Git のインストールに失敗しました。後続処理に支障があります。"
        exit 1
    }
    Refresh-PathEnv
    Write-OK "Git をインストールしました"
}

# --- Windows Terminal ---
Write-Step "Windows Terminal の確認"
$wtInstalled = Test-WinGetInstalled -PackageId 'Microsoft.WindowsTerminal'
if ($wtInstalled) {
    Write-OK "Windows Terminal は既にインストール済み"
} else {
    Write-Host "Windows Terminal をインストール中..."
    Install-WinGetApp -PackageId 'Microsoft.WindowsTerminal' -AppName 'Windows Terminal'
}

# --- PC名変更 (任意) ---
if ($config.ComputerName -and $config.ComputerName -ne '' -and $config.ComputerName -ne $env:COMPUTERNAME) {
    Write-Step "PC名の変更"
    Write-Host "  現在のPC名: $env:COMPUTERNAME"
    Write-Host "  新しいPC名: $($config.ComputerName)"
    try {
        Rename-Computer -NewName $config.ComputerName -Force
        Write-OK "PC名を '$($config.ComputerName)' に変更しました"
        Write-Warn "PC名の変更を反映するには再起動が必要です。"
        $script:NeedsReboot = $true
    } catch {
        Write-Fail "PC名の変更に失敗: $_"
    }
} else {
    Write-Host "[SKIP] PC名の変更はスキップ (設定なし)"
}

# --- スリープ無効化 (任意) ---
if ($config.DisableSleep -eq $true) {
    Write-Step "スリープの無効化"
    try {
        powercfg /change standby-timeout-ac 0
        powercfg /change standby-timeout-dc 0
        powercfg /change monitor-timeout-ac 0
        powercfg /change monitor-timeout-dc 0
        Write-OK "スリープとモニターオフを無効化しました"
    } catch {
        Write-Warn "スリープ設定の変更に失敗: $_"
    }
} else {
    Write-Host "[SKIP] スリープ設定の変更はスキップ (設定なし)"
}

# --- Windows Update 確認方法の案内 ---
Write-Step "Windows Update の確認"
Write-Host "  Windows Update は以下のコマンドで確認できます:"
Write-Host "    # PowerShell 7" -ForegroundColor DarkGray
Write-Host '    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser' -ForegroundColor White
Write-Host '    Get-WindowsUpdate' -ForegroundColor White
Write-Host '    Install-WindowsUpdate -AcceptAll' -ForegroundColor White
Write-Host ""
Write-Host "  または Settings > Windows Update から手動で確認してください。"

Write-OK "Phase 1: 基本環境セットアップ完了"
