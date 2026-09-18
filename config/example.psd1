@{
    # === Git設定 ===
    GitUserName  = "Your Name"
    GitUserEmail = "your-email@example.com"

    # === PC名 (空文字の場合は変更しない) ===
    ComputerName = ""

    # === スリープ無効化 ($true で無効化する) ===
    DisableSleep = $false

    # === デスクトップのゴミ箱アイコン ($true で非表示、未指定時も非表示) ===
    HideDesktopRecycleBin = $true

    # === SSHデフォルトシェル ===
    # PowerShell 7をSSHのデフォルトシェルにする
    SetDefaultShell = $true

    # === AutoHotkey (06-configure-ime.ps1) ===
    # Startup にショートカットを登録して自動起動する (実体は assets\ を直接参照)
    EnableAutoHotkey       = $true   # win-space-ime.ahk : Win+Space IMEトグル / Win単独無効
    EnableEmacsKeys        = $true   # emacs-keys.ahk : Ctrl+A/E/B/F/P/N 等の Emacs 風キーバインド
    EnableCtrlCtrlTerminal = $true   # ctrl-ctrl-terminal.ahk : Ctrl 2回押しでホットキーターミナル

    # === ハードウェアキーボードレイアウト (06-configure-ime.ps1) ===
    # 物理キーボードの配列。"US" (101/102) / "JIS" (106/109) / "" (変更しない)
    # MS-IME を入れると入力ロケールが日本語 (00000411) になるため、
    # US 配列のキーボードでは "US" を指定しないと @ [ ] : " 等がずれる。要管理者+再起動。
    HardwareKeyboardLayout = ""

    # === キーボード (12-configure-keyboard.ps1) ===
    PowerToysKeyboardManager    = $true   # assets\powertoys-keyboard-manager.json を反映 (Win+C/V → Ctrl+C/V)
    PowerToysDisableFindMyMouse = $true   # Ctrl 2回押しがターミナルと競合するため Find My Mouse を無効化
    CapsLockToCtrl              = $true   # $true で CapsLock → 左Ctrl (Scancode Map, 要管理者+再起動)

    # === WinGetアプリ ===
    # $false にするとインストールをスキップ
    WinGetApps = @{
        GoogleChrome    = $true
        Slack           = $true
        Cursor          = $true
        OnePassword     = $true
        Tailscale       = $true
        AutoHotkey      = $true
        CopyQ           = $true
        PowerToys       = $true
        WindowsTerminal = $true
        PowerShell7     = $true
        Git             = $true
    }

    # === Scoopツール ===
    ScoopTools = @{
        "7zip"       = $true
        "jq"         = $true
        "yq"         = $true
        "ripgrep"    = $true
        "fd"         = $true
        "fzf"        = $true
        "vim"        = $true
        "nodejs-lts" = $true
        "python"     = $true
    }

    # === Datadog メトリクスコレクタ ===
    # 10-install-datadog-collector.ps1 で使用。CPU/メモリ/GPU を Datadog へ送る。
    # ApiKey は秘密情報なので config\local.psd1 にのみ実値を書くこと (このファイルはコミットされる)。
    Datadog = @{
        Enabled  = $false
        ApiKey   = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # Datadog API キー
        Site     = "datadoghq.com"                     # ap1.datadoghq.com / datadoghq.eu / us5.datadoghq.com など
        Interval = 15                                  # 送信間隔(秒)
    }

    # === USB 復旧タスク (13-install-usb-resume-fix.ps1) ===
    # スリープ復帰後に USB デバイスがエラー状態なら xHCI コントローラを
    # PnP 再起動して復旧するタスクを登録する (要管理者)。
    UsbResumeFix = @{
        Enabled = $false
        ControllerInstanceId = ''   # 空なら自動検出。固定したい場合のみ 'PCI\VEN_...' を指定
    }

    # === Datadog キオスク (14-install-datadog-kiosk.ps1) ===
    # ダッシュボード等を Chrome アプリウィンドウで指定座標に常時表示する。
    # URL は環境固有情報を含むため config\local.psd1 (gitignore 済み) にのみ書くこと。
    DatadogKiosk = @{
        Enabled = $false
        Windows = @(
            @{ Match = 'datadog'                                  # ウィンドウタイトルの正規表現
               Url   = 'https://app.datadoghq.com/dashboard/xxx'  # 表示する URL
               X = 0; Y = 0; W = 1280; H = 1400 }                 # ウィンドウ位置とサイズ
        )
    }

    # === ネットワーク (固定IP) ===
    # 07-configure-network.ps1 でのみ使用。setup-all.ps1 からは呼ばれない
    Network = @{
        Enabled        = $false
        IPAddress      = "192.168.100.5"
        PrefixLength   = 16
        Gateway        = ""
        DnsServers     = @()
        AdapterName    = ""
        InterfaceIndex = $null
    }
}
