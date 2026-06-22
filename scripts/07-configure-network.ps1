<#
.SYNOPSIS
    固定IPアドレスを設定する (手動実行専用)
.DESCRIPTION
    setup-all.ps1 からは呼ばれない。明示的に実行した場合のみ固定IPを設定する。
    -WhatIf パラメータで Dry Run が可能。
.PARAMETER WhatIf
    実際に変更を行わず、何が行われるかのみ表示する
.PARAMETER RevertToDHCP
    固定IPをDHCPに戻す
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RevertToDHCP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Assert-Admin

# --- DHCP に戻す ---
if ($RevertToDHCP) {
    Write-Step "DHCP に戻す"

    # 物理NICの一覧を取得 (仮想NIC除外)
    $adapters = Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and
        $_.InterfaceDescription -notmatch 'Tailscale|Hyper-V|WSL|VPN|Virtual|vEthernet'
    }

    if ($adapters.Count -eq 0) {
        Write-Fail "有効な物理ネットワークアダプターが見つかりません。"
        exit 1
    }

    Write-Host "  利用可能なアダプター:"
    foreach ($a in $adapters) {
        Write-Host "    [$($a.InterfaceIndex)] $($a.Name) - $($a.InterfaceDescription)" -ForegroundColor White
    }

    if ($adapters.Count -eq 1) {
        $targetAdapter = $adapters[0]
    } else {
        $idx = Read-Host "対象のInterfaceIndexを入力してください"
        $targetAdapter = $adapters | Where-Object { $_.InterfaceIndex -eq [int]$idx }
        if (-not $targetAdapter) {
            Write-Fail "指定されたInterfaceIndexのアダプターが見つかりません。"
            exit 1
        }
    }

    Write-Host "  対象: [$($targetAdapter.InterfaceIndex)] $($targetAdapter.Name)"

    if ($PSCmdlet.ShouldProcess($targetAdapter.Name, 'DHCP に戻す')) {
        Set-NetIPInterface -InterfaceIndex $targetAdapter.InterfaceIndex -Dhcp Enabled
        Set-DnsClientServerAddress -InterfaceIndex $targetAdapter.InterfaceIndex -ResetServerAddresses
        Write-OK "DHCP に戻しました。IPアドレスが再取得されます。"
        Write-Warn "SSH接続中の場合、接続が切断される可能性があります。"

        # 新しいIPの表示を少し待つ
        Start-Sleep -Seconds 3
        $newIp = Get-NetIPAddress -InterfaceIndex $targetAdapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($newIp) {
            Write-Host "  新しいIPアドレス: $($newIp.IPAddress)"
        }
    }
    exit 0
}

# --- 固定IP設定 ---
Write-Step "Phase 7: 固定IPアドレス設定"

$config = Read-Config

# Enabled チェック
if (-not $config.Network -or $config.Network.Enabled -ne $true) {
    Write-Warn "固定IP設定は無効化されています。"
    Write-Host "  有効にするには config/local.psd1 の Network.Enabled を `$true に設定してください。"
    exit 0
}

$netConfig = $config.Network

# --- SSH接続中の警告 ---
$sshSession = $env:SSH_CONNECTION
if ($sshSession) {
    Write-Warn "SSH接続中にIPアドレスを変更すると、接続が切断されます！"
    Write-Host "  現在のSSH接続: $sshSession" -ForegroundColor Yellow
    $confirm = Read-Host "続行しますか？ (yes/no)"
    if ($confirm -ne 'yes') {
        Write-Host "中断しました。"
        exit 0
    }
}

# --- 物理NICの取得 ---
$adapters = Get-NetAdapter | Where-Object {
    $_.Status -eq 'Up' -and
    $_.InterfaceDescription -notmatch 'Tailscale|Hyper-V|WSL|VPN|Virtual|vEthernet'
}

if ($adapters.Count -eq 0) {
    Write-Fail "有効な物理ネットワークアダプターが見つかりません。"
    exit 1
}

# --- アダプター選択 ---
$targetAdapter = $null

if ($netConfig.InterfaceIndex) {
    $targetAdapter = $adapters | Where-Object { $_.InterfaceIndex -eq $netConfig.InterfaceIndex }
} elseif ($netConfig.AdapterName -and $netConfig.AdapterName -ne '') {
    $targetAdapter = $adapters | Where-Object { $_.Name -eq $netConfig.AdapterName }
}

if (-not $targetAdapter) {
    Write-Host "  利用可能な物理アダプター:"
    foreach ($a in $adapters) {
        $currentIp = Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $ipStr = if ($currentIp) { $currentIp.IPAddress } else { 'N/A' }
        $mediaType = if ($a.MediaType -eq '802.3') { '有線' } else { $a.MediaType }
        Write-Host "    [$($a.InterfaceIndex)] $($a.Name) - $($a.InterfaceDescription) - $ipStr ($mediaType)" -ForegroundColor White
    }

    if ($adapters.Count -eq 1) {
        $targetAdapter = $adapters[0]
        Write-Host "  アダプターが1つのみのため自動選択: $($targetAdapter.Name)"
    } else {
        $idx = Read-Host "対象のInterfaceIndexを入力してください"
        $targetAdapter = $adapters | Where-Object { $_.InterfaceIndex -eq [int]$idx }
        if (-not $targetAdapter) {
            Write-Fail "指定されたInterfaceIndexのアダプターが見つかりません。"
            exit 1
        }
    }
}

Write-OK "対象アダプター: [$($targetAdapter.InterfaceIndex)] $($targetAdapter.Name)"

# --- 現在のネットワーク設定をバックアップ ---
Write-Step "現在のネットワーク設定"

$currentIpConfig = Get-NetIPAddress -InterfaceIndex $targetAdapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
$currentGateway = Get-NetRoute -InterfaceIndex $targetAdapter.InterfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
$currentDns = Get-DnsClientServerAddress -InterfaceIndex $targetAdapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

Write-Host "  現在のIPアドレス: $(if ($currentIpConfig) { $currentIpConfig.IPAddress } else { 'N/A' })"
Write-Host "  現在のサブネット: $(if ($currentIpConfig) { "/$($currentIpConfig.PrefixLength)" } else { 'N/A' })"
Write-Host "  現在のゲートウェイ: $(if ($currentGateway) { $currentGateway.NextHop } else { 'N/A' })"
Write-Host "  現在のDNS: $(if ($currentDns.ServerAddresses) { $currentDns.ServerAddresses -join ', ' } else { 'N/A' })"

# バックアップファイルに保存
$backupFile = Join-Path $PSScriptRoot "network-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$backup = @{
    InterfaceIndex = $targetAdapter.InterfaceIndex
    AdapterName    = $targetAdapter.Name
    IPAddress      = if ($currentIpConfig) { $currentIpConfig.IPAddress } else { $null }
    PrefixLength   = if ($currentIpConfig) { $currentIpConfig.PrefixLength } else { $null }
    Gateway        = if ($currentGateway) { $currentGateway.NextHop } else { $null }
    DnsServers     = if ($currentDns.ServerAddresses) { $currentDns.ServerAddresses } else { @() }
}
$backup | ConvertTo-Json | Set-Content -Path $backupFile -Encoding UTF8
Write-OK "ネットワーク設定をバックアップ: $backupFile"

# --- 設定値の決定 ---
$newIp = $netConfig.IPAddress
$newPrefix = $netConfig.PrefixLength
$newGateway = $netConfig.Gateway
$newDns = $netConfig.DnsServers

# Gateway が空の場合、現在の値を候補として表示
if (-not $newGateway -or $newGateway -eq '') {
    if ($currentGateway) {
        $newGateway = $currentGateway.NextHop
        Write-Host "  Gateway が未指定のため、現在値を使用: $newGateway" -ForegroundColor Yellow
    } else {
        Write-Warn "Gateway が未指定で、現在の設定からも取得できません。"
        $newGateway = Read-Host "Gateway を入力してください (空欄でスキップ)"
    }
}

# DNS が空の場合、現在の値を維持
if (-not $newDns -or $newDns.Count -eq 0) {
    if ($currentDns.ServerAddresses) {
        $newDns = $currentDns.ServerAddresses
        Write-Host "  DNS が未指定のため、現在値を維持: $($newDns -join ', ')" -ForegroundColor Yellow
    }
}

# --- IP重複チェック ---
Write-Step "IP重複チェック"
try {
    $ping = Test-Connection -ComputerName $newIp -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($ping) {
        # 自分自身のIPでないか確認
        $myIps = Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress
        if ($newIp -notin $myIps) {
            Write-Warn "$newIp は既にネットワーク上で使用されている可能性があります！"
            $confirm = Read-Host "続行しますか？ (yes/no)"
            if ($confirm -ne 'yes') {
                Write-Host "中断しました。"
                exit 0
            }
        }
    } else {
        Write-OK "$newIp はネットワーク上で応答なし (使用可能の可能性あり)"
    }
} catch {
    Write-Host "  IP重複チェックをスキップ" -ForegroundColor DarkGray
}

# --- 適用内容の表示と確認 ---
Write-Step "適用予定の設定"
Write-Host "  アダプター:     $($targetAdapter.Name) [InterfaceIndex: $($targetAdapter.InterfaceIndex)]"
Write-Host "  IPアドレス:     $newIp"
Write-Host "  サブネット:     /$newPrefix"
Write-Host "  ゲートウェイ:   $newGateway"
Write-Host "  DNS:            $(if ($newDns) { $newDns -join ', ' } else { '(なし)' })"

if ($WhatIfPreference) {
    Write-Host "`n[DRY RUN] 実際の変更は行いません。" -ForegroundColor Cyan
    exit 0
}

$confirm = Read-Host "`nこの設定を適用しますか？ (yes/no)"
if ($confirm -ne 'yes') {
    Write-Host "中断しました。"
    exit 0
}

# --- 設定の適用 ---
Write-Step "固定IPアドレスの設定"

try {
    # 既存のIP設定を削除
    if ($currentIpConfig) {
        Remove-NetIPAddress -InterfaceIndex $targetAdapter.InterfaceIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    }

    # 既存のゲートウェイを削除
    if ($currentGateway) {
        Remove-NetRoute -InterfaceIndex $targetAdapter.InterfaceIndex -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
    }

    # DHCP を無効化
    Set-NetIPInterface -InterfaceIndex $targetAdapter.InterfaceIndex -Dhcp Disabled

    # 新しいIPアドレスを設定
    $ipParams = @{
        InterfaceIndex = $targetAdapter.InterfaceIndex
        IPAddress      = $newIp
        PrefixLength   = $newPrefix
        AddressFamily  = 'IPv4'
    }
    if ($newGateway -and $newGateway -ne '') {
        $ipParams['DefaultGateway'] = $newGateway
    }
    New-NetIPAddress @ipParams | Out-Null

    # DNS設定
    if ($newDns -and $newDns.Count -gt 0) {
        Set-DnsClientServerAddress -InterfaceIndex $targetAdapter.InterfaceIndex -ServerAddresses $newDns
    }

    Write-OK "固定IPアドレスを設定しました"

    # 設定の確認
    Start-Sleep -Seconds 2
    $verifyIp = Get-NetIPAddress -InterfaceIndex $targetAdapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($verifyIp -and $verifyIp.IPAddress -eq $newIp) {
        Write-OK "設定の確認完了: $($verifyIp.IPAddress)/$($verifyIp.PrefixLength)"
    } else {
        Write-Warn "設定後のIPアドレスが期待値と異なります。確認してください。"
    }
} catch {
    Write-Fail "固定IPアドレスの設定に失敗: $_"
    Write-Host "  DHCP に戻すには以下を実行してください:"
    Write-Host "  .\07-configure-network.ps1 -RevertToDHCP" -ForegroundColor White
    exit 1
}

Write-Host ""
Write-Host "  DHCP に戻すには:" -ForegroundColor DarkGray
Write-Host "  .\07-configure-network.ps1 -RevertToDHCP" -ForegroundColor White
Write-Host ""

Write-OK "Phase 7: ネットワーク設定完了"
