# 04_triton_integration_notes

## 目的

MediaMTX から取得した映像を Triton Inference Server などの推論基盤へ渡す構成を整理する。

このリポジトリでは、まず MediaMTX 側の配信経路と取得方法を安定させる。Triton 連携は、検証対象が明確になってから別ディレクトリまたは別リポジトリに分離するか判断する。

## 想定構成

```text
Camera / Browser / ffmpeg
        ↓
     MediaMTX
        ↓
 RTSP / WebRTC / HLS read
        ↓
 frame extraction
        ↓
 Triton gRPC / HTTP
        ↓
 inference result
```

## 確認観点

- MediaMTX から何の protocol で取り出すか
- フレーム抽出をどこで行うか
- 推論 FPS を何にするか
- 入力映像 FPS と推論 FPS を分離するか
- 推論結果をどこへ返すか
- WebRTC connection disconnected などの切断をどう検知するか

## 保留事項

- Triton の model repository はこのリポジトリに含めない
- GPU 環境依存の設定は public example と local config に分離する
- 実映像・推論ログは commit しない
