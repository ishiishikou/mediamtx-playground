# スマートフォン実機からWebRTC publishする手順

## 目的

Windows + WSL2 上のMediaMTXへ、同一LAN内のスマートフォンブラウザから実カメラ映像をWebRTCでpublishする。

短期の検証用途に限定し、PCへmkcertやOpenSSLなどを追加インストールしない。証明書生成はDockerコンテナ内で行い、Windows Firewallの一時ルールも検証終了時に削除する。

## 構成

```text
スマートフォン Safari / Chrome
  ├─ HTTP  :8000  rootCA.pem取得（初回のみ）
  ├─ HTTPS :8889  MediaMTX WebRTC publish page / WHIP handshake
  └─ UDP   :8189  WebRTC media
             │
Windows Firewall: LocalSubnetのみ一時許可
             │
Windows / WSL2
  ├─ cert-generator  mkcertで一時CA・サーバー証明書生成
  ├─ cert-server     rootCA.pemだけHTTP配信
  └─ mediamtx        HTTPS WebRTC + RTSP
```

## PC側の前提

追加インストールは不要。以下が既に利用できること。

- Windows 10/11
- WSL2
- Docker Compose v2
- Windows PowerShell 5.1以降
- WSL内からDockerを利用できること

推奨構成はDocker DesktopのWSL 2 integrationである。Docker DesktopはpublishしたコンテナportをWindows host / local networkへ転送するため、この手順と相性がよい。

WSL内へ独立してDocker Engineをインストールしている場合は注意する。WSL2の既定ネットワークはNATであり、WindowsからWSLへのlocalhost forwardingと、LAN上の別端末からWSLへ直接到達できることは同義ではない。Windows 11でWSL mirrored networkingを利用するなど、LAN到達性を別途確保する必要がある場合がある。

`start.ps1` はMediaMTX起動後、WindowsのLAN IPに対して8000/TCPと8889/TCPの疎通を確認する。ここで失敗した場合は、コンテナとFirewallルールを自動で戻してエラー終了する。

`mkcert` は `docker/smartphone-cert/Dockerfile` で固定したv1.4.4をコンテナ内へ取得する。WindowsとWSLの証明書ストアへCAをインストールしない。

## 起動

### WSLのリポジトリから起動する場合

リポジトリ直下で以下を実行する。

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w scripts/smartphone/start.ps1)"
```

Windows Firewall変更のため、必要に応じてUACが表示される。

### Windows PowerShellから起動する場合

WSL側リポジトリを `\\wsl.localhost\<distro>\...` で開き、次を実行する。

```powershell
.\scripts\smartphone\start.ps1
```

通常はデフォルトルートを持つWindows側LAN IPv4を自動検出する。VPNや複数NICで誤検出する場合は明示する。

```powershell
.\scripts\smartphone\start.ps1 -LanIp 192.0.2.10
```

上の `192.0.2.10` はドキュメント用の例であり、実行時は自分のPCのLAN IPを指定する。

WSLディストリビューションを明示する場合:

```powershell
.\scripts\smartphone\start.ps1 -Distro Ubuntu
```

Firewallを自分で管理したい場合のみ:

```powershell
.\scripts\smartphone\start.ps1 -SkipFirewall
```

## start.ps1が行うこと

1. WSL内のDocker / Docker Compose利用可否を確認
2. 前回異常終了時に残った同名FirewallルールとCompose stackを掃除
3. `cert-generator` をbuild
4. WSLユーザーのUID/GIDで `tmp/smartphone/` の検証用CAを準備し、LAN IP向けサーバー証明書を生成
5. Windows FirewallをLocalSubnet限定で一時開放
   - TCP 8000: CA証明書取得
   - TCP 8889: HTTPS WebRTC signaling / WHIP
   - UDP 8189: WebRTC media
6. MediaMTXとCA配信サーバーを起動
7. WindowsのLAN IP:8000/8889へTCP疎通を確認
8. iPhone/Androidから開くURLを表示
9. PowerShellが終了すると `finally` でCompose停止とFirewallルール削除

Firewallルール名は以下に固定し、次回起動時にも残骸を削除する。

```text
MediaMTX Smartphone Test TCP
MediaMTX Smartphone Test UDP
```

## iPhone初回設定

`start.ps1` が次のようなURLを表示する。

```text
CA取得URL          : http://<PC-LAN-IP>:8000/rootCA.pem
WebRTC publish URL : https://<PC-LAN-IP>:8889/live/iphone-001/publish
```

初回だけ次を行う。

1. SafariでCA取得URLを開き `rootCA.pem` を取得
2. 「設定」からダウンロード済みのCAプロファイルをインストール
3. 「設定」→「一般」→「情報」→「証明書信頼設定」で、そのCAを完全に信頼
4. WebRTC publish URLを開く
5. Basic認証ダイアログへ以下の検証用example credentialを入力
   - user: `poc-publisher`
   - password: `poc-publisher-pass`
6. カメラ・マイク利用を許可

CAを一度信頼すれば、同じ `tmp/smartphone/certs/ca` を使う限り次回の `start.ps1` でも再利用できる。サーバー証明書は `start.ps1` 実行時に、そのCAを使って現在のLAN IP向けに生成する。

## 配信確認

別ターミナルのWSLからControl APIを確認する。

```bash
bash scripts/poc/api.sh /v3/paths/list
bash scripts/poc/api.sh /v3/webrtcsessions/list
```

`live/iphone-001` のactive pathとWebRTC sessionが確認できればpublish成功。

視聴ページ:

```text
https://<PC-LAN-IP>:8889/live/iphone-001
```

viewer credential:

```text
user: poc-viewer
pass: poc-viewer-pass
```

RTSP readerから利用する場合は、WSL/PC上から次のpathを利用できる。

```text
rtsp://poc-viewer:poc-viewer-pass@localhost:8554/live/iphone-001
```

Control APIとmetricsはWindows hostのlocalhostだけに公開する。

```text
http://127.0.0.1:9997/
http://127.0.0.1:9998/metrics
```

## 終了

起動中のPowerShellでEnterまたは `Ctrl+C` を使ってスクリプトを終了する。

```text
PowerShell終了
  ↓
finally
  ↓
Docker Compose down
  ↓
Windows Firewall一時ルール削除
  ↓
証明書はtmp/smartphone/に保持
```

PC強制終了、PowerShellプロセスの強制Killなどでは `finally` が実行されない場合がある。その場合でも、次回 `start.ps1` は同名FirewallルールとCompose stackを先に掃除する。

明示的に停止だけ行う場合:

```powershell
.\scripts\smartphone\stop.ps1
```

## 完全削除

検証終了後、PC側のCA・証明書を含めて削除する。

```powershell
.\scripts\smartphone\cleanup.ps1
```

これにより以下を削除する。

- MediaMTX / cert-serverコンテナ
- 検証用Windows Firewallルール
- `tmp/smartphone/certs/`
- `tmp/smartphone/public/`
- `tmp/smartphone/generated/`

iPhoneにインストールしたCAプロファイルはiPhone側で手動削除する。

## セキュリティ上の注意

- `rootCA-key.pem` はCA秘密鍵であり、外部へ共有しない
- CA秘密鍵は `tmp/smartphone/certs/ca/` にのみ保存する
- `cert-server` がmountするのは `tmp/smartphone/public/` だけで、ここには `rootCA.pem` しかコピーしない
- Firewallは `RemoteAddress LocalSubnet` に限定する
- LAN公開するのは8000/TCP、8889/TCP、8189/UDPだけ
- RTSP、HLS、Control API、metricsはWindows hostの127.0.0.1にのみbindする
- `tmp/`、`*.pem`、`*.key`、`*.crt` はGit管理対象外
- このCAとexample credentialは短期のローカル検証専用で、本番利用しない

## トラブルシュート

### LAN IPの自動検出が違う

VPNや複数NICがある場合は `-LanIp` を指定する。

### start.ps1のTCP疎通確認で失敗する

- Docker Desktopを利用する場合は、Docker Desktopが起動し、対象WSL distroでWSL integrationが有効か確認する
- WSL内の独立Docker Engineを利用する場合は、WSLのnetworking modeとLANからWSLへの到達性を確認する
- Windows 11でmirrored networkingを使う場合は、WSL側のHyper-V firewall設定も確認する

### iPhoneからCA取得URLへ接続できない

- PCとスマートフォンが同じLAN/Wi-Fiにいるか確認
- ゲストWi-FiやAP isolationで端末間通信が禁止されていないか確認
- `Get-NetFirewallRule -DisplayName 'MediaMTX Smartphone Test*'` で一時ルールを確認
- Dockerで8000/TCPがpublishされているか確認

### HTTPSページは開くが映像が流れない

- 8189/UDPがFirewallで許可されているか確認
- `tmp/smartphone/generated/mediamtx.yml` の `webrtcAdditionalHosts` がPCのLAN IPか確認
- `docker compose -f examples/docker-compose.smartphone.yml logs mediamtx` を確認
- WSL内の独立Docker Engineの場合は、UDP 8189もLANから到達できるネットワーク構成か確認

### Firewallルールだけ残った

管理者PowerShellで以下を実行する。

```powershell
.\scripts\smartphone\stop.ps1
```

または次回 `start.ps1` を起動すれば、開始時に同名の古いルールを削除する。
