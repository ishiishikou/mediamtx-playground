# PoC scripts GitHub Actions 検証

## 目的

`docs/poc-verification.md` で追加した PoC 補助スクリプトが、GitHub Actions 上で最低限実行できることを確認する。

## 対象

GitHub Actions workflow は `.github/workflows/poc-scripts.yml` に定義する。

確認対象は以下。

- `scripts/poc/*.sh` の bash 構文チェック
- `scripts/poc/hooks/*.sh` の sh 構文チェック
- `examples/docker-compose.poc.yml` の Docker Compose 構成チェック
- `scripts/poc/run-smoke.sh` による以下の一括確認
  - MediaMTX コンテナ起動
  - Control API の `/v3/paths/list` 呼び出し
  - ffmpeg testsrc の RTSP publish
  - RTSP reader 録画
  - HLS playlist 取得
  - publish 停止後の path 確認

## 注意

GitHub Actions ではブラウザカメラを使う WebRTC publish の完全な手動確認までは行わない。

WebRTC publish 画面、管理者画面、AWS 上の HTTPS / STUN / TURN / Security Group は、別途実環境で確認する。
