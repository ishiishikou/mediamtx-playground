# 01_mediamtx_basics

## 確認したいこと

- MediaMTX が Docker Compose で起動すること
- RTSP で publish できること
- RTSP / HLS / WebRTC で read できること
- Control API が参照できること
- Prometheus metrics が取得できること

## 起動

```bash
cp .env.example .env
cd compose
docker compose up -d
```

## 状態確認

```bash
docker compose ps
docker compose logs -f mediamtx
../scripts/check_api.sh
```

## テスト映像 publish

```bash
../scripts/publish_testsrc_rtsp.sh
```

## 観察メモ欄

| 日付 | 目的 | 結果 | メモ |
| --- | --- | --- | --- |
|  |  |  |  |

## 注意

実カメラ URL、認証情報、接続元 IP、録画ファイルは記録しない。
