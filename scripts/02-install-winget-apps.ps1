<#
.SYNOPSIS
    WinGet で GUI アプリをインストールする
.DESCRIPTION
    設定ファイルで有効なアプリのみインストールする。
    インストール済みのアプリはスキップまたはアップグレードする。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 2: WinGet アプリのインストール"

# winget の存在確認
$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wingetCmd) {
    Write-Fail "winget が見つかりません。"
    Write-Host "  Microsoft Store から 'App Installer' をインストールしてください。"
    Write-Host "  または: Add-AppxPackage -RegisterByFamilyName Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"
    exit 1
}

$config = Read-Config

# WinGet Package ID マッピング
$appMap = [ordered]@{
    GoogleChrome    = @{ Id = 'Google.Chrome';                    Name = 'Google Chrome' }
    Slack           = @{ Id = 'SlackTechnologies.Slack';          Name = 'Slack' }
    Cursor          = @{ Id = 'Anysphere.Cursor';                Name = 'Cursor' }
    OnePassword     = @{ Id = 'AgileBits.1Password';             Name = '1Password' }
    Tailscale       = @{ Id = 'Tailscale.Tailscale';             Name = 'Tailscale' }
    Discord         = @{ Id = 'Discord.Discord';                 Name = 'Discord' }
    AutoHotkey      = @{ Id = 'AutoHotkey.AutoHotkey';           Name = 'AutoHotkey v2' }
    CopyQ           = @{ Id = 'hluk.CopyQ';                     Name = 'CopyQ' }
    PowerToys       = @{ Id = 'Microsoft.PowerToys';             Name = 'PowerToys' }
    WindowsTerminal = @{ Id = 'Microsoft.WindowsTerminal';       Name = 'Windows Terminal' }
    PowerShell7     = @{ Id = 'Microsoft.PowerShell';            Name = 'PowerShell 7' }
    Git             = @{ Id = 'Git.Git';                         Name = 'Git' }
}

$results = @()
$failCount = 0

foreach ($key in $appMap.Keys) {
    $app = $appMap[$key]

    # 設定で無効化されている場合はスキップ
    $enabled = $true
    if ($config.WinGetApps -and $config.WinGetApps.ContainsKey($key)) {
        $enabled = $config.WinGetApps[$key]
    }

    if (-not $enabled) {
        Write-Host "[SKIP] $($app.Name) (設定で無効化)"
        $results += @{ Name = $app.Name; Status = 'SKIP'; Detail = '設定で無効化' }
        continue
    }

    $success = Install-WinGetApp -PackageId $app.Id -AppName $app.Name
    if ($success) {
        $results += @{ Name = $app.Name; Status = 'OK'; Detail = $app.Id }
    } else {
        $results += @{ Name = $app.Name; Status = 'FAIL'; Detail = "インストール失敗: $($app.Id)" }
        $failCount++
    }
}

# PATH の再読み込み
Refresh-PathEnv

# 結果表示
Write-Step "WinGet インストール結果"
Show-ResultTable -Results $results

if ($failCount -gt 0) {
    Write-Warn "$failCount 個のアプリのインストールに失敗しました。上記の結果を確認してください。"
} else {
    Write-OK "Phase 2: すべての WinGet アプリのインストール完了"
}
