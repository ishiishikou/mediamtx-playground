# 00_overview

## このリポジトリの位置づけ

`mediamtx-playground` は、MediaMTX を中心にリアルタイム映像配信の経路を実際に動かしながら確認するための検証用リポジトリです。

本番サービスの実装ではなく、次のような作業を安全に記録することを目的とします。

- Docker Compose による MediaMTX 起動
- RTSP publish / read の確認
- HLS / WebRTC の閲覧確認
- Control API / metrics の確認
- Triton など外部推論基盤との接続方針の整理

## 設計方針

- public repository として公開できる内容だけを置く
- 実値は `.env` または `*.local.yml` に分離する
- 設定ファイルは `*.example.yml` を基本にする
- 検証結果は再現手順と観察結果を分けて記録する
- 録画・画像・ログは原則 commit しない

## まず見るファイル

1. `README.md`
2. `SECURITY.md`
3. `configs/mediamtx.example.yml`
4. `compose/docker-compose.yml`
5. `docs/01_mediamtx_basics.md`
