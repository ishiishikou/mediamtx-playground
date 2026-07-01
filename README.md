# mediamtx-playground

MediaMTX を実際に動かしながら、WebRTC / RTSP / RTMP / HLS / Triton 連携を調査するための playground リポジトリです。

このリポジトリは本番環境ではなく、検証手順・設定例・実験メモを蓄積するための作業場所です。

## 目的

- MediaMTX の基本動作を Docker Compose で再現する
- RTSP / RTMP / HLS / WebRTC の入出力経路を確認する
- WebRTC から推論基盤へつなぐ構成を整理する
- 将来の PoC や構成説明に使える検証メモを残す
- public repository として公開しても安全な形で設定例を管理する

## 初回セットアップ

```bash
cp .env.example .env
cd compose
docker compose up -d
```

起動確認:

```bash
../scripts/check_api.sh
```

テスト映像を RTSP で publish する例:

```bash
../scripts/publish_testsrc_rtsp.sh
```

主な確認 URL:

- RTSP: `rtsp://localhost:8554/test`
- HLS: `http://localhost:8888/test/index.m3u8`
- WebRTC: `http://localhost:8889/test`
- Control API: `http://localhost:9997/v3/config/global/get`
- Metrics: `http://localhost:9998/metrics`

## 動的配信 PoC 検証

Web アプリなどから MediaMTX に動的に配信が追加される構成について、active path、hook、HLS 遅延、Control API kick、認証境界を確認するための手順を追加しています。

- [MediaMTX 動的配信 PoC 検証手順](docs/poc-verification.md)

最小動作確認は以下で実行します。

```bash
bash scripts/poc/run-smoke.sh
```

## 負荷試験

MediaMTX が複数の動画 publisher を同時に受信したときの安定性を確認するための負荷試験手順を追加しています。

推奨は、ホストに FFmpeg / GStreamer / Python 依存を入れず、`load-runner` コンテナで実行する方法です。

- [MediaMTX 負荷試験手順](docs/load-test.md)
- [MediaMTX 負荷試験のコンテナ運用](docs/container-load-test.md)

コンテナ実行の最小例:

```bash
docker compose -f examples/docker-compose.load.yml build load-runner
docker compose -f examples/docker-compose.load.yml up -d mediamtx
docker compose -f examples/docker-compose.load.yml run --rm load-runner
docker compose -f examples/docker-compose.load.yml down -v
```

## ディレクトリ構成

```text
.
├── configs/                         # MediaMTX の公開用 example 設定
├── compose/                         # Docker Compose 検証環境
├── docker/                          # 検証用コンテナイメージ
├── docs/                            # 調査メモ
├── examples/                        # PoC 用 Compose / MediaMTX 設定
├── scripts/                         # ローカル・コンテナ検証用スクリプト
├── .env.example                     # 公開可能な環境変数サンプル
├── .gitignore                       # 秘密情報・録画・ログ除外
├── SECURITY.md                      # public 運用時の注意
└── README.md
```

## public 運用方針

このリポジトリには、以下を含めません。

- 実カメラの RTSP URL
- 実環境の IP アドレス、ホスト名、認証情報
- TURN / STUN / Basic 認証 / API token / secret
- 秘密鍵、証明書、Provisioning profile
- 録画映像、キャプチャ画像、検証ログ

実値は `.env` または `*.local.yml` に分離し、公開する設定は `*.example.yml` として管理します。

## 推奨ワークフロー

1. `main` から作業ブランチを作成する
2. 検証単位ごとに PR を作成する
3. PR 上で設定・手順・ログの公開可否を確認する
4. 問題なければ squash merge する

## License

MIT License. See [LICENSE](LICENSE).
