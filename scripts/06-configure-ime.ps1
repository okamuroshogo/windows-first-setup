<#
.SYNOPSIS
    IME設定とAutoHotkeyスクリプトの配置
.DESCRIPTION
    日本語Microsoft IMEを維持しつつ、AutoHotkey v2 で Win+Space を
    IMEオン・オフのトグルに設定する。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 6: IME 設定"

$config = Read-Config

# --- AutoHotkey の確認 ---
if ($config.EnableAutoHotkey -eq $false) {
    Write-Host "[SKIP] AutoHotkey 設定はスキップ (設定で無効化)"
    Write-OK "Phase 6: IME 設定完了 (スキップ)"
    return
}

# AutoHotkey v2 の存在確認
$ahkExe = $null
$ahkPaths = @(
    (Get-Command 'AutoHotkey64.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    (Get-Command 'AutoHotkey.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'),
    (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'AutoHotkey\v2\AutoHotkey64.exe')
)

foreach ($path in $ahkPaths) {
    if ($path -and (Test-Path $path)) {
        $ahkExe = $path
        break
    }
}

if (-not $ahkExe) {
    Write-Warn "AutoHotkey v2 が見つかりません。先に WinGet でインストールしてください。"
    Write-Host "  winget install AutoHotkey.AutoHotkey"
    Write-OK "Phase 6: IME 設定完了 (AutoHotkey未インストール)"
    return
}

Write-OK "AutoHotkey を検出: $ahkExe"

# --- AHKスクリプトをStartupフォルダへコピー ---
Write-Step "AutoHotkey スクリプトの配置"

$repoRoot = Split-Path $PSScriptRoot -Parent
$sourceAhk = Join-Path $repoRoot 'assets\win-space-ime.ahk'
$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$destAhk = Join-Path $startupDir 'win-space-ime.ahk'

if (-not (Test-Path $sourceAhk)) {
    Write-Fail "AHKスクリプトが見つかりません: $sourceAhk"
    exit 1
}

# コピー (既存ファイルは上書き)
Copy-Item -Path $sourceAhk -Destination $destAhk -Force
Write-OK "AHKスクリプトを Startup フォルダへコピー: $destAhk"

# --- 既存の AHK プロセスを停止して再起動 ---
Write-Step "AutoHotkey スクリプトの起動"

# 既存の win-space-ime.ahk プロセスを停止
$existingProcesses = Get-Process -Name 'AutoHotkey*' -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -match 'win-space-ime' -or $_.CommandLine -match 'win-space-ime' }

if ($existingProcesses) {
    $existingProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Write-OK "既存の AHK プロセスを停止しました"
}

# 新しいプロセスを起動
Start-Process -FilePath $ahkExe -ArgumentList $destAhk
Write-OK "AutoHotkey スクリプトを起動しました"

# --- 言語設定の確認 ---
Write-Step "言語設定の確認"

try {
    $languages = Get-WinUserLanguageList
    Write-Host "  現在の言語リスト:"
    foreach ($lang in $languages) {
        Write-Host "    - $($lang.LanguageTag): $($lang.LocalizedName)" -ForegroundColor DarkGray
        foreach ($kb in $lang.InputMethodTips) {
            Write-Host "      キーボード: $kb" -ForegroundColor DarkGray
        }
    }
} catch {
    Write-Warn "言語設定の取得に失敗: $_"
}

Write-Host ""
Write-Host "  ※ Win+Space で IME のオン・オフを切り替えられます。" -ForegroundColor White
Write-Host "  ※ Windows標準の Win+Space 言語切替を上書きしています。" -ForegroundColor Yellow
Write-Host "  ※ 管理者権限で起動したアプリでは、通常権限の AutoHotkey が効かない場合があります。" -ForegroundColor Yellow

Write-OK "Phase 6: IME 設定完了"
