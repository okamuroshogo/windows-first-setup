@{
    # === Git設定 ===
    GitUserName  = "Your Name"
    GitUserEmail = "your-email@example.com"

    # === PC名 (空文字の場合は変更しない) ===
    ComputerName = ""

    # === スリープ無効化 ($true で無効化する) ===
    DisableSleep = $false

    # === SSHデフォルトシェル ===
    # PowerShell 7をSSHのデフォルトシェルにする
    SetDefaultShell = $true

    # === AutoHotkey ===
    # Win+SpaceのIMEトグルスクリプトをStartupに配置する
    EnableAutoHotkey = $true

    # === WinGetアプリ ===
    # $false にするとインストールをスキップ
    WinGetApps = @{
        GoogleChrome    = $true
        Slack           = $true
        Cursor          = $true
        OnePassword     = $true
        Tailscale       = $true
        Discord         = $true
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
