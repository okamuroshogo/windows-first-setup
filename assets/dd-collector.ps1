# ============================================================
#  Datadog 軽量メトリクスコレクタ (CPU / メモリ / GPU)
#  ※これはテンプレートです。10-install-datadog-collector.ps1 が
#    __DD_*__ トークンを config の値に置換し、実体を
#    %LOCALAPPDATA%\dd-collector\ に配置します。
#  - 配置後のスクリプトには APIキー/サイト/間隔が焼き込まれます (実行時ハードコード)。
#  - GPU は NVIDIA に依存せず Windows のパフォーマンスカウンタから取得 (AMD/Intel 対応)。
# ============================================================

# ---- インストール時に焼き込まれる設定 ----
$ApiKey   = "__DD_API_KEY__"
$Site     = "__DD_SITE__"        # 例: ap1.datadoghq.com
$Interval = __DD_INTERVAL__      # 送信間隔(秒)

$HostName = $env:COMPUTERNAME
$Tags     = @("host:$HostName", "source:dd-collector", "os:windows", "server:win")
$Endpoint = "https://api.$Site/api/v2/series"
$LogFile  = Join-Path $PSScriptRoot "dd-collector.log"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log($msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $LogFile -Value $line
    if ((Get-Item $LogFile -ErrorAction SilentlyContinue).Length -gt 1MB) {
        $tail = Get-Content $LogFile -Tail 500
        Set-Content -Path $LogFile -Value $tail
    }
}

function Get-Sample {
    $unix = [int64](([DateTimeOffset](Get-Date)).ToUnixTimeSeconds())
    $series = New-Object System.Collections.Generic.List[object]

    function Add-Metric($name, $value, $extraTags = @()) {
        if ($null -eq $value) { return }
        $series.Add([ordered]@{
            metric    = $name
            type      = 3   # gauge
            points    = @(@{ timestamp = $unix; value = [double]$value })
            tags      = @($Tags + $extraTags)
            resources = @(@{ name = $HostName; type = "host" })
        })
    }

    # ---- CPU ----
    try {
        $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples[0].CookedValue
        $cpu = [math]::Round($cpu, 2)
        Add-Metric "system.cpu.percent" $cpu
        # ダッシュボードは 100 - system.cpu.idle で使用率を算出するため idle も送る
        Add-Metric "system.cpu.idle" ([math]::Round(100 - $cpu, 2))
    } catch { Write-Log "CPU read error: $($_.Exception.Message)" }

    # ---- メモリ ----
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalKB = $os.TotalVisibleMemorySize
        $freeKB  = $os.FreePhysicalMemory
        $usedKB  = $totalKB - $freeKB
        Add-Metric "system.mem.total_bytes" ($totalKB * 1024)
        Add-Metric "system.mem.used_bytes"  ($usedKB  * 1024)
        Add-Metric "system.mem.used_percent" ([math]::Round(($usedKB / $totalKB) * 100, 2))
        # ダッシュボードは (1 - system.mem.pct_usable) * 100 で使用率を算出 (pct_usable は 0..1 の空き割合)
        Add-Metric "system.mem.pct_usable" ([math]::Round($freeKB / $totalKB, 4))
    } catch { Write-Log "MEM read error: $($_.Exception.Message)" }

    # ---- GPU 使用率 (全エンジンの合計と最大) ----
    try {
        $samples = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop).CounterSamples
        $vals = $samples | Select-Object -ExpandProperty CookedValue
        $sum  = ($vals | Measure-Object -Sum).Sum
        $max  = ($vals | Measure-Object -Maximum).Maximum
        $utilPct = [math]::Round([math]::Min($sum, 100), 2)
        Add-Metric "gpu.utilization.percent"     $utilPct
        Add-Metric "gpu.utilization.max_percent" ([math]::Round($max, 2))
        # ダッシュボード互換 (nvidia.gpu.* / gpu_index:0)
        Add-Metric "nvidia.gpu.utilization" $utilPct @("gpu_index:0")
    } catch { Write-Log "GPU util read error: $($_.Exception.Message)" }

    # ---- GPU 専有メモリ (使用量) ----
    try {
        $mem = (Get-Counter '\GPU Process Memory(*)\Dedicated Usage' -ErrorAction Stop).CounterSamples |
               Measure-Object CookedValue -Sum
        $vramUsed = [int64]$mem.Sum
        Add-Metric "gpu.memory.dedicated_bytes" $vramUsed
        # ダッシュボード互換 (nvidia.gpu.memory.used / gpu_index:0)
        Add-Metric "nvidia.gpu.memory.used" $vramUsed @("gpu_index:0")
    } catch { Write-Log "GPU mem read error: $($_.Exception.Message)" }

    # ---- GPU 専有メモリ (総量) ----
    #  WMI の AdapterRAM は 4GB で頭打ちになるためレジストリの qwMemorySize を使用 (AMD/Intel/NVIDIA 共通)
    #  一部サブキーは非管理者だと列挙できないため SilentlyContinue で読める分だけ使う
    try {
        $clsBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
        $vramTotal = Get-ChildItem $clsBase -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).'HardwareInformation.qwMemorySize' } |
            Where-Object { $_ } |
            Measure-Object -Maximum |
            Select-Object -ExpandProperty Maximum
        if ($vramTotal) {
            Add-Metric "gpu.memory.total_bytes" ([int64]$vramTotal)
            # ダッシュボード互換 (nvidia.gpu.memory.total / gpu_index:0)
            Add-Metric "nvidia.gpu.memory.total" ([int64]$vramTotal) @("gpu_index:0")
        }
    } catch { Write-Log "GPU mem total read error: $($_.Exception.Message)" }

    return @{ series = $series }
}

Write-Log "=== dd-collector start (site=$Site interval=${Interval}s host=$HostName) ==="

while ($true) {
    try {
        $payload = Get-Sample | ConvertTo-Json -Depth 8 -Compress
        Invoke-RestMethod -Method Post -Uri $Endpoint `
            -Headers @{ "DD-API-KEY" = $ApiKey; "Content-Type" = "application/json" } `
            -Body $payload -ErrorAction Stop | Out-Null
    } catch {
        Write-Log "SEND error: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $Interval
}
