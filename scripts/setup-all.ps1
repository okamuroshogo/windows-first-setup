#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 初期セットアップを一括実行する
.DESCRIPTION
    Phase 1～8 を順番に実行し、最後に検証を行う。
    固定IPの設定 (07-configure-network.ps1) は含まない。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Assert-Admin

$scriptDir = $PSScriptRoot
$startTime = Get-Date
$needsReboot = $false

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  Windows 初期セットアップ" -ForegroundColor Cyan
Write-Host "  開始: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

# --- Phase 定義 ---
$phases = @(
    @{
        Name     = 'Phase 1: 基本環境'
        Script   = '01-base-setup.ps1'
        Critical = $true
    },
    @{
        Name     = 'Phase 2: WinGet アプリ'
        Script   = '02-install-winget-apps.ps1'
        Critical = $false
    },
    @{
        Name     = 'Phase 3: Scoop ツール'
        Script   = '03-install-scoop-tools.ps1'
        Critical = $false
    },
    @{
        Name     = 'Phase 4: Git 設定'
        Script   = '04-configure-git.ps1'
        Critical = $false
    },
    @{
        Name     = 'Phase 5: SSHD 設定'
        Script   = '05-configure-sshd.ps1'
        Critical = $false
    },
    @{
        Name     = 'Phase 6: IME 設定'
        Script   = '06-configure-ime.ps1'
        Critical = $false
    },
    @{
        Name     = 'Phase 8: Claude Code'
        Script   = '08-install-claude-code.ps1'
        Critical = $false
    }
)

$phaseResults = @()

foreach ($phase in $phases) {
    $scriptPath = Join-Path $scriptDir $phase.Script

    if (-not (Test-Path $scriptPath)) {
        Write-Fail "$($phase.Name): スクリプトが見つかりません: $scriptPath"
        $phaseResults += @{ Name = $phase.Name; Status = 'FAIL'; Detail = 'スクリプト未検出' }
        if ($phase.Critical) {
            Write-Fail "必須フェーズが失敗したため、セットアップを中断します。"
            break
        }
        continue
    }

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  $($phase.Name) 開始" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    try {
        & $scriptPath
        $exitCode = $LASTEXITCODE

        if ($exitCode -and $exitCode -ne 0) {
            throw "終了コード: $exitCode"
        }

        Write-Host ""
        Write-OK "$($phase.Name) 成功"
        $phaseResults += @{ Name = $phase.Name; Status = 'OK'; Detail = '成功' }
    } catch {
        Write-Host ""
        Write-Fail "$($phase.Name) 失敗: $_"
        $phaseResults += @{ Name = $phase.Name; Status = 'FAIL'; Detail = $_.ToString() }

        if ($phase.Critical) {
            Write-Fail "必須フェーズが失敗したため、セットアップを中断します。"
            break
        } else {
            Write-Warn "このフェーズの失敗は致命的ではありません。続行します。"
        }
    }

    # PATH を更新 (新しいツールがインストールされた可能性)
    Refresh-PathEnv
}

# --- 検証 ---
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Phase 9: 検証" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$verifyScript = Join-Path $scriptDir '09-verify.ps1'
if (Test-Path $verifyScript) {
    & $verifyScript
} else {
    Write-Warn "検証スクリプトが見つかりません: $verifyScript"
}

# --- 結果サマリー ---
$endTime = Get-Date
$elapsed = $endTime - $startTime

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  セットアップ完了サマリー" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

Show-ResultTable -Results $phaseResults

Write-Host "  実行時間: $($elapsed.Minutes)分 $($elapsed.Seconds)秒"
Write-Host ""

$failedPhases = $phaseResults | Where-Object { $_.Status -eq 'FAIL' }
if ($failedPhases) {
    Write-Warn "$($failedPhases.Count) 個のフェーズが失敗しました:"
    foreach ($f in $failedPhases) {
        Write-Host "    - $($f.Name): $($f.Detail)" -ForegroundColor Red
    }
    Write-Host ""
}

# --- 再起動の確認 ---
if ($needsReboot) {
    Write-Host ""
    Write-Warn "一部の変更を反映するには再起動が必要です。"
    Write-Host "  再起動するには: Restart-Computer"
    Write-Host "  再起動後、セットアップを再実行しても安全です (冪等)。"
}

# --- 次のステップ ---
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  次のステップ" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  1. Tailscale にログイン:    tailscale login" -ForegroundColor White
Write-Host "  2. Claude Code にログイン:  claude  (ブラウザーで認証)" -ForegroundColor White
Write-Host "  3. 1Password にログイン:    1Password アプリを起動" -ForegroundColor White
Write-Host ""
Write-Host "  固定IPが必要な場合:" -ForegroundColor DarkGray
Write-Host "    .\scripts\07-configure-network.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  以後は Claude Code に作業を引き継ぐことができます:" -ForegroundColor DarkGray
Write-Host "    claude" -ForegroundColor White
Write-Host ""
