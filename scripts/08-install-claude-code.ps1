<#
.SYNOPSIS
    Claude Code をインストールする
.DESCRIPTION
    Claude Code の公式インストール方法を使用してインストールする。
    セットアップの最後に実行することを推奨。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 8: Claude Code インストール"

# --- Node.js の確認 ---
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Refresh-PathEnv
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
}

if (-not $nodeCmd) {
    Write-Fail "Node.js が見つかりません。先に Scoop ツールをインストールしてください。"
    Write-Host "  scoop install nodejs-lts"
    exit 1
}

$nodeVersion = node --version
Write-OK "Node.js: $nodeVersion"

# --- Claude Code の確認 ---
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Refresh-PathEnv
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
}

if ($claudeCmd) {
    $claudeVersion = claude --version 2>$null
    Write-OK "Claude Code は既にインストール済み: $claudeVersion"
    Write-Host "  アップデートを確認中..."
    try {
        npm update -g @anthropic-ai/claude-code 2>$null | Out-Null
        $claudeVersion = claude --version 2>$null
        Write-OK "Claude Code: $claudeVersion"
    } catch {
        Write-Warn "Claude Code のアップデートに失敗: $_"
    }
} else {
    Write-Host "Claude Code をインストール中..."
    try {
        npm install -g @anthropic-ai/claude-code 2>&1 | Out-Null
        Refresh-PathEnv

        $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
        if ($claudeCmd) {
            $claudeVersion = claude --version 2>$null
            Write-OK "Claude Code をインストールしました: $claudeVersion"
        } else {
            Write-Warn "Claude Code のインストールは完了しましたが、PATHに見つかりません。"
            Write-Host "  新しいターミナルを開くか、以下を実行してPATHを更新してください:"
            Write-Host '  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")'
        }
    } catch {
        Write-Fail "Claude Code のインストールに失敗: $_"
        Write-Host "  手動でインストールしてください:"
        Write-Host "  npm install -g @anthropic-ai/claude-code"
        exit 1
    }
}

# --- 初回ログインの案内 ---
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  Claude Code の初回ログイン" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Claude Code の初回ログインはブラウザー認証が必要です。" -ForegroundColor Yellow
Write-Host "  Windows本体のデスクトップ環境で以下を実行してください:" -ForegroundColor Yellow
Write-Host ""
Write-Host "    claude" -ForegroundColor White
Write-Host ""
Write-Host "  ブラウザーが開くので、Anthropicアカウントでログインしてください。"
Write-Host "  ログイン後は、SSH経由でも Claude Code を利用できます。"
Write-Host ""

Write-OK "Phase 8: Claude Code インストール完了"
