<#
.SYNOPSIS
    Git のグローバル設定を行う
.DESCRIPTION
    config/local.psd1 から Git のユーザー名・メールアドレスを読み込み、設定する。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 4: Git 設定"

# Git の存在確認
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Fail "git が見つかりません。先に 01-base-setup.ps1 を実行してください。"
    exit 1
}

$config = Read-Config

# --- user.name ---
if ($config.GitUserName -and $config.GitUserName -ne '' -and $config.GitUserName -ne 'Your Name') {
    $currentName = git config --global user.name 2>$null
    if ($currentName -eq $config.GitUserName) {
        Write-OK "user.name は既に設定済み: $currentName"
    } else {
        git config --global user.name $config.GitUserName
        Write-OK "user.name を設定: $($config.GitUserName)"
    }
} else {
    $currentName = git config --global user.name 2>$null
    if ($currentName) {
        Write-OK "user.name は既に設定済み: $currentName"
    } else {
        Write-Warn "user.name が未設定です。config/local.psd1 の GitUserName を設定してください。"
    }
}

# --- user.email ---
if ($config.GitUserEmail -and $config.GitUserEmail -ne '' -and $config.GitUserEmail -ne 'your-email@example.com') {
    $currentEmail = git config --global user.email 2>$null
    if ($currentEmail -eq $config.GitUserEmail) {
        Write-OK "user.email は既に設定済み: $currentEmail"
    } else {
        git config --global user.email $config.GitUserEmail
        Write-OK "user.email を設定: $($config.GitUserEmail)"
    }
} else {
    $currentEmail = git config --global user.email 2>$null
    if ($currentEmail) {
        Write-OK "user.email は既に設定済み: $currentEmail"
    } else {
        Write-Warn "user.email が未設定です。config/local.psd1 の GitUserEmail を設定してください。"
    }
}

# --- init.defaultBranch ---
$currentDefault = git config --global init.defaultBranch 2>$null
if ($currentDefault -eq 'main') {
    Write-OK "init.defaultBranch は既に 'main' に設定済み"
} else {
    git config --global init.defaultBranch main
    Write-OK "init.defaultBranch を 'main' に設定"
}

# --- 現在の設定を表示 ---
Write-Step "現在の Git グローバル設定"
Write-Host "  user.name         = $(git config --global user.name 2>$null)"
Write-Host "  user.email        = $(git config --global user.email 2>$null)"
Write-Host "  init.defaultBranch = $(git config --global init.defaultBranch 2>$null)"
Write-Host "  core.autocrlf     = $(git config --global core.autocrlf 2>$null)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ※ core.autocrlf はこのスクリプトでは変更しません。" -ForegroundColor DarkGray
Write-Host "  ※ 必要に応じて手動で設定してください: git config --global core.autocrlf <true|false|input>" -ForegroundColor DarkGray

Write-OK "Phase 4: Git 設定完了"
