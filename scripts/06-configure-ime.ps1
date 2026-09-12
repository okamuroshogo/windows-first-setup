<#
.SYNOPSIS
    IME設定とAutoHotkeyスクリプトの配置
.DESCRIPTION
    AutoHotkey v2 のスクリプト群を Startup のショートカット (.lnk) として
    登録し、起動する。実体はリポジトリ内の assets\ を直接参照するため、
    git pull で更新が反映される (コピーによる二重管理をしない)。

    - win-space-ime.ahk      : Win+Space で IME トグル / Win 単独無効 / Ctrl+Space でスタート
    - emacs-keys.ahk         : Ctrl+A/E/B/F/P/N/H/D/K 等の Emacs 風キーバインド
    - ctrl-ctrl-terminal.ahk : Ctrl ダブルタップでホットキー専用ターミナルをトグル

    config: EnableAutoHotkey / EnableEmacsKeys / EnableCtrlCtrlTerminal
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ヘルパー読み込み
. (Join-Path $PSScriptRoot '_helpers.ps1')

Write-Step "Phase 6: IME 設定 / AutoHotkey"

$config = Read-Config

# --- AHKスクリプト定義 (ConfigKey が $false なら無効化) ---
$repoRoot = Split-Path $PSScriptRoot -Parent
$ahkScripts = @(
    @{ Name = 'win-space-ime';      ConfigKey = 'EnableAutoHotkey';        Desc = 'Win+Space IME トグル' },
    @{ Name = 'emacs-keys';         ConfigKey = 'EnableEmacsKeys';         Desc = 'Emacs 風キーバインド' },
    @{ Name = 'ctrl-ctrl-terminal'; ConfigKey = 'EnableCtrlCtrlTerminal';  Desc = 'Ctrl 2回押しターミナル' }
)

foreach ($s in $ahkScripts) {
    $s.Enabled = if ($config.ContainsKey($s.ConfigKey)) { [bool]$config[$s.ConfigKey] } else { $true }
    $s.Path = Join-Path $repoRoot "assets\$($s.Name).ahk"
}

if (-not ($ahkScripts | Where-Object Enabled)) {
    Write-Host "[SKIP] すべての AutoHotkey スクリプトが設定で無効化されています"
    Write-OK "Phase 6: IME 設定完了 (スキップ)"
    return
}

# --- AutoHotkey v2 の存在確認 ---
$ahkExe = $null
$ahkPaths = @(
    (Get-Command 'AutoHotkey64.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    (Get-Command 'AutoHotkey.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'),
    (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'AutoHotkey\v2\AutoHotkey64.exe')
)

foreach ($path in $ahkPaths) {
    if ($path -and (Test-Path $path)) {
        $ahkExe = $path
        break
    }
}

if (-not $ahkExe) {
    Write-Warn "AutoHotkey v2 が見つかりません。先に WinGet でインストールしてください。"
    Write-Host "  winget install AutoHotkey.AutoHotkey"
    Write-OK "Phase 6: IME 設定完了 (AutoHotkey未インストール)"
    return
}

Write-OK "AutoHotkey を検出: $ahkExe"

# --- Startup ショートカットの整備 ---
Write-Step "AutoHotkey スクリプトの Startup 登録"

$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$shell = New-Object -ComObject WScript.Shell

# 旧方式 (Startup に .ahk 実体をコピー) の残骸を削除
$legacyAhk = Join-Path $startupDir 'win-space-ime.ahk'
if (Test-Path $legacyAhk) {
    Remove-Item $legacyAhk -Force
    Write-OK "旧方式の実体コピーを削除: $legacyAhk"
}

foreach ($s in $ahkScripts) {
    $lnkPath = Join-Path $startupDir "$($s.Name).lnk"

    if (-not $s.Enabled) {
        if (Test-Path $lnkPath) {
            Remove-Item $lnkPath -Force
            Write-OK "$($s.Name): 無効化されたためショートカットを削除"
        } else {
            Write-Host "[SKIP] $($s.Name) ($($s.ConfigKey) = `$false)"
        }
        continue
    }

    if (-not (Test-Path $s.Path)) {
        Write-Fail "AHKスクリプトが見つかりません: $($s.Path)"
        exit 1
    }

    $lnk = $shell.CreateShortcut($lnkPath)
    $lnk.TargetPath  = $ahkExe
    $lnk.Arguments   = "`"$($s.Path)`""
    $lnk.Description = $s.Desc
    $lnk.Save()
    Write-OK "$($s.Name): Startup ショートカットを登録 (実体: $($s.Path))"
}

# --- 既存の AHK プロセスを停止して起動し直す ---
Write-Step "AutoHotkey スクリプトの起動"

$namePattern = ($ahkScripts | ForEach-Object { [regex]::Escape($_.Name) }) -join '|'
$running = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" |
    Where-Object { $_.CommandLine -match $namePattern }

foreach ($p in $running) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}
if ($running) {
    Start-Sleep -Seconds 1
    Write-OK "既存の AHK プロセスを停止しました ($(@($running).Count) 個)"
}

foreach ($s in $ahkScripts | Where-Object Enabled) {
    Start-Process -FilePath $ahkExe -ArgumentList "`"$($s.Path)`""
    Write-OK "$($s.Name) を起動しました"
}

# --- 日本語 IME (Microsoft IME) の登録 ---
#  Win+Space の IME トグルは「MS-IME が入力方式として登録されている」ことが前提。
#  日本語 Windows でもセットアップ時に英語キーボードを選ぶと言語リストが
#  ja / 入力方式ゼロ (実体は 00000409 の US レイアウトのみ) になることがあり、
#  この状態だとトグルする IME 自体が存在せず Win+Space が無反応になる。
Write-Step "日本語 IME (Microsoft IME) の登録確認"

$MsImeTip = '0411:{03B5835F-F03C-411B-9CE2-AA23E1171E36}{A76C93D9-5523-4E90-AAFA-4DB112F9AC76}'

try {
    $langList = Get-WinUserLanguageList
    $ja = $langList | Where-Object { $_.LanguageTag -eq 'ja' }

    if (-not $ja) {
        $langList.Add('ja')
        $ja = $langList | Where-Object { $_.LanguageTag -eq 'ja' }
        Write-OK "言語リストに日本語 (ja) を追加"
    }

    if ($ja.InputMethodTips -contains $MsImeTip) {
        Write-OK "Microsoft IME は既に登録済み"
    } else {
        $ja.InputMethodTips.Add($MsImeTip)
        Set-WinUserLanguageList $langList -Force
        Write-OK "Microsoft IME を入力方式として登録しました (Win+Space のトグル対象)"
    }
} catch {
    Write-Warn "Microsoft IME の登録に失敗: $_"
}

# --- ハードウェアキーボードレイアウト (US / JIS) ---
#  MS-IME を入れると入力ロケールが 00000411 (日本語 106/109) になるため、
#  物理キーボードが US 配列だと @ [ ] : " 等が入れ替わってしまう。
#  i8042prt の Override* で「英語キーボード (101/102)」に切り替える。
#  HKLM への書き込みなので管理者権限が必要 + 反映には再起動 (サインアウト) が必要。
$kbLayout = if ($config.ContainsKey('HardwareKeyboardLayout')) { "$($config.HardwareKeyboardLayout)" } else { '' }

if ($kbLayout) {
    Write-Step "ハードウェアキーボードレイアウト: $kbLayout"

    $kbProfiles = @{
        'US'  = @{ Driver = 'kbd101.dll'; Identifier = 'PCAT_101KEY'; Type = 7; Subtype = 0 }
        'JIS' = @{ Driver = 'kbd106.dll'; Identifier = 'PCAT_106KEY'; Type = 7; Subtype = 2 }
    }

    if (-not $kbProfiles.ContainsKey($kbLayout)) {
        Write-Warn "HardwareKeyboardLayout の値が不正です: '$kbLayout' (US または JIS)"
    } elseif (-not (Test-IsAdmin)) {
        Write-Warn "ハードウェアキーボードレイアウトの変更には管理者権限が必要です。スキップします。"
    } else {
        $kb = $kbProfiles[$kbLayout]
        $kbKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters'
        $current = Get-ItemProperty $kbKey -ErrorAction SilentlyContinue

        if ($current -and $current.OverrideKeyboardIdentifier -eq $kb.Identifier) {
            Write-OK "既に $kbLayout 配列 ($($kb.Identifier)) に設定済み"
        } else {
            try {
                Set-ItemProperty $kbKey -Name 'LayerDriver JPN'            -Value $kb.Driver     -ErrorAction Stop
                Set-ItemProperty $kbKey -Name 'OverrideKeyboardIdentifier' -Value $kb.Identifier -ErrorAction Stop
                Set-ItemProperty $kbKey -Name 'OverrideKeyboardType'       -Value $kb.Type    -Type DWord -ErrorAction Stop
                Set-ItemProperty $kbKey -Name 'OverrideKeyboardSubtype'    -Value $kb.Subtype -Type DWord -ErrorAction Stop
                Write-OK "$kbLayout 配列 ($($kb.Identifier) / $($kb.Driver)) に設定しました"
                Write-Warn "反映には再起動が必要です。"
            } catch {
                Write-Warn "ハードウェアキーボードレイアウトの変更に失敗: $_"
            }
        }
    }
}

# --- 言語設定の確認 ---
Write-Step "言語設定の確認"

try {
    $languages = Get-WinUserLanguageList
    Write-Host "  現在の言語リスト:"
    foreach ($lang in $languages) {
        Write-Host "    - $($lang.LanguageTag): $($lang.LocalizedName)" -ForegroundColor DarkGray
        foreach ($kb in $lang.InputMethodTips) {
            Write-Host "      キーボード: $kb" -ForegroundColor DarkGray
        }
    }
} catch {
    Write-Warn "言語設定の取得に失敗: $_"
}

Write-Host ""
Write-Host "  ※ Win+Space で IME のオン・オフを切り替えられます。" -ForegroundColor White
Write-Host "  ※ Ctrl を素早く2回押すとホットキー専用ターミナルが開閉します。" -ForegroundColor White
Write-Host "  ※ 管理者権限で起動したアプリでは、通常権限の AutoHotkey が効かない場合があります。" -ForegroundColor Yellow

Write-OK "Phase 6: IME 設定完了"
