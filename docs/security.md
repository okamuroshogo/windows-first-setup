# セキュリティに関する注意事項

このリポジトリのスクリプトを安全に使うために、以下の点に注意してください。

---

## `irm | iex` の危険性

PowerShell でよく見かける以下のパターンは危険です。

```powershell
# 危険な例 - 絶対にこのまま実行しないでください
irm https://example.com/install.ps1 | iex
```

**なぜ危険か:**

- **コードを確認できない** -- リモートから取得したスクリプトがそのまま `Invoke-Expression` に渡されるため、実行前に内容を確認する機会がありません。悪意のあるコードが含まれていても気づけません。
- **中間者攻撃 (MITM)** -- HTTPS であっても、プロキシ環境や証明書の設定によっては通信が改ざんされる可能性があります。攻撃者がスクリプトの内容を差し替えることができます。
- **URL の内容が変わる** -- 同じ URL でも、時間の経過やサーバー側の変更によって返されるスクリプトの内容が変わる可能性があります。昨日安全だったスクリプトが、今日も安全とは限りません。

**推奨される方法:**

```powershell
# 1. まずダウンロードする
Invoke-WebRequest -Uri https://example.com/install.ps1 -OutFile install.ps1

# 2. 内容を確認する
Get-Content install.ps1 | more

# 3. 問題がなければ実行する
.\install.ps1
```

このリポジトリのスクリプトについても、`git clone` してから内容を確認した上で実行してください。

---

## 公開リポジトリへの秘密情報の扱い

公開リポジトリには以下の情報を絶対にコミットしないでください。

- **パスワード** -- サービスのログインパスワード、データベースのパスワードなど
- **APIキー / トークン** -- GitHub Personal Access Token、クラウドサービスのAPIキーなど
- **SSH秘密鍵** -- `id_ed25519`、`id_rsa` などの秘密鍵ファイル
- **メールアドレス** -- スパムの対象になる可能性があります

このリポジトリでは、個人の設定値を `config/local.psd1` に記述する設計になっています。このファイルは `.gitignore` に含まれているため、Git にコミットされません。

```
# .gitignore より
config/local.psd1
```

設定ファイルのテンプレートとして `config/local.psd1.example` を用意しています。このファイルをコピーして、自分の環境に合わせて値を変更してください。

```powershell
Copy-Item .\config\local.psd1.example .\config\local.psd1
notepad .\config\local.psd1
```

**コミット前の確認:**

```powershell
# ステージングされたファイルに秘密情報が含まれていないか確認
git diff --cached --name-only
```

---

## SSH鍵の管理

SSH鍵の扱いを誤ると、サーバーへの不正アクセスにつながります。

### 基本原則

- **秘密鍵はクライアントマシンに留める** -- 秘密鍵 (`id_ed25519`, `id_rsa`) は、生成したマシンの `~/.ssh/` ディレクトリから移動させないでください。
- **公開鍵だけをサーバーに登録する** -- サーバーの `~/.ssh/authorized_keys` に登録するのは公開鍵 (`.pub` ファイル) の内容だけです。

### 公開鍵の登録方法

```powershell
# 方法1: ssh-copy-id を使う (Linux/macOS から)
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@host

# 方法2: 手動でコピーする
# クライアント側で公開鍵の内容を表示
Get-Content ~/.ssh/id_ed25519.pub

# サーバー側で authorized_keys に追記
# (表示された内容をコピーして、サーバーの authorized_keys に貼り付け)
```

### やってはいけないこと

- 秘密鍵をメール、チャット、クラウドストレージで共有する
- 秘密鍵をリポジトリにコミットする
- 秘密鍵をサーバーにコピーする (サーバーから別のサーバーへ接続したい場合は SSH Agent Forwarding を使う)

---

## ネットワークセキュリティ

### SSH ポートを外部に公開しない

TCP ポート 22 をルーターのポートフォワーディングでインターネットに公開しないでください。公開すると、世界中からブルートフォース攻撃を受けます。

```
# 危険: ルーターで以下のような設定をしない
外部ポート 22 -> 内部IP:22 のポートフォワーディング
```

### リモートアクセスには Tailscale を使う

外出先から自宅のマシンにアクセスしたい場合は、Tailscale を使ってください。Tailscale は WireGuard ベースの VPN で、NAT の内側にあるマシン同士を安全に接続できます。

```powershell
# Tailscale 経由で SSH 接続
ssh user@100.x.x.x    # Tailscale が割り当てた IP
ssh user@hostname      # MagicDNS を使う場合
```

### ファイアウォールルールは LAN のみに制限する

Windows ファイアウォールの SSH 受信規則は、ローカルネットワーク (LAN) からの接続のみ許可するように設定してください。

```powershell
# ファイアウォール規則の確認
Get-NetFirewallRule -Name *ssh* | Get-NetFirewallAddressFilter

# LAN のみに制限する例
Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -RemoteAddress LocalSubnet
```

---

## パスワード認証

SSH サーバーの `sshd_config` でパスワード認証を無効化する際は、必ず以下の手順を守ってください。

### 手順

1. **まず公開鍵認証でログインできることを確認する**

```powershell
# 公開鍵を明示的に指定して接続テスト
ssh -i ~/.ssh/id_ed25519 user@host
```

2. **別のターミナルで SSH セッションを開いたまま** にしておく (設定ミスで締め出されるのを防ぐ)

3. **パスワード認証を無効化する**

```
# sshd_config
PasswordAuthentication no
```

4. **sshd を再起動する**

```powershell
Restart-Service sshd
```

5. **新しいターミナルから接続できることを確認する** (既存のセッションは閉じない)

**パスワード認証を無効化する前に公開鍵でのログインが確認できていない場合、マシンにリモートからアクセスできなくなります。** 物理アクセスがない環境では特に注意してください。

---

## クリップボード履歴

CopyQ などのクリップボード履歴ツールは便利ですが、コピーした内容がすべて記録されるため、セキュリティ上のリスクがあります。

### リスク

- パスワードマネージャー (1Password など) からコピーしたパスワードが履歴に残る
- API キーやトークンが履歴に残る
- クレジットカード番号などの機密情報が履歴に残る

### 対策

CopyQ を使用する場合は、パスワードマネージャーなどのアプリケーションを除外リストに追加してください。

```
CopyQ の設定:
  項目 -> 自動コマンド -> ウィンドウタイトルでフィルタ
  -> 1Password などのウィンドウを除外
```

1Password を使用している場合は、1Password 側の設定で「クリップボードを一定時間後にクリアする」オプションを有効にしてください (デフォルトで 90 秒後にクリアされます)。

---

## 1Password SSH Agent

1Password には SSH Agent 機能が組み込まれており、SSH 秘密鍵を 1Password の Vault 内に安全に保管できます。

### 注意点

- **SSH 鍵を複数の場所に保管しない** -- 1Password の SSH Agent を使う場合は、ファイルシステム上の `~/.ssh/` に同じ鍵を置かないでください。どちらの鍵が使われているか混乱の原因になります。
- **SSH 設定との連携** -- 1Password SSH Agent を使う場合、`~/.ssh/config` の `IdentityAgent` ディレクティブで 1Password の Agent ソケットを指定する必要があります。

```
# ~/.ssh/config の例
Host *
    IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

Windows の場合:

```
# ~/.ssh/config の例
Host *
    IdentityAgent "\\.\pipe\openssh-ssh-agent"
```

- **1Password がロックされていると SSH 接続できない** -- 1Password のロック解除が必要です。自動化スクリプトや cron ジョブでは、ファイルベースの SSH 鍵を使うことを検討してください。
- **Git の署名** -- 1Password の SSH Agent は Git コミットの署名にも使えますが、設定が別途必要です。
