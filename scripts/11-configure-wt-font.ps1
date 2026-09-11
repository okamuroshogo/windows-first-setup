<#
.SYNOPSIS
    Windows Terminal のフォントだけを PlemolJP Console NF に変更する
.DESCRIPTION
    - GitHub Releases から最新の「PlemolJP Console NF」を取得し、現在のユーザーにだけ
      インストールする (管理者権限不要 / システムフォントは変更しない)。
    - Windows Terminal (安定版 / Preview) の profiles.defaults.font だけを追加・更新する。
      既存の settings.json は変更前に同ディレクトリへバックアップし、他の設定は維持する。
    - 冪等: 何度実行しても同じ結果に収束する。一時ファイルは処理後に削除する。

    元に戻すには: バックアップ (settings.backup-*.json) を settings.json に戻すか、
    settings.json の profiles.defaults.font を削除して Windows Terminal を再起動する。
    フォント自体は HKCU:\...\Fonts の該当エントリ削除 + %LOCALAPPDATA%\Microsoft\Windows\Fonts の
    PlemolJP*Console*NF*.ttf 削除で除去できる。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$FaceName = 'PlemolJP Console NF'   # Windows Terminal に設定するフォント名
$FontSize = 11
$FontWeight = 'light'
$Repo = 'yuru7/PlemolJP'            # PlemolJP 配布元

$step = '初期化'
$tmp = $null
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # ---- 1. すでにフォントが入っているか確認 (冪等) ----
    $step = 'インストール済みフォントの確認'
    $userFontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $installed = Test-Path (Join-Path $userFontDir 'PlemolJPConsoleNF-*.ttf')

    if ($installed) {
        Write-Host "[skip] '$FaceName' は既にインストール済みです。" -ForegroundColor DarkGray
    } else {
        # ---- 2. 最新リリースから Nerd Font 版 zip を取得 ----
        #  Nerd Font 版 zip の中に PlemolJPConsole_NF (= PlemolJP Console NF) が同梱されている
        $step = 'GitHub リリース情報の取得'
        Write-Host "[1/4] 最新リリースを問い合わせ中 ($Repo)..." -ForegroundColor Cyan
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
            -Headers @{ 'User-Agent' = 'wt-font-setup'; 'Accept' = 'application/vnd.github+json' }

        $asset = $rel.assets |
            Where-Object { $_.name -match '_NF_' -and $_.name -notmatch '_HS' -and $_.name -like '*.zip' } |
            Sort-Object { $_.name.Length } |
            Select-Object -First 1
        if (-not $asset) { throw "リリースに Nerd Font 版 (_NF_) の zip が見つかりませんでした ($($rel.tag_name))。" }

        # ---- 3. ダウンロード & 展開 ----
        $step = 'フォントのダウンロードと展開'
        Write-Host "[2/4] ダウンロード中: $($asset.name) ($($rel.tag_name))" -ForegroundColor Cyan
        $tmp = Join-Path $env:TEMP ("plemoljp-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $zip = Join-Path $tmp $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing `
            -Headers @{ 'User-Agent' = 'wt-font-setup' }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force

        # ---- 4. 現在のユーザーにだけインストール ----
        $step = 'ユーザーフォントのインストール'
        Write-Host "[3/4] 現在のユーザーにインストール中..." -ForegroundColor Cyan
        if (-not (Test-Path $userFontDir)) { New-Item -ItemType Directory -Path $userFontDir -Force | Out-Null }
        $regKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }

        Add-Type -Namespace Win32 -Name Font -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("gdi32.dll")] public static extern int AddFontResource(string p);
'@
        # zip には PlemolJPConsole / PlemolJP35Console 等が同梱されるため、目的の Console NF だけ抽出する
        $ttfs = Get-ChildItem -Path $tmp -Recurse -Filter '*.ttf' |
            Where-Object { $_.Name -match '^PlemolJPConsoleNF-' }
        if (-not $ttfs) { throw "展開したファイルの中に PlemolJPConsoleNF-*.ttf が見つかりませんでした。" }
        foreach ($f in $ttfs) {
            $dest = Join-Path $userFontDir $f.Name
            Copy-Item $f.FullName $dest -Force
            [Win32.Font]::AddFontResource($dest) | Out-Null
            # 再ログオン後も有効になるよう HKCU に登録 (per-user はフルパスを値にする)
            New-ItemProperty -Path $regKey -Name ("{0} (TrueType)" -f $f.BaseName) `
                -Value $dest -PropertyType String -Force | Out-Null
        }
        Write-Host "      $($ttfs.Count) 個のフォントを登録しました。" -ForegroundColor DarkGray
    }

    # ---- 5. Windows Terminal の設定を更新 ----
    $step = 'Windows Terminal 設定の更新'
    Write-Host "[4/4] Windows Terminal のフォントを設定中..." -ForegroundColor Cyan
    $settingsPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path $_ }

    if (-not $settingsPaths) {
        Write-Warning "Windows Terminal の settings.json が見つかりませんでした。一度 Windows Terminal を起動してから再実行してください。"
    }

    foreach ($sp in $settingsPaths) {
        # 変更前にバックアップ (同ディレクトリ)
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = Join-Path (Split-Path $sp -Parent) "settings.backup-$stamp.json"
        Copy-Item $sp $backup -Force

        $json = Get-Content $sp -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not ($json.PSObject.Properties.Name -contains 'profiles')) {
            $json | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        if (-not ($json.profiles.PSObject.Properties.Name -contains 'defaults')) {
            $json.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        # profiles.defaults.font だけを追加・更新 (他の設定は維持)
        $json.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{
            face   = $FaceName
            size   = $FontSize
            weight = $FontWeight
        }) -Force

        ($json | ConvertTo-Json -Depth 100) | Set-Content -Path $sp -Encoding UTF8
        Write-Host "      更新: $sp" -ForegroundColor DarkGray
        Write-Host "      バックアップ: $backup" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "完了: フォントを '$FaceName' (size $FontSize / weight $FontWeight) に設定しました。" -ForegroundColor Green
    Write-Host "反映するには Windows Terminal を再起動してください。" -ForegroundColor Yellow
}
catch {
    Write-Host ""
    Write-Host "失敗した処理: $step" -ForegroundColor Red
    Write-Host "エラー内容: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    # 一時ファイルの削除
    if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
