# 03_rtsp_check

## 目的

MediaMTX の RTSP 入出力を確認し、後続の推論処理に渡す前提を整理する。

## テスト publish

```bash
../scripts/publish_testsrc_rtsp.sh
```

## VLC / ffprobe での確認例

```bash
ffprobe rtsp://localhost:8554/test
```

## 確認観点

- publish が維持されるか
- read 開始時に遅延がどの程度あるか
- transport を TCP に固定した場合の安定性
- FPS / 解像度変更時の挙動
- 複数 reader 接続時の挙動

## 記録テンプレート

| 日付 | publish 方法 | read 方法 | 解像度 | FPS | 結果 | メモ |
| --- | --- | --- | --- | --- | --- | --- |
|  | ffmpeg testsrc | ffprobe | 1280x720 | 30 |  |  |

## 禁止事項

実カメラの `rtsp://user:password@host/path` は commit しない。必要な場合は `.env` または `mediamtx.local.yml` に置く。
