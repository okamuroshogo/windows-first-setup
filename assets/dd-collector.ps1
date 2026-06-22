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
$Tags     = @("host:$HostName", "source:dd-collector", "os:windows")
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

    function Add-Metric($name, $value) {
        if ($null -eq $value) { return }
        $series.Add([ordered]@{
            metric    = $name
            type      = 3   # gauge
            points    = @(@{ timestamp = $unix; value = [double]$value })
            tags      = $Tags
            resources = @(@{ name = $HostName; type = "host" })
        })
    }

    # ---- CPU ----
    try {
        $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples[0].CookedValue
        Add-Metric "system.cpu.percent" ([math]::Round($cpu, 2))
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
    } catch { Write-Log "MEM read error: $($_.Exception.Message)" }

    # ---- GPU 使用率 (全エンジンの合計と最大) ----
    try {
        $samples = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop).CounterSamples
        $vals = $samples | Select-Object -ExpandProperty CookedValue
        $sum  = ($vals | Measure-Object -Sum).Sum
        $max  = ($vals | Measure-Object -Maximum).Maximum
        Add-Metric "gpu.utilization.percent"     ([math]::Round([math]::Min($sum, 100), 2))
        Add-Metric "gpu.utilization.max_percent" ([math]::Round($max, 2))
    } catch { Write-Log "GPU util read error: $($_.Exception.Message)" }

    # ---- GPU 専有メモリ ----
    try {
        $mem = (Get-Counter '\GPU Process Memory(*)\Dedicated Usage' -ErrorAction Stop).CounterSamples |
               Measure-Object CookedValue -Sum
        Add-Metric "gpu.memory.dedicated_bytes" ([int64]$mem.Sum)
    } catch { Write-Log "GPU mem read error: $($_.Exception.Message)" }

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
