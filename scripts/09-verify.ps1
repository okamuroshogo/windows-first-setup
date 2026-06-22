<#
.SYNOPSIS
    セットアップの検証
.DESCRIPTION
    インストールされたツールとサービスの状態を検証し、結果をテーブルで表示する。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 9: セットアップ検証"

$results = @()

# --- PowerShell 7 ---
$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwshCmd) {
    $ver = & pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
    $results += @{ Name = 'PowerShell 7'; Status = 'OK'; Detail = "v$ver" }
} else {
    $results += @{ Name = 'PowerShell 7'; Status = 'FAIL'; Detail = 'pwsh が見つかりません' }
}

# --- Git ---
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $ver = git --version 2>$null
    $results += @{ Name = 'Git'; Status = 'OK'; Detail = $ver }
} else {
    $results += @{ Name = 'Git'; Status = 'FAIL'; Detail = 'git が見つかりません' }
}

# --- WinGet ---
$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if ($wingetCmd) {
    $ver = winget --version 2>$null
    $results += @{ Name = 'WinGet'; Status = 'OK'; Detail = "v$ver" }
} else {
    $results += @{ Name = 'WinGet'; Status = 'FAIL'; Detail = 'winget が見つかりません' }
}

# --- Scoop ---
$scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
if ($scoopCmd) {
    $results += @{ Name = 'Scoop'; Status = 'OK'; Detail = 'インストール済み' }
} else {
    $results += @{ Name = 'Scoop'; Status = 'FAIL'; Detail = 'scoop が見つかりません' }
}

# --- Node.js ---
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
    $ver = node --version 2>$null
    $results += @{ Name = 'Node.js'; Status = 'OK'; Detail = $ver }
} else {
    $results += @{ Name = 'Node.js'; Status = 'FAIL'; Detail = 'node が見つかりません' }
}

# --- Python ---
$pyCmd = Get-Command python -ErrorAction SilentlyContinue
if ($pyCmd) {
    $ver = python --version 2>$null
    $results += @{ Name = 'Python'; Status = 'OK'; Detail = $ver }
} else {
    $results += @{ Name = 'Python'; Status = 'FAIL'; Detail = 'python が見つかりません' }
}

# --- Claude Code ---
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    $ver = claude --version 2>$null
    $results += @{ Name = 'Claude Code'; Status = 'OK'; Detail = $ver }
} else {
    $results += @{ Name = 'Claude Code'; Status = 'FAIL'; Detail = 'claude が見つかりません' }
}

# --- sshd サービス ---
$sshdService = Get-Service -Name sshd -ErrorAction SilentlyContinue
if ($sshdService) {
    if ($sshdService.Status -eq 'Running') {
        $results += @{ Name = 'sshd サービス'; Status = 'OK'; Detail = "実行中 (起動: $($sshdService.StartType))" }
    } else {
        $results += @{ Name = 'sshd サービス'; Status = 'WARN'; Detail = "停止中 (起動: $($sshdService.StartType))" }
    }
} else {
    $results += @{ Name = 'sshd サービス'; Status = 'FAIL'; Detail = 'サービスが見つかりません' }
}

# --- TCP 22 Listen ---
try {
    $listeners = Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue
    if ($listeners) {
        $results += @{ Name = 'TCP 22 Listen'; Status = 'OK'; Detail = "Listen中 ($($listeners.Count) connections)" }
    } else {
        $results += @{ Name = 'TCP 22 Listen'; Status = 'FAIL'; Detail = 'Port 22 でListenしていません' }
    }
} catch {
    $results += @{ Name = 'TCP 22 Listen'; Status = 'WARN'; Detail = '確認できません' }
}

# --- OpenSSH DefaultShell ---
$regPath = 'HKLM:\SOFTWARE\OpenSSH'
try {
    $defaultShell = Get-ItemProperty -Path $regPath -Name 'DefaultShell' -ErrorAction SilentlyContinue
    if ($defaultShell) {
        $shellName = Split-Path $defaultShell.DefaultShell -Leaf
        if (Test-Path $defaultShell.DefaultShell) {
            $results += @{ Name = 'SSH DefaultShell'; Status = 'OK'; Detail = $shellName }
        } else {
            $results += @{ Name = 'SSH DefaultShell'; Status = 'WARN'; Detail = "設定あり ($shellName) だがファイルが存在しません" }
        }
    } else {
        $results += @{ Name = 'SSH DefaultShell'; Status = 'WARN'; Detail = '未設定 (Windows PowerShell がデフォルト)' }
    }
} catch {
    $results += @{ Name = 'SSH DefaultShell'; Status = 'WARN'; Detail = '確認できません' }
}

# --- Tailscale ---
$tailscaleCmd = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $tailscaleCmd) {
    # 標準インストール先を確認
    $tailscalePath = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path $tailscalePath) {
        $tailscaleCmd = $tailscalePath
    }
}

if ($tailscaleCmd) {
    try {
        $tailscaleStatus = if ($tailscaleCmd -is [string]) {
            & $tailscaleCmd status 2>$null
        } else {
            tailscale status 2>$null
        }
        if ($LASTEXITCODE -eq 0) {
            $tailscaleIp = if ($tailscaleCmd -is [string]) {
                & $tailscaleCmd ip -4 2>$null
            } else {
                tailscale ip -4 2>$null
            }
            $results += @{ Name = 'Tailscale'; Status = 'OK'; Detail = "接続中 (IP: $tailscaleIp)" }
        } else {
            $results += @{ Name = 'Tailscale'; Status = 'WARN'; Detail = 'インストール済みだが未接続' }
        }
    } catch {
        $results += @{ Name = 'Tailscale'; Status = 'WARN'; Detail = 'インストール済みだが状態確認失敗' }
    }
} else {
    $results += @{ Name = 'Tailscale'; Status = 'FAIL'; Detail = 'tailscale が見つかりません' }
}

# --- AutoHotkey スクリプト ---
$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$ahkScript = Join-Path $startupDir 'win-space-ime.ahk'
if (Test-Path $ahkScript) {
    $ahkProcess = Get-Process -Name 'AutoHotkey*' -ErrorAction SilentlyContinue
    if ($ahkProcess) {
        $results += @{ Name = 'AutoHotkey IME'; Status = 'OK'; Detail = 'スクリプト配置済み & プロセス実行中' }
    } else {
        $results += @{ Name = 'AutoHotkey IME'; Status = 'WARN'; Detail = 'スクリプト配置済みだがプロセス未実行' }
    }
} else {
    $results += @{ Name = 'AutoHotkey IME'; Status = 'WARN'; Detail = 'Startup にスクリプトなし' }
}

# --- Datadog コレクタ ---
$ddTask = Get-ScheduledTask -TaskName 'DatadogMetricsCollector' -ErrorAction SilentlyContinue
if ($ddTask) {
    $ddLog = Join-Path $env:LOCALAPPDATA 'dd-collector\dd-collector.log'
    $recentSend = $false
    if (Test-Path $ddLog) {
        # 直近5分以内に SEND error が無ければ送信成功とみなす (成功時は無ログ)
        $lastErr = Get-Content $ddLog -Tail 20 | Where-Object { $_ -match 'SEND error' } | Select-Object -Last 1
        $recentSend = -not $lastErr
    }
    if ($ddTask.State -eq 'Running') {
        $detail = if ($recentSend) { '実行中 (送信エラーなし)' } else { '実行中 (直近に送信エラーあり — ログ確認)' }
        $status = if ($recentSend) { 'OK' } else { 'WARN' }
        $results += @{ Name = 'Datadog コレクタ'; Status = $status; Detail = $detail }
    } else {
        $results += @{ Name = 'Datadog コレクタ'; Status = 'WARN'; Detail = "タスク登録済みだが停止中 (State: $($ddTask.State))" }
    }
} else {
    $results += @{ Name = 'Datadog コレクタ'; Status = 'WARN'; Detail = 'タスク未登録 (Datadog.Enabled=$false の可能性)' }
}

# --- IPv4 設定 ---
$physicalIps = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -ne '127.0.0.1' -and
        $_.InterfaceAlias -notmatch 'Loopback|Tailscale|vEthernet|WSL|Hyper-V'
    }

if ($physicalIps) {
    foreach ($ip in $physicalIps) {
        $adapterName = $ip.InterfaceAlias
        $results += @{ Name = "IPv4 ($adapterName)"; Status = 'OK'; Detail = "$($ip.IPAddress)/$($ip.PrefixLength)" }
    }
} else {
    $results += @{ Name = 'IPv4'; Status = 'WARN'; Detail = '物理NICのIPアドレスが見つかりません' }
}

# --- DNS 名前解決 ---
try {
    $dns = Resolve-DnsName -Name 'github.com' -Type A -ErrorAction Stop
    $results += @{ Name = 'DNS解決 (github.com)'; Status = 'OK'; Detail = ($dns | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1 -ExpandProperty IPAddress) }
} catch {
    $results += @{ Name = 'DNS解決 (github.com)'; Status = 'FAIL'; Detail = '名前解決失敗' }
}

# --- GitHub HTTPS 疎通 ---
try {
    $response = Invoke-WebRequest -Uri 'https://github.com' -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    $results += @{ Name = 'GitHub HTTPS'; Status = 'OK'; Detail = "StatusCode: $($response.StatusCode)" }
} catch {
    $results += @{ Name = 'GitHub HTTPS'; Status = 'FAIL'; Detail = "接続失敗: $_" }
}

# --- 結果表示 ---
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  セットアップ検証結果" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Show-ResultTable -Results $results

$okCount = ($results | Where-Object { $_.Status -eq 'OK' }).Count
$warnCount = ($results | Where-Object { $_.Status -eq 'WARN' }).Count
$failCount = ($results | Where-Object { $_.Status -eq 'FAIL' }).Count

Write-Host "  合計: $($results.Count) 項目  |  OK: $okCount  |  WARN: $warnCount  |  FAIL: $failCount"
Write-Host ""

if ($failCount -eq 0) {
    Write-OK "すべての検証に合格しました!"
} else {
    Write-Warn "$failCount 個の項目が失敗しています。上記の結果を確認してください。"
}
