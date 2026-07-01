# 一回限りの動画 artifact 確認

このブランチでは、GitHub Actions 上で WebRTC publish のテスト映像を約1分録画し、artifact としてダウンロードできるかを確認する。

## 方針

- 通常の CI では動画 artifact を保存しない
- この確認用 workflow は一回限りで使う
- 確認後、`.github/workflows/poc-video-artifact-once.yml` は削除する
- artifact retention は 1 日にする

## 生成物

- `poc-webrtc-fake-camera-recording`
  - `*.mp4`
  - `*.log`

動画は検証用の合成 media device 由来であり、実カメラ映像ではない。
