# スマートフォン実機からWebRTC publishする手順

## 目的

Windows + WSL2 上のMediaMTXへ、同一LAN内のスマートフォンブラウザから実カメラ映像をWebRTCでpublishする。

短期の検証用途に限定し、PCへmkcertやOpenSSLなどを追加インストールしない。証明書生成はDockerコンテナ内で行い、Windows Firewallの一時ルールも検証終了時に削除する。

通常の同一LANだけでなく、構築済みPCをインターネットから切断し、Windowsのモバイルホットスポットへスマートフォンを直接接続する完全オフライン構成でも検証できる。

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

インターネットから切断したモバイルホットスポット構成では、通信経路は次のようになる。

```text
Internet
   × 未接続

Windows PC
  ├─ WSL2 / Docker Desktop / MediaMTX
  └─ Windows Mobile Hotspot
              │ local Wi-Fi
              │
         Smartphone
              ├─ HTTPS :8889 signaling / WHIP
              └─ UDP   :8189 WebRTC media
```

WebRTCのシグナリングとメディア通信はPCとスマートフォンのローカル通信だけで成立する。外部STUN/TURNはこの検証構成では使用しない。

## PC側の前提

追加インストールは不要。以下が既に利用できること。

- Windows 10/11
- WSL2
- Docker Compose v2
- Windows PowerShell 5.1以降
- WSL内からDockerを利用できること

推奨構成はDocker DesktopのWSL 2 integrationである。Docker DesktopはpublishしたコンテナportをWindows host / local networkへ転送するため、この手順と相性がよい。

WSL内へ独立してDocker Engineをインストールしている場合は注意する。WSL2の既定ネットワークはNATであり、WindowsからWSLへのlocalhost forwardingと、LAN上の別端末からWSLへ直接到達できることは同義ではない。Windows 11でWSL mirrored networkingを利用するなど、LAN到達性を別途確保する必要がある場合がある。

`start.ps1` はMediaMTX起動後、Windows localhostの8000/TCPと8889/TCPを最大10回retryして必須の起動確認を行う。続けてWindows自身からLAN IPへの8000/TCPと8889/TCPも確認するが、WSLのnetworking modeによっては自己接続だけが失敗し、同一LANのスマートフォンからは到達できる場合があるため、この確認は警告扱いとする。最終的なLAN到達性はスマートフォンからCA取得URLとpublish URLを開いて確認する。

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

インターネット未接続でWindowsモバイルホットスポットだけが有効な場合、`start.ps1` はデフォルトゲートウェイのないホットスポット側プライベートIPv4もフォールバック検出する。候補が複数ある場合は誤選択を避けるため自動決定せず、候補を表示して `-LanIp` の指定を要求する。

WSLディストリビューションを明示する場合:

```powershell
.\scripts\smartphone\start.ps1 -Distro Ubuntu
```

Firewallを自分で管理したい場合のみ:

```powershell
.\scripts\smartphone\start.ps1 -SkipFirewall
```

## 完全オフラインのモバイルホットスポット構成

### 1. インターネット接続中にDockerイメージを事前準備

完全オフラインで実行する前に一度だけ、必要なDockerイメージを取得し、証明書生成用イメージをbuildする。

WSLのリポジトリ直下から実行する場合:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w scripts/smartphone/prepare-offline.ps1)"
```

Windows PowerShellから実行する場合:

```powershell
.\scripts\smartphone\prepare-offline.ps1
```

この処理は以下を事前にキャッシュする。

- `bluenviron/mediamtx:1`
- `busybox:1.36`
- `alpine:3.20` と `apk` / `mkcert` を含む `mediamtx-playground-smartphone-cert:local`

`prepare-offline.ps1` 実行後にDockerイメージを削除した場合は、再度インターネット接続中に実行する。

### 2. PCをインターネットから切断

有線LANや通常Wi-Fiなど、外部ネットワークへの接続を切断する。

### 3. Windowsのモバイルホットスポットを有効化

Windowsの「設定」からモバイルホットスポットを有効にし、表示されたSSIDへスマートフォンを接続する。

この状態ではPCにインターネット接続がなくてもよい。スマートフォンとPCがホットスポットのローカルネットワーク内で相互通信できればよい。

### 4. `start.ps1` を起動

```powershell
.\scripts\smartphone\start.ps1
```

ホットスポット側IPv4が一意に検出できれば、そのIPを証明書、WebRTC URL、MediaMTXのICE candidate用ホストとして使用する。

複数のプライベートNICなどにより自動判定できない場合は、Windowsで `ipconfig` または `Get-NetIPAddress -AddressFamily IPv4` を確認し、スマートフォンと同一サブネットのPC側IPv4を明示する。

```powershell
.\scripts\smartphone\start.ps1 -LanIp <hotspot側のPC IPv4>
```

### 5. スマートフォンからpublish

`start.ps1` が表示するQRコードまたはURLをスマートフォンで開き、CA信頼設定、Basic認証、カメラ権限を許可する。

この構成で測定されるネットワーク特性は「スマートフォンとPC間のローカルWi-Fi」であり、モバイル回線やWAN越しの遅延は含まない。機能確認や基礎性能測定と、本番WAN条件の測定は分けて扱う。

## start.ps1が行うこと

1. WSL内のDocker / Docker Compose利用可否を確認
2. 前回異常終了時に残った同名FirewallルールとCompose stackを掃除
3. WSL通常ユーザーで `tmp/smartphone/` を準備し、root所有・書込不可のパスが残っていないことを確認してから `cert-generator` をbuild
4. WSLユーザーのUID/GIDで検証用CAを準備し、LAN IP向けサーバー証明書を生成
5. Windows FirewallをLocalSubnet限定で一時開放
   - TCP 8000: CA証明書取得
   - TCP 8889: HTTPS WebRTC signaling / WHIP
   - UDP 8189: WebRTC media
6. MediaMTXとCA配信サーバーを起動
7. Windows localhost:8000/8889をretry付きで必須確認し、LAN IP:8000/8889への自己疎通は警告用に確認
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
- モバイルホットスポット使用時も、検証用SSID/パスワードを不用意に共有せず、検証終了後はホットスポットを無効化する

## トラブルシュート

詳細な起動時トラブルは [スマートフォンWebRTC起動トラブルシュート](smartphone-webrtc-troubleshooting.md) も参照する。

### `tmp/smartphone` がroot所有になっている

正規の `start.ps1` はWSLの通常ユーザーでworkspaceを作成し、そのUID/GIDで証明書生成コンテナを実行する。現在はCompose側も `create_host_path: false` とし、bind元がない状態でDockerが `tmp/smartphone` 配下を自動作成しない。

過去の直接 `docker compose up/run` や `sudo docker compose ...` 等でroot所有パスが残っている場合、`start.ps1` は証明書生成前に検出して停止する。次で所有者を戻して再実行する。

```bash
sudo chown -R "$(id -u):$(id -g)" tmp/smartphone
```

### LAN IPの自動検出が違う

VPNや複数NICがある場合は `-LanIp` を指定する。

インターネット未接続のホットスポット構成では、ホットスポット側NICまたは一意なプライベートIPv4へフォールバックする。複数候補が表示された場合は、スマートフォンと同一サブネットのIPv4を `-LanIp` で指定する。

### オフラインでDocker image取得エラーになる

インターネット接続中に `prepare-offline.ps1` を実行していない、または準備後にDockerイメージを削除した可能性がある。PCを再度オンラインにして `prepare-offline.ps1` を実行する。

### LAN IPへのTCP自己疎通で警告になる

`start.ps1` は `127.0.0.1:8000` と `127.0.0.1:8889` を必須の起動確認に使う。Windows自身からPCのLAN IPへの8000/8889が失敗した場合は警告を表示するが、この結果だけでは停止しない。

- Docker Desktopを利用する場合は、Docker Desktopが起動し、対象WSL distroでWSL integrationが有効か確認する
- WSL内の独立Docker Engineを利用する場合は、WSLのnetworking modeとLANからWSLへの到達性を確認する
- Windows 11でmirrored networkingを使う場合は、WSL側のHyper-V firewall設定も確認する
- モバイルホットスポット構成では `-LanIp` がスマートフォンと同一サブネットのPC側IPv4か確認する
- 最終判断はスマートフォンから `http://<PC-LAN-IP>:8000/rootCA.pem` と `https://<PC-LAN-IP>:8889/live/iphone-001/publish` を開いて行う

### iPhoneからCA取得URLへ接続できない

- PCとスマートフォンが同じLAN/Wi-FiまたはWindowsモバイルホットスポットにいるか確認
- ゲストWi-FiやAP isolationで端末間通信が禁止されていないか確認
- `Get-NetFirewallRule -DisplayName 'MediaMTX Smartphone Test*'` で一時ルールを確認
- Dockerで8000/TCPがpublishされているか確認

### HTTPSページは開くが映像が流れない

- 8189/UDPがFirewallで許可されているか確認
- `tmp/smartphone/generated/mediamtx.yml` の `webrtcAdditionalHosts` がPCのLAN IPまたはホットスポット側IPか確認
- `docker compose -f examples/docker-compose.smartphone.yml logs mediamtx` を確認
- WSL内の独立Docker Engineの場合は、UDP 8189もLANから到達できるネットワーク構成か確認

### Firewallルールだけ残った

管理者PowerShellで以下を実行する。

```powershell
.\scripts\smartphone\stop.ps1
```

または次回 `start.ps1` を起動すれば、開始時に同名の古いルールを削除する。
