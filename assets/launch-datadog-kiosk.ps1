# Chrome アプリウィンドウを指定座標に並べるキオスクランチャー。
# レイアウト (URL・座標) は同じフォルダの kiosk-layout.json から読み込む。
# URL などの環境固有情報をリポジトリに含めないため、レイアウトは
# 14-install-datadog-kiosk.ps1 が config\local.psd1 から生成して配置する。
#
# kiosk-layout.json 形式:
#   { "windows": [ { "match": "タイトル正規表現", "url": "...",
#                    "x": 0, "y": 0, "w": 1280, "h": 1400 }, ... ] }

$ErrorActionPreference = 'Stop'

$kioskDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$layoutFile = Join-Path $kioskDir 'kiosk-layout.json'

if (-not (Test-Path $layoutFile)) {
    Write-Error "レイアウトファイルが見つかりません: $layoutFile"
    exit 1
}
$layout = @((Get-Content $layoutFile -Raw | ConvertFrom-Json).windows)

$chrome = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) {
    Write-Error 'Chrome が見つかりません。'
    exit 1
}

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class KioskWin32 {
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int X, int Y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  public class Info { public IntPtr H; public string Title; public uint Pid; }
  public static List<Info> GetAll() {
    var list = new List<Info>();
    EnumWindows((h, lp) => {
      if (!IsWindowVisible(h)) return true;
      var sb = new StringBuilder(512);
      GetWindowText(h, sb, 512);
      if (sb.Length == 0) return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      list.Add(new Info { H = h, Title = sb.ToString(), Pid = pid });
      return true;
    }, IntPtr.Zero);
    return list;
  }
}
"@

# 各 URL を専用プロファイルのアプリウィンドウとして起動
foreach ($w in $layout) {
  $argList = @(
    "--user-data-dir=$kioskDir",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-session-crashed-bubble",
    "--new-window",
    "--window-position=$($w.x),$($w.y)",
    "--window-size=$($w.w),$($w.h)",
    "--app=$($w.url)"
  )
  Start-Process -FilePath $chrome -ArgumentList $argList
  Start-Sleep -Milliseconds 800
}

# キオスク用プロファイルを使う chrome.exe だけを対象にする
# (通常の Chrome で開いているタブには触らない)
function Get-KioskPids {
  (Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" |
    Where-Object { $_.CommandLine -match [regex]::Escape($kioskDir) }).ProcessId
}

# 両ウィンドウの出現を待って配置する (タイトル = ページタイトル or URLホスト)
$deadline = (Get-Date).AddSeconds(30)
$placed = @{}
while ((Get-Date) -lt $deadline -and $placed.Count -lt $layout.Count) {
  Start-Sleep -Milliseconds 500
  $pids = @(Get-KioskPids)
  $wins = [KioskWin32]::GetAll() | Where-Object { $pids -contains $_.Pid }
  foreach ($w in $layout) {
    if ($placed.ContainsKey($w.match)) { continue }
    $hit = $wins | Where-Object { $_.Title -imatch $w.match } | Select-Object -First 1
    if ($hit) {
      [KioskWin32]::ShowWindow($hit.H, 9) | Out-Null   # SW_RESTORE
      # 0x40 = SWP_SHOWWINDOW (NOZORDER なし: IntPtr.Zero = HWND_TOP)
      [KioskWin32]::SetWindowPos($hit.H, [IntPtr]::Zero, $w.x, $w.y, $w.w, $w.h, 0x40) | Out-Null
      $placed[$w.match] = $true
    }
  }
}
