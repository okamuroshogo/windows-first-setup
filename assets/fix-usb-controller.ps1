<#
.SYNOPSIS
    スリープ復帰後の USB「Port Reset Failed」復旧スクリプト
.DESCRIPTION
    スリープ復帰後に xHCI USB コントローラ配下のデバイスが全滅し、
    物理マウス・キーボードが認識されなくなる問題を、コントローラの
    PnP 再起動 (Restart-PnpDevice) で復旧する。

    -OnlyIfBroken : エラー状態の USB デバイスが無ければ何もせず終了する。
                    スリープ復帰イベントで自動実行するタスク用。
    -ControllerInstanceId : 再起動するコントローラを固定指定する。
                    未指定ならエラー状態のデバイスから親をたどって自動検出。

    13-install-usb-resume-fix.ps1 がこのスクリプトを
    %ProgramData%\windows-first-setup\ に配置し、スリープ復帰イベント
    (Power-Troubleshooter ID 1) で自動実行するタスクを登録する。
.NOTES
    管理者権限 (または SYSTEM) で実行すること。
#>
param(
    [string]$ControllerInstanceId = '',
    [switch]$OnlyIfBroken
)

$ErrorActionPreference = 'Stop'

$logFile = Join-Path $env:ProgramData 'windows-first-setup\fix-usb-controller.log'
function Write-Log {
    param([string]$Msg)
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    Write-Host $line
    try { Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue } catch {}
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error '管理者権限で実行してください。'
    exit 1
}

# --- エラー状態の USB デバイスを列挙 ---
$broken = @(Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -eq 'Error' -and ($_.Class -eq 'USB' -or $_.InstanceId -like 'USB\*') })

if ($OnlyIfBroken -and $broken.Count -eq 0) {
    Write-Log 'エラー状態の USB デバイスなし。何もしません。'
    exit 0
}

if ($broken.Count -gt 0) {
    Write-Log ("エラー状態の USB デバイス: " + (($broken | ForEach-Object { $_.FriendlyName }) -join ', '))
}

# --- デバイスの親をたどって PCI 上のコントローラを見つける ---
function Get-PciParent {
    param([string]$InstanceId)
    $id = $InstanceId
    for ($i = 0; $i -lt 6 -and $id -and $id -notlike 'PCI\*'; $i++) {
        $id = (Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue).Data
    }
    if ($id -like 'PCI\*') { return $id }
    return $null
}

# --- 再起動対象コントローラの決定 ---
$targets = if ($ControllerInstanceId) {
    @($ControllerInstanceId)
} elseif ($broken.Count -gt 0) {
    @($broken | ForEach-Object { Get-PciParent $_.InstanceId } | Where-Object { $_ } | Sort-Object -Unique)
} else {
    # 手動実行でエラーデバイスが無い場合: PCI 直下の USB コントローラすべて
    @(Get-PnpDevice -Class USB -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like 'PCI\*' -and $_.Present } |
        Select-Object -ExpandProperty InstanceId)
}

if ($targets.Count -eq 0) {
    Write-Log '再起動対象の USB コントローラが見つかりませんでした。'
    exit 1
}

foreach ($id in $targets) {
    Write-Log "USB コントローラを再起動: $id"
    try {
        Restart-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Log "再起動に失敗: $_"
    }
}

Start-Sleep -Seconds 5

# --- 復旧確認 ---
$stillBroken = @(Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Error' })
if ($stillBroken.Count -gt 0) {
    Write-Log ("まだエラーの USB デバイスあり: " + (($stillBroken | ForEach-Object { $_.FriendlyName }) -join ', '))
    Write-Log 'デバイスを挿し直すか、PC を再起動してください。'
    exit 1
}

Write-Log 'USB デバイスのエラーは解消しました。'
Get-PnpDevice -Class Mouse, Keyboard -ErrorAction SilentlyContinue | Where-Object Present |
    Select-Object Class, Status, FriendlyName | Format-Table -AutoSize
