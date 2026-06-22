#Requires -RunAsAdministrator
<#
.SYNOPSIS
    SSHD の設定を行う (デフォルトシェル、自動起動)
.DESCRIPTION
    PowerShell 7 を SSH のデフォルトシェルに設定し、sshd を再起動する。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Assert-Admin

Write-Step "Phase 5: SSHD 設定"

$config = Read-Config

# --- sshd サービス確認 ---
$sshdService = Get-Service -Name sshd -ErrorAction SilentlyContinue
if (-not $sshdService) {
    Write-Fail "sshd サービスが見つかりません。先に 00-bootstrap-openssh.ps1 を実行してください。"
    exit 1
}

# --- 自動起動設定 ---
if ($sshdService.StartType -ne 'Automatic') {
    Set-Service -Name sshd -StartupType Automatic
    Write-OK "sshd を自動起動に設定"
} else {
    Write-OK "sshd は既に自動起動"
}

# --- デフォルトシェルの設定 ---
$needsRestart = $false

if ($config.SetDefaultShell -ne $false) {
    Write-Step "SSH デフォルトシェルの設定"

    # PowerShell 7 のパスを探す
    $pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $pwshPath) {
        # 標準インストール先を確認
        $defaultPwshPath = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
        if (Test-Path $defaultPwshPath) {
            $pwshPath = $defaultPwshPath
        }
    }

    if ($pwshPath -and (Test-Path $pwshPath)) {
        # レジストリキーの確認・作成
        $regPath = 'HKLM:\SOFTWARE\OpenSSH'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }

        $currentShell = Get-ItemProperty -Path $regPath -Name 'DefaultShell' -ErrorAction SilentlyContinue
        if ($currentShell -and $currentShell.DefaultShell -eq $pwshPath) {
            Write-OK "デフォルトシェルは既に PowerShell 7 に設定済み: $pwshPath"
        } else {
            Set-ItemProperty -Path $regPath -Name 'DefaultShell' -Value $pwshPath
            Write-OK "デフォルトシェルを PowerShell 7 に設定: $pwshPath"
            $needsRestart = $true
        }
    } else {
        Write-Warn "PowerShell 7 (pwsh.exe) が見つかりません。デフォルトシェルの変更をスキップします。"
        Write-Host "  先に 01-base-setup.ps1 で PowerShell 7 をインストールしてください。"
    }
} else {
    Write-Host "[SKIP] デフォルトシェルの変更はスキップ (設定で無効化)"
}

# --- sshd_config のバックアップと確認 ---
Write-Step "sshd_config の確認"
$sshdConfigPath = Join-Path $env:ProgramData 'ssh\sshd_config'
if (Test-Path $sshdConfigPath) {
    # バックアップ作成
    $backupPath = "${sshdConfigPath}.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -Path $sshdConfigPath -Destination $backupPath
    Write-OK "sshd_config のバックアップを作成: $backupPath"

    # 現在の設定を表示
    Write-Host "  現在の sshd_config から重要な設定:"
    $sshdConfig = Get-Content $sshdConfigPath
    $importantSettings = @('PubkeyAuthentication', 'PasswordAuthentication', 'AuthorizedKeysFile', 'Match Group administrators')
    foreach ($setting in $importantSettings) {
        $line = $sshdConfig | Where-Object { $_ -match "^\s*#?\s*$setting" } | Select-Object -First 1
        if ($line) {
            Write-Host "    $($line.Trim())" -ForegroundColor DarkGray
        }
    }

    Write-Warn "sshd_config の変更はこのスクリプトでは行いません。"
    Write-Host "  パスワード認証を無効化する前に、必ず公開鍵でのログインを確認してください。" -ForegroundColor Yellow
    Write-Host "  手動で編集する場合: notepad $sshdConfigPath" -ForegroundColor DarkGray
} else {
    Write-Warn "sshd_config が見つかりません: $sshdConfigPath"
}

# --- sshd 再起動 ---
if ($needsRestart) {
    Write-Step "sshd の再起動"
    Restart-Service sshd
    Write-OK "sshd を再起動しました"
}

# --- サービス状態の確認 ---
$sshdService = Get-Service -Name sshd
if ($sshdService.Status -eq 'Running') {
    Write-OK "sshd サービスは実行中"
} else {
    Start-Service sshd
    Write-OK "sshd サービスを開始しました"
}

Write-OK "Phase 5: SSHD 設定完了"
