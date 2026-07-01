# MediaMTX 動的配信 PoC 検証手順

## 目的

Web アプリなどから MediaMTX に動的に配信が追加される構成について、ローカル環境で次の観点を確認する。

1. 任意 path への publish により active path が作成されること
2. `runOnReady` / `runOnNotReady` の発火タイミング
3. reader / forwarder 起動時に冒頭映像が欠ける可能性
4. HLS 視聴開始遅延と `hlsAlwaysRemux` の差分
5. Control API による session / connection の kick
6. kick 後に publisher が再接続するか
7. internal 認証で publish / read / api の権限境界が効くこと
8. 正規表現 path で `live/` 配下だけを検証対象にできること
9. Playwright と Chromium のテスト用 media device で WebRTC publish 経路を確認できること

このリポジトリは public 前提のため、実認証情報、実 IP、実ホスト名、実カメラ URL は記載しない。ここで使う ID / password はローカル検証用の example 値であり、本番・社内環境では使わない。

## 前提

ローカル PC で以下を使える状態にする。

- Docker / Docker Compose
- curl
- jq
- ffmpeg
- bash

GitHub Actions では、上記に加えて Node.js / Playwright / Chromium を使って WebRTC publish の自動確認を行う。

## 追加ファイル

| ファイル | 用途 |
|---|---|
| `examples/docker-compose.poc.yml` | PoC 用 MediaMTX 起動 |
| `examples/mediamtx.poc.yml` | PoC 用 MediaMTX 設定 |
| `.github/workflows/poc-scripts.yml` | PoC 補助スクリプトの CI 実行 |
| `scripts/poc/run-smoke.sh` | 最小動作確認をまとめて実行 |
| `scripts/poc/api.sh` | Control API 呼び出し補助 |
| `scripts/poc/publish-rtsp-testsrc.sh` | ffmpeg のテスト映像を RTSP publish |
| `scripts/poc/record-rtsp-head.sh` | RTSP reader として冒頭数秒を録画 |
| `scripts/poc/check-hls.sh` | HLS playlist 取得時間を確認 |
| `scripts/poc/check-webrtc-publish.mjs` | Playwright で WebRTC publish を確認 |
| `scripts/poc/kick-session.sh` | Control API で session / connection を kick |
| `scripts/poc/hooks/log-ready.sh` | `runOnReady` ログ出力 |
| `scripts/poc/hooks/log-not-ready.sh` | `runOnNotReady` ログ出力 |

## 0. 一括 smoke test

リポジトリ直下で実行する。

```bash
bash scripts/poc/run-smoke.sh
```

出力は `tmp/poc-output/` に保存される。`tmp/` は `.gitignore` で除外済みのため、録画ファイルや検証ログを誤って commit しにくい。

## 1. MediaMTX を起動する

個別に起動する場合は以下。

```bash
docker compose -f examples/docker-compose.poc.yml up -d
```

ログ確認。

```bash
docker compose -f examples/docker-compose.poc.yml logs -f mediamtx
```

停止。

```bash
docker compose -f examples/docker-compose.poc.yml down
```

## 2. active path 一覧を確認する

Control API は Docker Compose の port binding で `127.0.0.1:9997` にだけ公開する。

```bash
bash scripts/poc/api.sh /v3/paths/list
```

期待結果:

- 起動直後は検証中の path が存在しない
- publish 開始後に `live/...` path が出る
- publish 停止後に該当 path が消える、または source がなくなる

## 3. 任意 path に動的 publish する

ffmpeg の testsrc を使って、固定カメラなしで publish する。

```bash
bash scripts/poc/publish-rtsp-testsrc.sh live/poc-rtsp-001
```

別ターミナルで確認する。

```bash
bash scripts/poc/api.sh /v3/paths/list
```

期待結果:

- `live/poc-rtsp-001` が active path として表示される
- path の source が publisher 系の source になる
- `examples/mediamtx.poc.yml` の正規表現 path `~^live/.+$` にマッチする

## 4. `runOnReady` / `runOnNotReady` を確認する

publish 中に Docker logs を見る。

```bash
docker compose -f examples/docker-compose.poc.yml logs -f mediamtx
```

確認観点:

- publish 開始後に `runOnReady` のログが出る
- publish 停止後に `runOnNotReady` のログが出る
- publish コマンド開始時刻と `runOnReady` ログ時刻の差を見る
- `runOnReady` は配信開始前ではなく、stream が read 可能になった後に発火する前提で扱う

## 5. 冒頭数秒が downstream に入るか確認する

ターミナル A で publish する。

```bash
bash scripts/poc/publish-rtsp-testsrc.sh live/poc-head-001
```

ターミナル B で冒頭を録画する。

```bash
bash scripts/poc/record-rtsp-head.sh live/poc-head-001 8
```

出力先:

```text
tmp/poc-output/live_poc-head-001_head.mp4
```

確認観点:

- reader を publish 後に起動した場合、reader 接続前の live frame は録画されない
- `runOnReady` で FFmpeg forward を起動する設計では、FFmpeg 起動・接続前の冒頭が転送先に入らない可能性がある
- publisher 側の IDR interval / GOP 長が長いと、再生・録画の開始が遅く見える場合がある

## 6. HLS 視聴開始遅延を確認する

publish 中に HLS playlist の取得時間を見る。

```bash
bash scripts/poc/check-hls.sh live/poc-rtsp-001
```

比較手順:

1. `examples/mediamtx.poc.yml` の `hlsAlwaysRemux: false` で測定する
2. `hlsAlwaysRemux: true` に変更する
3. MediaMTX を再起動する
4. 同じ path / 同じ publisher 条件で再測定する

```bash
docker compose -f examples/docker-compose.poc.yml restart mediamtx
```

## 7. WebRTC publish をブラウザで確認する

MediaMTX の WebRTC publish ページを使う。

```text
http://localhost:8889/live/poc-webrtc-001/publish
```

ブラウザでカメラ利用を許可した後、別ターミナルで確認する。

```bash
bash scripts/poc/api.sh /v3/paths/list
bash scripts/poc/api.sh /v3/webrtcsessions/list
```

GitHub Actions では、実カメラの代わりに Chromium のテスト用 media device を使って WebRTC publish 経路を確認する。

```bash
npm install
npx playwright install chromium
npm run check:webrtc-publish
```

CI で確認するのは、MediaMTX の publish ページを開き、WebRTC session と active path が作成されることまでである。実デバイス選択、スマホブラウザの権限操作、実利用環境での到達性は別途確認する。

## 8. Control API で session / connection を kick する

WebRTC session の一覧を確認する。

```bash
bash scripts/poc/api.sh /v3/webrtcsessions/list
```

得られた `id` を指定して kick する。

```bash
bash scripts/poc/kick-session.sh webrtc <session-id>
```

RTSP の場合:

```bash
bash scripts/poc/api.sh /v3/rtspsessions/list
bash scripts/poc/kick-session.sh rtsp <session-id>
```

HLS の場合:

```bash
bash scripts/poc/api.sh /v3/hlssessions/list
bash scripts/poc/kick-session.sh hls <session-id>
```

期待結果:

- 対象 session / connection が切断される
- ブラウザや ffmpeg 側で切断が観測できる
- publisher 側が自動再接続する設定の場合、再度 session が作られる可能性がある

## 9. kick 後の再接続を確認する

確認観点:

- kick は現在の接続を切る操作であり、ユーザーを永久停止する操作ではない
- publisher が再接続する実装なら、同じ認証情報で再 publish できる可能性がある
- 本番で管理者停止を実現するには、kick と同時にアプリ側 DB / JWT 発行 / HTTP 認証で再接続を拒否する必要がある

## 10. 認証境界を確認する

PoC 設定では以下の example credential を使う。

| 種別 | user | pass | 権限 |
|---|---|---|---|
| publisher | `poc-publisher` | `poc-publisher-pass` | `live/` 配下へ publish |
| viewer | `poc-viewer` | `poc-viewer-pass` | `live/` 配下を read |
| api | anonymous from local access | なし | Control API |

確認例:

```bash
bash scripts/poc/publish-rtsp-testsrc.sh live/auth-ok-001
bash scripts/poc/publish-rtsp-testsrc.sh other/auth-ng-001
```

期待結果:

- `live/...` は publish できる
- `other/...` は publish できない
- Control API は `127.0.0.1:9997` にだけ bind され、外部公開しない

## 判定基準

- `live/...` に対する動的 publish が active path として確認できる
- `runOnReady` / `runOnNotReady` の発火タイミングをログで確認できる
- reader / forwarder 起動が publish 後になる場合、冒頭欠落の有無を観測できる
- HLS の初回遅延を測定できる
- WebRTC publish 経路で session と active path が確認できる
- Control API で session / connection を kick できる
- kick 後の再接続有無を確認できる
- internal 認証の path 制限が効く
- public repository に入れてはいけない secret・実 URL・検証ログを分離できている

## 次の設計判断

1. 冒頭欠落を許容するか
2. 許容しない場合、publisher 開始前に reader / forwarder を先に準備するか
3. 管理者停止は kick だけで足りるか、HTTP auth / JWT で再接続拒否まで行うか
4. HLS を使うか、WebRTC / RTSP / SRT を優先するか
5. ローカル検証で十分な項目と、別環境で確認が必要な項目を分けるか
