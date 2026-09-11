<#
.SYNOPSIS
    Datadog ダッシュボード等を表示するキオスクランチャーをインストールする
.DESCRIPTION
    assets\launch-datadog-kiosk.ps1 を %LOCALAPPDATA%\DatadogKiosk\ に配置し、
    config の DatadogKiosk.Windows からレイアウト (URL・座標) を
    kiosk-layout.json として生成する。ログオン時に自動起動するよう
    Startup フォルダにショートカット (.lnk) を作成する。

    URL には内部ホスト名やダッシュボード ID が含まれるため、リポジトリには
    含めず config\local.psd1 (gitignore 済み) にのみ書く。

    config\local.psd1:
        DatadogKiosk = @{
            Enabled = $true
            Windows = @(
                @{ Match = 'タイトル正規表現'; Url = 'https://...'
                   X = 0; Y = 0; W = 1280; H = 1400 }
            )
        }
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 14: Datadog キオスク"

$config = Read-Config

$kiosk = if ($config.ContainsKey('DatadogKiosk')) { $config.DatadogKiosk } else { @{} }
$enabled = if ($kiosk.ContainsKey('Enabled')) { [bool]$kiosk.Enabled } else { $false }
$windows = if ($kiosk.ContainsKey('Windows')) { @($kiosk.Windows) } else { @() }

if (-not $enabled) {
    Write-Warn "Datadog キオスクはスキップされました (config の DatadogKiosk.Enabled = `$false)。"
    return
}

if ($windows.Count -eq 0) {
    Write-Fail "DatadogKiosk.Windows が空です。config\local.psd1 にレイアウトを設定してください。"
    exit 1
}

# --- スクリプトとレイアウトの配置 ---
$repoRoot   = Split-Path $PSScriptRoot -Parent
$sourcePs1  = Join-Path $repoRoot 'assets\launch-datadog-kiosk.ps1'
$installDir = Join-Path $env:LOCALAPPDATA 'DatadogKiosk'
$target     = Join-Path $installDir 'launch-datadog-kiosk.ps1'
$layoutFile = Join-Path $installDir 'kiosk-layout.json'

if (-not (Test-Path $sourcePs1)) {
    Write-Fail "スクリプトが見つかりません: $sourcePs1"
    exit 1
}

if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

Copy-Item -Path $sourcePs1 -Destination $target -Force
Write-OK "キオスクランチャーを配置: $target"

$layoutJson = @{
    windows = @($windows | ForEach-Object {
        [ordered]@{
            match = [string]$_.Match
            url   = [string]$_.Url
            x     = [int]$_.X
            y     = [int]$_.Y
            w     = [int]$_.W
            h     = [int]$_.H
        }
    })
} | ConvertTo-Json -Depth 4
Set-Content -Path $layoutFile -Value $layoutJson -Encoding UTF8
Write-OK "レイアウトを生成: $layoutFile ($($windows.Count) ウィンドウ)"

# --- Startup ショートカット作成 ---
$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$lnkPath    = Join-Path $startupDir 'datadog-kiosk.lnk'
$ps         = (Get-Command powershell.exe).Source

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath  = $ps
$lnk.Arguments   = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
$lnk.Description = 'Datadog ダッシュボード キオスク起動'
$lnk.Save()
Write-OK "Startup ショートカットを作成: $lnkPath"

# 旧名のショートカットが残っていれば削除
$oldLnk = Join-Path $startupDir 'Datadog GPU Dashboard (Right Display).lnk'
if (Test-Path $oldLnk) {
    Remove-Item $oldLnk -Force
    Write-OK "旧ショートカットを削除: $oldLnk"
}

Write-Host "  今すぐ起動するには: powershell -ExecutionPolicy Bypass -File `"$target`""

Write-OK "Phase 14: Datadog キオスク完了"
