<#
.SYNOPSIS
    Datadog 軽量メトリクスコレクタをインストールする
.DESCRIPTION
    CPU / メモリ / GPU メトリクスを Datadog の Metrics API に直接送る
    PowerShell コレクタを配置し、ログオン時に自動起動するタスクを登録する。

    公式 Datadog Agent の GPU インテグレーションは NVIDIA 専用のため、
    AMD/Intel GPU でも値が取れるよう Windows のパフォーマンスカウンタを使用する。

    APIキー等は config\local.psd1 の Datadog ブロックから読み込み、
    配置先スクリプトに焼き込む (リポジトリには鍵をコミットしない)。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 10: Datadog メトリクスコレクタ"

$config = Read-Config

# --- 設定の取り出し (デフォルト付き) ---
$dd = if ($config.ContainsKey('Datadog')) { $config.Datadog } else { @{} }
$enabled  = if ($dd.ContainsKey('Enabled'))  { [bool]$dd.Enabled }  else { $false }
$apiKey   = if ($dd.ContainsKey('ApiKey'))   { [string]$dd.ApiKey } else { '' }
$site     = if ($dd.ContainsKey('Site'))     { [string]$dd.Site }   else { 'datadoghq.com' }
$interval = if ($dd.ContainsKey('Interval')) { [int]$dd.Interval }  else { 15 }

if (-not $enabled) {
    Write-Warn "Datadog はスキップされました (config の Datadog.Enabled = `$false)。"
    Write-Host "  有効化するには config\local.psd1 の Datadog ブロックを設定してください。"
    return
}

if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -eq 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx') {
    Write-Fail "Datadog APIキーが未設定です。config\local.psd1 の Datadog.ApiKey を設定してください。"
    exit 1
}

# --- APIキーの検証 ---
Write-Host "  APIキーを検証中 (site=$site)..."
try {
    $valid = Invoke-RestMethod -Method Get -Uri "https://api.$site/api/v1/validate" `
        -Headers @{ "DD-API-KEY" = $apiKey } -ErrorAction Stop
    if ($valid.valid) {
        Write-OK "APIキーは有効です (site=$site)"
    } else {
        Write-Fail "APIキーが無効です (site=$site)。"
        exit 1
    }
} catch {
    Write-Fail "APIキー検証に失敗しました: $_"
    Write-Host "  サイト指定が正しいか確認してください (datadoghq.com / ap1.datadoghq.com / datadoghq.eu / us5.datadoghq.com など)"
    exit 1
}

# --- コレクタ配置 (テンプレートのトークンを置換して焼き込み) ---
$repoRoot   = Split-Path $PSScriptRoot -Parent
$template   = Join-Path $repoRoot 'assets\dd-collector.ps1'
$installDir = Join-Path $env:LOCALAPPDATA 'dd-collector'
$target     = Join-Path $installDir 'dd-collector.ps1'

if (-not (Test-Path $template)) {
    Write-Fail "コレクタテンプレートが見つかりません: $template"
    exit 1
}

if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

$content = Get-Content $template -Raw
$content = $content.Replace('__DD_API_KEY__',  $apiKey)
$content = $content.Replace('__DD_SITE__',     $site)
$content = $content.Replace('__DD_INTERVAL__', [string]$interval)
Set-Content -Path $target -Value $content -Encoding UTF8

Write-OK "コレクタを配置しました: $target"

# --- スケジュールタスク登録 (ログオン時自動起動) ---
$taskName = 'DatadogMetricsCollector'
$ps       = (Get-Command powershell.exe).Source
$me       = whoami

$action  = New-ScheduledTaskAction -Execute $ps `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $me
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal `
    -Description "CPU/GPU/Memory -> Datadog ($site). 自動起動 (logon)。" -Force | Out-Null

Write-OK "スケジュールタスクを登録しました: $taskName (ログオン時自動起動)"

# --- 既存プロセスを再起動して即反映 ---
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName $taskName

Write-Host "  起動確認中..."
Start-Sleep -Seconds 8
$state = (Get-ScheduledTask -TaskName $taskName).State
if ($state -eq 'Running') {
    Write-OK "コレクタは実行中です (送信間隔 ${interval}s)"
} else {
    Write-Warn "タスク状態: $state — 次回ログオン時に起動します。"
}

Write-Host ""
Write-Host "  送信メトリクス: system.cpu.percent / system.mem.* / gpu.utilization.percent / gpu.memory.dedicated_bytes"
Write-Host "  ログ: $installDir\dd-collector.log"
Write-Host ""

Write-OK "Phase 10: Datadog メトリクスコレクタ 完了"
