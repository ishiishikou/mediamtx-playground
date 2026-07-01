# PoC scripts GitHub Actions 検証

## 目的

`docs/poc-verification.md` で追加した PoC 補助スクリプトが、GitHub Actions 上で最低限実行できることを確認する。

## 対象

GitHub Actions workflow は `.github/workflows/poc-scripts.yml` に定義する。

確認対象は以下。

- `scripts/poc/*.sh` の bash 構文チェック
- `scripts/poc/hooks/*.sh` の sh 構文チェック
- `scripts/poc/check-webrtc-publish.mjs` の Node.js 構文チェック
- `examples/docker-compose.poc.yml` の Docker Compose 構成チェック
- `scripts/poc/run-smoke.sh` による MediaMTX 起動、RTSP publish、RTSP reader 録画、HLS playlist 取得、Control API 確認
- Playwright + Chromium のテスト用 media device による WebRTC publish 確認

## CI で確認しない範囲

GitHub Actions では、実ブラウザ・実入力デバイス・実ネットワーク環境に依存する確認は対象外とする。

対象外の例:

- 実入力デバイスの選択
- スマホブラウザでの権限確認
- 社内ネットワークや実利用環境での到達性
- 外部ネットワーク条件を含む接続性
- 本番相当の HTTPS 構成

これらはローカル PC または別の実環境で確認する。
