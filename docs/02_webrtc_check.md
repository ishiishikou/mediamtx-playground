# 02_webrtc_check

## 目的

MediaMTX の WebRTC 出力をブラウザから確認し、ローカル PC / スマートフォン / LAN 環境での挙動差を整理する。

## 基本確認

1. MediaMTX を起動する
2. `scripts/publish_testsrc_rtsp.sh` で `test` path に映像を publish する
3. ブラウザで `http://localhost:8889/test` を開く
4. 再生可否、遅延、切断タイミングを記録する

## 確認観点

- localhost で再生できるか
- LAN 内のスマートフォンから再生できるか
- HTTPS が必要になる条件は何か
- ICE candidate が期待通り出ているか
- UDP 8189 が到達できない場合にどう失敗するか
- TURN / STUN が必要になる境界はどこか

## 記録テンプレート

| 日付 | 端末 | 接続元 | URL | 結果 | メモ |
| --- | --- | --- | --- | --- | --- |
|  | PC | localhost |  |  |  |
|  | iPhone | LAN |  |  |  |

## public repository 注意

WebRTC 検証では、接続元 IP、グローバル IP、LAN IP、TURN 認証情報がログやスクリーンショットに入りやすい。公開前に必ず除去する。
