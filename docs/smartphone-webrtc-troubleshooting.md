# スマートフォンWebRTC起動トラブルシュート

## `tmp/smartphone` が root 所有になる場合

通常の `scripts/smartphone/start.ps1` 経路では、WSLの通常ユーザーで `tmp/smartphone/` を作成し、そのUID/GIDを `cert-generator` コンテナへ渡す。そのため、正規ルートで生成されるCA、サーバー証明書、MediaMTX設定は通常ユーザー所有になる。

一方、過去の短縮形式bind mountでは、bind元が存在しない状態で `docker compose up` / `docker compose run` を直接実行すると、Dockerがbind元を作成し、root所有のディレクトリやパスが残る可能性があった。`sudo docker compose ...` を使った実験でも同様の状態を作り得る。

現在のスマートフォン用Composeでは、`tmp/smartphone` 配下のbind mountに `create_host_path: false` を指定する。必要なパスがない場合はDockerに作らせず、`start.ps1` がWSLユーザーで事前作成する。

`start.ps1` は起動前に `scripts/smartphone/ensure-workspace.sh` を実行し、次を検査する。

- WSLの実行ユーザーがrootではないこと
- `tmp/smartphone` 自体がroot所有ではないこと
- 配下にroot所有のファイル/ディレクトリが残っていないこと
- CA、public、generatedディレクトリへ現在ユーザーが書き込めること

既存のroot所有パスを検出した場合は自動で所有権を変更せず、次のような修復コマンドを表示して停止する。

```bash
sudo chown -R "$(id -u):$(id -g)" tmp/smartphone
```

所有権変更後に `start.ps1` を再実行する。

## `start.ps1` が `[7/7]` で自動停止する問題

以前の `start.ps1` は、MediaMTX起動後にWindows自身からPCのLAN IPへ `8000/TCP` と `8889/TCP` の接続を試し、どちらかが失敗すると例外終了していた。

ただしWSLのネットワーク構成によっては、次のような状態が成立する。

```text
Windows -> 127.0.0.1:8889       成功
Windows -> 自分のLAN IP:8889    失敗
スマートフォン -> LAN IP:8889   成功
```

この場合、Windows自身からLAN IPへの自己接続失敗だけを理由にスマートフォン検証環境を停止するのは誤判定になる。

現在の `start.ps1` は次の判定に変更する。

1. `127.0.0.1:8000` と `127.0.0.1:8889` は最大10回retryし、起動確認の必須条件とする
2. Windows自身からLAN IPの `8000/8889` へも確認する
3. LAN IPへの自己接続が失敗した場合は警告を表示するが、コンテナとFirewallを停止しない
4. 最終的なLAN到達性は、表示されたCA取得URLとpublish URLをスマートフォンから開いて確認する

スマートフォンで次の両方へ到達できれば、LAN公開は機能している。

```text
http://<PC-LAN-IP>:8000/rootCA.pem
https://<PC-LAN-IP>:8889/live/iphone-001/publish
```

publish URLでは公開用PoC credentialを使用する。

```text
user: poc-publisher
password: poc-publisher-pass
```

## 手動確認

MediaMTXがローカルで起動しているか確認する。

```bash
docker ps --filter name=mediamtx-smartphone
curl -k -I https://127.0.0.1:8889/
```

MediaMTXの `/` はページを持たないため、HTTPSで `404 Not Found` が返ること自体は疎通成功として扱える。

Windows側のlocalhost確認:

```powershell
Test-NetConnection 127.0.0.1 -Port 8000
Test-NetConnection 127.0.0.1 -Port 8889
```

LAN IPへの自己接続が失敗しても、それだけではスマートフォンからの到達不能とは判断しない。スマートフォン実機でCA取得URLとpublish URLを確認する。
