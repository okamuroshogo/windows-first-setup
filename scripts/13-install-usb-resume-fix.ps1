<#
.SYNOPSIS
    スリープ復帰時の USB 復旧タスクをインストールする
.DESCRIPTION
    assets\fix-usb-controller.ps1 を %ProgramData%\windows-first-setup\ に配置し、
    スリープ復帰イベント (Microsoft-Windows-Power-Troubleshooter ID 1) を
    トリガーに SYSTEM 権限で自動実行するスケジュールタスクを登録する。

    スクリプトは -OnlyIfBroken 付きで動くため、USB デバイスが正常なら何もしない。
    エラー状態の USB デバイスがあるときだけ xHCI コントローラを PnP 再起動する。

    config\local.psd1:
        UsbResumeFix = @{
            Enabled = $true
            ControllerInstanceId = ''   # 空なら自動検出。固定したい場合のみ指定
        }
.NOTES
    管理者権限が必要。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 13: USB 復旧タスク (スリープ復帰時)"

$config = Read-Config

$fix = if ($config.ContainsKey('UsbResumeFix')) { $config.UsbResumeFix } else { @{} }
$enabled      = if ($fix.ContainsKey('Enabled')) { [bool]$fix.Enabled } else { $false }
$controllerId = if ($fix.ContainsKey('ControllerInstanceId')) { [string]$fix.ControllerInstanceId } else { '' }

if (-not $enabled) {
    Write-Warn "USB 復旧タスクはスキップされました (config の UsbResumeFix.Enabled = `$false)。"
    return
}

Assert-Admin

# --- スクリプト配置 (SYSTEM で実行するため一般ユーザーが書けない場所に置く) ---
$repoRoot   = Split-Path $PSScriptRoot -Parent
$sourcePs1  = Join-Path $repoRoot 'assets\fix-usb-controller.ps1'
$installDir = Join-Path $env:ProgramData 'windows-first-setup'
$target     = Join-Path $installDir 'fix-usb-controller.ps1'

if (-not (Test-Path $sourcePs1)) {
    Write-Fail "スクリプトが見つかりません: $sourcePs1"
    exit 1
}

if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# ACL: SYSTEM/Administrators のみ書き込み可、Users は読み取りのみ
# (SYSTEM タスクが実行するスクリプトを一般ユーザーが差し替えられないようにする)
icacls $installDir /inheritance:r /grant '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null

Copy-Item -Path $sourcePs1 -Destination $target -Force
Write-OK "復旧スクリプトを配置: $target"

# --- スケジュールタスク登録 (スリープ復帰イベントトリガー) ---
$taskName = 'FixUsbControllerOnResume'
$ps = (Get-Command powershell.exe).Source

$argument = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`" -OnlyIfBroken"
if ($controllerId) {
    $argument += " -ControllerInstanceId `"$controllerId`""
}

$action = New-ScheduledTaskAction -Execute $ps -Argument $argument

# New-ScheduledTaskTrigger はイベントトリガー非対応のため CIM クラスで作る
$triggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
$trigger = New-CimInstance -CimClass $triggerClass -ClientOnly
$trigger.Enabled = $true
$trigger.Delay = 'PT20S'   # 復帰直後は自然回復する場合があるため少し待つ
$trigger.Subscription = @"
<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]</Select></Query></QueryList>
"@

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal `
    -Description 'スリープ復帰後に USB デバイスがエラー状態なら xHCI コントローラを再起動して復旧する。' `
    -Force | Out-Null

Write-OK "スケジュールタスクを登録しました: $taskName (スリープ復帰イベントで自動実行)"
Write-Host "  ログ: $installDir\fix-usb-controller.log"
Write-Host "  手動実行: powershell -ExecutionPolicy Bypass -File `"$target`"  (管理者)"

Write-OK "Phase 13: USB 復旧タスク完了"
