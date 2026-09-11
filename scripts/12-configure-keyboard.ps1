<#
.SYNOPSIS
    キーボードカスタマイズ (PowerToys Keyboard Manager / CapsLock→Ctrl)
.DESCRIPTION
    - assets\powertoys-keyboard-manager.json を PowerToys Keyboard Manager の
      設定 (default.json) として配置する。
      現在の内容: Win+C → Ctrl+C, Win+V → Ctrl+V
    - PowerToys の「マウスの検索 (Find My Mouse)」を無効化する。
      Ctrl 2回押しが ctrl-ctrl-terminal.ahk のホットキーターミナルと
      競合するため (config の PowerToysDisableFindMyMouse で制御)。
    - config の CapsLockToCtrl が $true の場合、レジストリの Scancode Map で
      CapsLock を左 Ctrl にリマップする (要管理者・反映には再起動が必要)。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 12: キーボードカスタマイズ"

$config = Read-Config
$repoRoot = Split-Path $PSScriptRoot -Parent

$ptEnabled = if ($config.ContainsKey('PowerToysKeyboardManager')) { [bool]$config.PowerToysKeyboardManager } else { $true }
$disableFindMyMouse = if ($config.ContainsKey('PowerToysDisableFindMyMouse')) { [bool]$config.PowerToysDisableFindMyMouse } else { $true }

$ptNeedsRestart = $false

# --- PowerToys Keyboard Manager 設定の配置 ---
if ($ptEnabled) {
    Write-Step "PowerToys Keyboard Manager 設定"

    $sourceJson = Join-Path $repoRoot 'assets\powertoys-keyboard-manager.json'
    $kbmDir     = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\Keyboard Manager'
    $destJson   = Join-Path $kbmDir 'default.json'

    if (-not (Test-Path $sourceJson)) {
        Write-Fail "設定ファイルが見つかりません: $sourceJson"
        exit 1
    }

    if (-not (Test-Path $kbmDir)) {
        New-Item -ItemType Directory -Path $kbmDir -Force | Out-Null
    }

    if ((Test-Path $destJson) -and (Get-FileHash $sourceJson).Hash -eq (Get-FileHash $destJson).Hash) {
        Write-OK "Keyboard Manager 設定は既に反映済み"
    } else {
        if (Test-Path $destJson) {
            Copy-Item $destJson "$destJson.bak" -Force
            Write-Info "既存設定をバックアップ: $destJson.bak"
        }
        Copy-Item -Path $sourceJson -Destination $destJson -Force
        Write-OK "Keyboard Manager 設定を配置: $destJson"
        $ptNeedsRestart = $true
    }
} else {
    Write-Host "[SKIP] PowerToys Keyboard Manager 設定はスキップ (設定で無効化)"
}

# --- Find My Mouse の無効化 (Ctrl 2回押しをホットキーターミナルに譲る) ---
if ($disableFindMyMouse) {
    Write-Step "PowerToys Find My Mouse の無効化"

    $ptSettings = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\settings.json'
    if (Test-Path $ptSettings) {
        $json = Get-Content $ptSettings -Raw | ConvertFrom-Json
        if ($json.PSObject.Properties['enabled'] -and $json.enabled.PSObject.Properties['FindMyMouse']) {
            if ($json.enabled.FindMyMouse) {
                $json.enabled.FindMyMouse = $false
                # PowerToys の C++ JSON パーサは BOM を読めず、BOM 付きで書くと
                # 設定全体が既定値 (FindMyMouse=有効, KBM=無効) に化けるため BOM なし必須
                [IO.File]::WriteAllText($ptSettings, ($json | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding($false)))
                Write-OK "Find My Mouse を無効化しました"
                $ptNeedsRestart = $true
            } else {
                Write-OK "Find My Mouse は既に無効"
            }
        } else {
            Write-OK "Find My Mouse の設定なし (未使用)"
        }
    } else {
        Write-Warn "PowerToys の settings.json が見つかりません (未インストール or 未起動)"
    }
} else {
    Write-Host "[SKIP] Find My Mouse の無効化はスキップ (設定で無効化)"
}

# --- PowerToys 再起動 (設定を読み込ませる) ---
if ($ptNeedsRestart) {
    $ptProcess = Get-Process -Name 'PowerToys' -ErrorAction SilentlyContinue
    $ptExe = @(
        (Join-Path $env:ProgramFiles 'PowerToys\PowerToys.exe'),
        (Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($ptProcess) {
        $ptProcess | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if ($ptExe) {
            Start-Process -FilePath $ptExe
            Write-OK "PowerToys を再起動しました"
        } else {
            Write-Warn "PowerToys 本体が見つからず再起動できません。手動で起動してください。"
        }
    } elseif ($ptExe) {
        Start-Process -FilePath $ptExe
        Write-OK "PowerToys を起動しました"
    } else {
        Write-Warn "PowerToys が未インストールです。WinGet でインストール後に再実行してください。"
    }
}

# --- CapsLock → 左Ctrl (Scancode Map) ---
$capsToCtrl = if ($config.ContainsKey('CapsLockToCtrl')) { [bool]$config.CapsLockToCtrl } else { $false }

if ($capsToCtrl) {
    Write-Step "CapsLock → Ctrl リマップ (Scancode Map)"

    if (-not (Test-IsAdmin)) {
        Write-Warn "Scancode Map の書き込みには管理者権限が必要です。管理者で再実行してください。"
    } else {
        # header(8) + count(4) + CapsLock(0x3A)→LCtrl(0x1D) + terminator(4)
        [byte[]]$scancodeMap = @(
            0x00,0x00,0x00,0x00,  0x00,0x00,0x00,0x00,
            0x02,0x00,0x00,0x00,
            0x1D,0x00,0x3A,0x00,
            0x00,0x00,0x00,0x00
        )

        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
        $current = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).'Scancode Map'

        if ($current -and -not (Compare-Object $current $scancodeMap -SyncWindow 0)) {
            Write-OK "Scancode Map は既に設定済み (CapsLock → Ctrl)"
        } else {
            if ($current) {
                Write-Warn "既存の Scancode Map を上書きします (旧値: $(($current | ForEach-Object { $_.ToString('x2') }) -join ' '))"
            }
            Set-ItemProperty -Path $regPath -Name 'Scancode Map' -Value $scancodeMap -Type Binary
            Write-OK "Scancode Map を設定しました (CapsLock → 左Ctrl)"
            Write-Warn "反映には再起動が必要です。"
        }
    }
} else {
    Write-Host "[SKIP] CapsLock → Ctrl リマップはスキップ (CapsLockToCtrl = `$false)"
}

Write-OK "Phase 12: キーボードカスタマイズ完了"
