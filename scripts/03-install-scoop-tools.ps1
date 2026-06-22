<#
.SYNOPSIS
    Scoop で CLI ツールをインストールする
.DESCRIPTION
    Scoop を CurrentUser スコープでインストールし、設定ファイルで有効なツールのみインストールする。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 3: Scoop CLI ツールのインストール"

$config = Read-Config

# --- Scoop 本体のインストール ---
$scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
if (-not $scoopCmd) {
    Write-Host "Scoop をインストール中..."
    try {
        # Scoop の公式インストール方法
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
        Refresh-PathEnv
        $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
        if ($scoopCmd) {
            Write-OK "Scoop をインストールしました"
        } else {
            Write-Fail "Scoop のインストールに失敗しました"
            exit 1
        }
    } catch {
        Write-Fail "Scoop のインストールに失敗: $_"
        Write-Host "  実行ポリシーを確認してください:"
        Write-Host "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"
        exit 1
    }
} else {
    Write-OK "Scoop は既にインストール済み"
    # Scoop自体を更新
    scoop update 2>$null | Out-Null
}

# --- extras bucket の追加 ---
$buckets = scoop bucket list 2>$null
if ($buckets -notmatch 'extras') {
    Write-Host "Scoop extras bucket を追加中..."
    scoop bucket add extras 2>$null | Out-Null
    Write-OK "extras bucket を追加しました"
}

# --- ツールのインストール ---
$tools = [ordered]@{
    '7zip'       = '7zip'
    'jq'         = 'jq'
    'yq'         = 'yq'
    'ripgrep'    = 'ripgrep'
    'fd'         = 'fd'
    'fzf'        = 'fzf'
    'vim'        = 'vim'
    'nodejs-lts' = 'nodejs-lts'
    'python'     = 'python'
}

$results = @()
$failCount = 0

foreach ($tool in $tools.Keys) {
    # 設定で無効化されている場合はスキップ
    $enabled = $true
    if ($config.ScoopTools -and $config.ScoopTools.ContainsKey($tool)) {
        $enabled = $config.ScoopTools[$tool]
    }

    if (-not $enabled) {
        Write-Host "[SKIP] $tool (設定で無効化)"
        $results += @{ Name = $tool; Status = 'SKIP'; Detail = '設定で無効化' }
        continue
    }

    # インストール済み確認
    $installed = scoop list 2>$null | Select-String -Pattern "^\s*$tool\s" -Quiet
    if ($installed) {
        Write-OK "$tool は既にインストール済み (更新を確認)"
        scoop update $tool 2>$null | Out-Null
        $results += @{ Name = $tool; Status = 'OK'; Detail = 'インストール済み/更新済み' }
    } else {
        Write-Host "  $tool をインストール中..."
        scoop install $tool 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "$tool をインストールしました"
            $results += @{ Name = $tool; Status = 'OK'; Detail = '新規インストール' }
        } else {
            Write-Fail "$tool のインストールに失敗"
            $results += @{ Name = $tool; Status = 'FAIL'; Detail = 'インストール失敗' }
            $failCount++
        }
    }
}

# PATH の再読み込み
Refresh-PathEnv

# 結果表示
Write-Step "Scoop インストール結果"
Show-ResultTable -Results $results

if ($failCount -gt 0) {
    Write-Warn "$failCount 個のツールのインストールに失敗しました。"
} else {
    Write-OK "Phase 3: すべての Scoop ツールのインストール完了"
}
