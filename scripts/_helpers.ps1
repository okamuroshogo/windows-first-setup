<#
.SYNOPSIS
    共通ヘルパー関数
.DESCRIPTION
    全スクリプトから利用する共通関数を定義する。
    各スクリプトの冒頭で `. (Join-Path $PSScriptRoot '_helpers.ps1')` で読み込む。
#>

# --- ログ関数 ---
function Write-Step  { param([string]$Msg) Write-Host "`n[*] $Msg" -ForegroundColor Cyan }
function Write-OK    { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "[WARN] $Msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Msg) Write-Host "[FAIL] $Msg" -ForegroundColor Red }
function Write-Info  { param([string]$Msg) Write-Host "[INFO] $Msg" -ForegroundColor White }

# --- 管理者権限チェック ---
function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-IsAdmin)) {
        Write-Fail "このスクリプトは管理者として実行してください。"
        Write-Host "PowerShellを右クリック → 「管理者として実行」で開き直してください。"
        exit 1
    }
}

# --- 設定ファイル読み込み ---
function Read-Config {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $localConfig = Join-Path $repoRoot 'config\local.psd1'
    $exampleConfig = Join-Path $repoRoot 'config\example.psd1'

    if (Test-Path $localConfig) {
        Write-Info "設定ファイルを読み込み: $localConfig"
        return Import-PowerShellDataFile $localConfig
    } elseif (Test-Path $exampleConfig) {
        Write-Warn "local.psd1 が見つかりません。example.psd1 のデフォルト値を使用します。"
        Write-Host "  カスタマイズするには: Copy-Item '$exampleConfig' '$localConfig'"
        return Import-PowerShellDataFile $exampleConfig
    } else {
        Write-Warn "設定ファイルが見つかりません。デフォルト値を使用します。"
        return @{
            GitUserName     = ''
            GitUserEmail    = ''
            ComputerName    = ''
            DisableSleep    = $false
            SetDefaultShell = $true
            EnableAutoHotkey = $true
            WinGetApps = @{}
            ScoopTools = @{}
            Network = @{ Enabled = $false }
        }
    }
}

# --- PATH 環境変数の再読み込み ---
function Refresh-PathEnv {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

# --- WinGet インストール済み確認 ---
function Test-WinGetInstalled {
    param([string]$PackageId)
    $result = winget list --id $PackageId --accept-source-agreements 2>$null
    return ($LASTEXITCODE -eq 0 -and $result -match [regex]::Escape($PackageId))
}

# --- WinGet でアプリをインストール ---
function Install-WinGetApp {
    param(
        [string]$PackageId,
        [string]$AppName
    )

    try {
        if (Test-WinGetInstalled -PackageId $PackageId) {
            Write-OK "$AppName は既にインストール済み"
            # アップグレードを試みる
            winget upgrade --id $PackageId --accept-source-agreements --accept-package-agreements --silent 2>$null | Out-Null
            return $true
        }

        Write-Host "  $AppName ($PackageId) をインストール中..."
        winget install --id $PackageId --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "$AppName をインストールしました"
            return $true
        } else {
            Write-Fail "$AppName のインストールに失敗しました (exit code: $LASTEXITCODE)"
            return $false
        }
    } catch {
        Write-Fail "$AppName のインストール中にエラー: $_"
        return $false
    }
}

# --- Scoop インストール済み確認 ---
function Test-ScoopInstalled {
    param([string]$ToolName)
    $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
    if (-not $scoopCmd) { return $false }
    $list = scoop list 2>$null
    return ($list -match "^\s*$ToolName\s")
}

# --- 結果テーブル表示 ---
function Show-ResultTable {
    param(
        [array]$Results  # @{ Name; Status; Detail }
    )
    Write-Host ""
    Write-Host ("{0,-25} {1,-10} {2}" -f "項目", "状態", "詳細") -ForegroundColor White
    Write-Host ("{0,-25} {1,-10} {2}" -f ("─" * 25), ("─" * 10), ("─" * 40)) -ForegroundColor DarkGray
    foreach ($r in $Results) {
        $color = switch ($r.Status) {
            'OK'   { 'Green' }
            'SKIP' { 'Yellow' }
            'FAIL' { 'Red' }
            'WARN' { 'Yellow' }
            default { 'White' }
        }
        Write-Host ("{0,-25} " -f $r.Name) -NoNewline
        Write-Host ("{0,-10} " -f $r.Status) -ForegroundColor $color -NoNewline
        Write-Host $r.Detail
    }
    Write-Host ""
}
