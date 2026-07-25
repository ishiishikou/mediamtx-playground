# WebRTC映像推論システム 性能測定計画

## 前提と要確認事項

本計画は、3週間で測定結果を取得することを優先し、以下を暫定前提とする。

| 項目 | 暫定前提 | 要確認事項 |
|---|---|---|
| 配信サーバ | MediaMTXを使用し、WebRTCはWHIP、比較系はRTSP publishを使用する | 実環境のMediaMTX URL、認証方式、ICE/TURN構成 |
| 推論サーバ | 同一モデル、同一前処理、同一GPU条件でWebRTC系とRTSP系を処理する | 推論ログに時刻・フレーム識別子を追加できるか |
| 結果表示 | ブラウザ上の結果描画時に計測イベントを発火できる | 実アプリに本書の計測フックを追加できるか |
| 入力動画 | 640x360、15fps、30秒の短い固定動画を既定とする | 本番相当の代表動画1～2本への差し替え |
| 同時接続数 | 1、3、6クライアントを仮置きする | 通常想定数とWSL側のCPU・メモリ上限 |
| 時刻同期 | クライアント、配信、推論サーバをNTP/chronyで同期する | 各ホストの時刻同期状態と許容誤差 |

不明点が残っていても、準備1週目はローカルMediaMTXに対する1クライアント配信とログ保存を先行して完成させる。

---

## 1. エグゼクティブサマリー

### 何を測定するか

スマートフォンまたはWSL上のChromiumからWebRTCで映像を配信し、配信サーバ、推論サーバ、AI推論、結果返却、ブラウザ描画までの性能を測定する。主な測定対象は以下である。

- エンドツーエンド遅延の中央値、p95、最小、最大、サンプル数
- 入力・推論・出力FPS、推論処理時間、結果返却時間
- CPU、メモリ、GPU、GPUメモリ、ネットワークの取得可能な範囲
- 接続成功率、切断、再接続、ブラウザエラー、推論エラー
- 同一動画をWebRTCとRTSPで配信した場合の推論結果の相対差

### 何を測定しないか

- mAPなどを用いた正式な推論精度評価
- 全フレームへの人手アノテーション
- 最大同時接続数の完全な特定
- 24時間以上の連続試験
- モバイル回線、端末機種、OS、ブラウザの網羅的な組み合わせ試験
- 新規の大規模監視製品、商用負荷試験製品の導入

### 3週間で得られる成果

- 1つの設定ファイルからWebRTC/RTSPの必須シナリオを実行できる自動測定系
- 同一動画を使用した再現可能な比較結果
- シナリオごとの成功率、ブラウザ送信FPS、遅延統計、リソースログ
- WebRTC/RTSPの検出件数、クラス別件数、平均信頼度、フレーム一致率の比較表
- 実スマートフォンによる最終的なE2E遅延・表示・接続確認
- 再測定可能な設定、コマンド、ログ形式、集計スクリプト

### この測定結果から判断できること

- WebRTC採用時に、RTSP比較系より遅延、FPS、検出結果差が許容範囲か
- 通常想定の少数クライアントで処理性能が大きく劣化しないか
- 配信、推論、結果返却、描画のどの区間が支配的か
- 中程度負荷で性能劣化が急増する兆候があるか
- 実機ブラウザで自動測定系と同じ傾向が得られるか

### この測定結果だけでは判断できないこと

- 大規模本番環境での最大収容数
- モデル自体の絶対的な認識精度
- あらゆるネットワーク品質、端末機種、照明条件での性能
- 長期間運用時のメモリリークや断続的障害
- WSL上の疑似クライアント結果を、そのままスマートフォンCPU・カメラ性能へ適用できるか

---

## 2. 測定目的と評価観点

評価観点は以下の5点に絞る。

| 評価観点 | 主な指標 | 設計判断との関係 |
|---|---|---|
| E2E応答性 | E2E遅延中央値・p95・最大、結果返却時間、描画時間 | 利用者が結果をリアルタイムと感じられるか。遅延対策を配信、推論、UIのどこに入れるべきかを判断する |
| 処理量と劣化傾向 | 入力FPS、推論FPS、出力FPS、ドロップ、推論待ち時間 | 通常想定および中程度クライアント数で処理が追従するか。GPU台数やキュー設計の見直し要否を判断する |
| 安定性 | 接続成功率、切断、再接続、エラー数、2時間時の変化 | WebRTC接続・推論処理・ブラウザ表示を継続運用できるか。再接続や監視の追加要否を判断する |
| リソース効率 | CPU、メモリ、GPU、GPUメモリ、ネットワーク | ボトルネックがクライアント生成側、MediaMTX、推論サーバのどこかを切り分け、構成変更の根拠にする |
| WebRTC/RTSP相対差 | 検出件数、クラス別件数、平均信頼度、フレーム一致率、FPS・遅延差 | WebRTC経路による圧縮、フレーム欠落、タイミング差が推論結果へ与える影響を把握する。優劣を断定せず差の大きさを判断する |

---

## 3. スコープ

### 必須スコープ

- 固定動画1本を使用したWebRTC 1クライアント測定
- 同一動画を使用したRTSP 1クライアント比較
- 通常想定の3クライアントでのWebRTC/RTSP比較
- 中程度の6クライアントでの劣化傾向比較
- E2E遅延の簡易測定またはアプリ計測フックによる詳細測定
- ブラウザ送信FPS、推論ログ、結果返却・描画時刻の収集
- MediaMTX metrics、OS情報、取得可能なGPU情報の収集
- 推論結果JSONLのWebRTC/RTSP相対比較
- 実スマートフォン1台による最終確認3回
- CSV/JSON集計と基本グラフ生成

### 時間があれば実施する追加スコープ

- 3クライアントで最大2時間の継続試験
- 代表動画を2本に増やす
- ネットワーク帯域・遅延を軽く制御した補助測定
- フレーム対応付け許容幅を25/50/100msで変えた感度確認
- スマートフォン機種またはブラウザを1種類追加

### 今回は実施しないスコープ

- 最大負荷まで段階的に増やす限界負荷試験
- 24時間以上の連続試験
- 正解ラベル作成、mAP、Precision/Recallの正式評価
- 全フレームの目視確認
- 多数の端末・OS・回線条件の組み合わせ
- 新規の分散負荷試験基盤、商用APM、専用計測製品の導入

---

## 4. 測定シナリオ

クライアント数1/3/6は仮値であり、`configs/performance/scenarios.example.json`で変更する。

| ID | 目的 | 配信方式 | 入力動画 | クライアント数 | 実行時間 | 繰り返し | 取得メトリクス | 合否判定・比較方法 | 自動化 | 優先度 |
|---|---|---|---|---:|---:|---:|---|---|---|---|
| P01_WEBRTC_1 | WebRTC基準値 | WebRTC/WHIP | 固定動画A | 1 | 5分 | 3 | E2E遅延、送信FPS、推論時間、結果返却、エラー、リソース | 3回とも接続成功。中央値・p95を基準値化 | 可 | 必須 |
| P02_RTSP_1 | RTSP比較基準値 | RTSP/TCP | P01と同一 | 1 | 5分 | 3 | 入力/推論FPS、推論時間、検出結果、リソース | P01との差を算出。絶対精度の合否は設けない | 可 | 必須 |
| P03_WEBRTC_NORMAL | 通常負荷確認 | WebRTC/WHIP | 固定動画A | 3 | 10分 | 3 | P01項目＋成功率、切断、FPS低下 | 全クライアント接続。P01比でp95遅延・FPSの劣化量を確認 | 可 | 必須 |
| P04_RTSP_NORMAL | 通常負荷の比較 | RTSP/TCP | P03と同一 | 3 | 10分 | 3 | P02項目＋成功率 | P03と検出件数・クラス・信頼度・FPSを比較 | 可 | 必須 |
| P05_WEBRTC_MEDIUM | 中程度負荷の劣化傾向 | WebRTC/WHIP | 固定動画A | 6 | 10分 | 2 | 接続成功率、p95遅延、送信/推論FPS、CPU/GPU | 急激な遅延増加、継続的FPS低下、切断有無を確認 | 可 | 必須 |
| P06_RTSP_MEDIUM | 中程度負荷の相対比較 | RTSP/TCP | P05と同一 | 6 | 10分 | 2 | P05相当 | P05との差を比較し、配信方式固有の影響を切り分ける | 可 | 必須 |
| P07_WEBRTC_STABILITY | 数時間以内の安定性 | WebRTC/WHIP | 固定動画A | 3 | 2時間 | 1 | 切断、再接続、遅延時系列、メモリ/GPUメモリ | 前半・後半で明確な右肩上がりがないか | 可 | 追加 |
| P08_SMARTPHONE_FINAL | 実利用に近い最終確認 | 実機WebRTC | 実カメラまたは固定対象 | 1 | 5分 | 3 | E2E遅延、表示、操作、切断、ブラウザエラー | 3回の結果と自動系の傾向が矛盾しないこと | 一部手動 | 必須 |

数値の絶対合否閾値が未確定の場合、準備2週目終了時にP01/P02の予備測定結果を基準として、許容差を承認する。例として、通常負荷時のp95遅延が1クライアント時の2倍未満、接続成功率100%、入力FPS低下20%未満などを暫定候補とする。

---

## 5. 測定方式

### 5.1 エンドツーエンド遅延

#### 推奨方式

映像フレームに対応する`frame_id`または`source_ts_ms`を推論結果まで伝搬し、ブラウザ描画時刻との差を計算する。

```text
E2E latency = browser_render_ts_ms - source_ts_ms
```

ブラウザ側は結果受信時と次の`requestAnimationFrame`実行時を記録する。実装済みのPlaywright harnessは以下のイベントを監視する。

```javascript
window.dispatchEvent(new CustomEvent('perf:inference-result', {
  detail: {
    frame_id: '00012345',
    source_ts_ms: 1780000000000,
    server_receive_ts_ms: 1780000000120,
    inference_start_ts_ms: 1780000000130,
    inference_end_ts_ms: 1780000000165,
    result_send_ts_ms: 1780000000170,
    detections: [
      { class: 'person', confidence: 0.91, bbox: [10, 20, 100, 180] }
    ]
  }
}));
```

Playwright側が以下を追加する。

- `browser_receive_ts_ms`
- `browser_render_ts_ms`

#### 最小構成への簡略化

全区間の改修が難しい場合は、以下の順で簡略化する。

1. `source_ts_ms`と`browser_render_ts_ms`のみでE2E遅延を測定
2. `inference_start_ts_ms`、`inference_end_ts_ms`で推論時間を測定
3. `result_send_ts_ms`と`browser_receive_ts_ms`で結果返却時間を測定
4. `frame_id`が取れない場合、映像内の周期マーカーと時刻近傍で対応付ける
5. それも難しい場合、イベント発生を目視・画面録画で10サンプルだけ補完する

### 5.2 サーバ内処理時間

推論アプリの構造化ログに以下を1行JSONで記録する。

- `scenario_id`
- `client_id`または`stream_path`
- `frame_id`
- `source_ts_ms`
- `server_receive_ts_ms`
- `inference_start_ts_ms`
- `inference_end_ts_ms`
- `result_send_ts_ms`
- `detections`
- `error_code`

計算式は以下とする。

```text
queue time       = inference_start_ts_ms - server_receive_ts_ms
inference time   = inference_end_ts_ms - inference_start_ts_ms
result send time = browser_receive_ts_ms - result_send_ts_ms
```

アプリ改修が難しい場合、既存ログの受信時刻、推論時間、結果送信時刻だけを正規表現またはPythonでCSV化する。

### 5.3 ブラウザ受信・描画時刻

- Playwrightの`addInitScript`で計測リスナーをページ読み込み前に登録する
- 結果イベント受信時にepochミリ秒を取得する
- 次の`requestAnimationFrame`内で描画時刻を取得する
- ページエラー、コンソールエラー、クラッシュをJSONLへ保存する
- WebRTCの`RTCPeerConnection.getStats()`を5秒間隔で収集する

実アプリを使用する場合、アプリは以下の開始フックを公開する。

```javascript
window.__PERF_START_PUBLISH = async ({ clientId, streamPath, scenarioId }) => {
  // 既存の配信開始処理を呼び出す。
  // RTCPeerConnectionをwindow.__perfPeerConnectionsへ追加するとgetStats取得が可能。
};
```

### 5.4 WebRTCとRTSPの比較

推論結果を以下のJSONL形式へそろえ、`compare-results.py`で比較する。

```json
{"frame_id":"00012345","source_ts_ms":1780000000000,"detections":[{"class":"person","confidence":0.91,"bbox":[10,20,100,180]}]}
```

対応付けは以下の順で行う。

1. `frame_id`完全一致
2. `source_ts_ms`の最近傍一致。既定許容幅50ms
3. 対応できない場合はWebRTCのみ、RTSPのみとして集計

比較項目:

- 総検出件数
- クラスごとの検出件数
- 平均信頼度
- クラス別検出数が一致したフレーム割合
- WebRTCのみ、RTSPのみのフレーム数
- 入力・推論FPS差
- E2E遅延差

これは正解率ではなく、配信方式間の相対差である。

### 5.5 同一動画の利用

- FFmpegで入力動画を固定解像度・固定FPS・固定GOPへ正規化する
- WebRTC疑似カメラ用にY4Mを生成する
- RTSP用に同じ内容のH.264 MP4を生成する
- 0.5秒ごとに点灯・消灯する白い矩形を埋め込み、イベントの目視確認にも使う
- 可能な環境ではフレーム番号とPTSを映像へ焼き込む

ChromiumのY4M疑似カメラはファイルサイズが大きいため、既定は640x360、15fps、30秒とする。比較条件を上げる場合も、準備2週目開始までに確定する。

### 5.6 動画内時刻・フレームID

優先順位は以下。

1. 推論パイプライン内の連番を`frame_id`として結果まで伝搬
2. 入力時のepoch時刻を`source_ts_ms`として伝搬
3. 映像へフレーム番号・PTSを焼き込み、問題発生時の目視確認に使用
4. 周期マーカーの変化点でおおまかな対応を確認
5. 正確な対応が困難な場合、一定間隔サンプリングへ変更

QRコードやArUcoを毎フレーム生成する方式は、追加実装とデコード負荷が大きいため今回の必須方式にはしない。

### 5.7 時刻同期

- Linuxサーバは`timedatectl`または`chronyc tracking`で同期状態を確認する
- WSLは測定前にWindows時刻と大きな差がないことを確認する
- スマートフォンはOSの自動時刻設定を有効にする
- 測定開始前後に各ホストのepochミリ秒をログへ残す
- 50ms以上のずれが見つかった場合、区間別時刻の比較を中止し、同一ホスト内の差分またはフレームID比較を優先する

### 5.8 ログ相関

全ログに以下を含める。

```text
run_id / case_id / scenario_id / repeat / client_id / stream_path / frame_id
```

ファイル名だけでなく、各レコードにも識別子を保持する。

### 5.9 保存形式

| 種別 | 形式 | 用途 |
|---|---|---|
| ケース定義 | JSON | 再実行条件、開始終了、成功失敗 |
| ブラウザイベント | JSONL | 接続、コンソール、ページエラー、クラッシュ |
| WebRTC stats | CSV | FPS、フレーム、パケット、バイト、encode時間 |
| 推論結果 | JSONLまたはCSV | WebRTC/RTSP相対比較 |
| リソース | CSV、Prometheus text | OS/GPUの簡易値、MediaMTX metrics生値 |
| 集計 | CSV、JSON | シナリオ比較、レビュー |
| グラフ | PNG | p95遅延、FPS、接続成功率 |

---

## 6. 自動化構成

### 6.1 コンポーネント

```text
scenario JSON
    |
run-scenarios.sh
    +-- prepare-fixture.sh
    |      +-- FFmpeg -> sample.mp4 / sample.y4m
    |
    +-- WebRTC case
    |      +-- Playwright + Chromium fake camera
    |      +-- WHIP または実アプリ開始フック
    |      +-- getStats / result event / browser error
    |
    +-- RTSP case
    |      +-- FFmpeg processes
    |      +-- 同一MP4を -re / loop publish
    |
    +-- collect-resources.sh
    |      +-- MediaMTX metrics
    |      +-- OS / nvidia-smi（利用可能な場合）
    |
    +-- summarize-results.py
           +-- summary.csv / JSON / PNG

compare-results.py
    +-- WebRTC inference JSONL
    +-- RTSP inference JSONL
    +-- 相対比較CSV / JSON
```

### 6.2 推奨する疑似カメラ方式

FFmpegでMP4を正規化し、Chromiumが受け付けるY4Mへ変換して、以下の起動オプションで疑似カメラとして使用する。

```text
--use-fake-device-for-media-stream
--use-fake-ui-for-media-stream
--use-file-for-fake-video-capture=/workspace/tmp/performance-fixtures/sample.y4m
```

理由は、実アプリが通常どおり`getUserMedia()`を呼び出せるためである。canvas captureは軽量だが、実アプリへの差し込みに追加フックが必要になるため、今回は補助方式とする。

### 6.3 Chromium起動オプション

- `--no-sandbox`
- `--disable-setuid-sandbox`
- `--use-fake-device-for-media-stream`
- `--use-fake-ui-for-media-stream`
- `--use-file-for-fake-video-capture=<Y4M>`
- `--autoplay-policy=no-user-gesture-required`
- `--disable-background-timer-throttling`
- `--disable-renderer-backgrounding`
- `--disable-backgrounding-occluded-windows`

既定はheadlessとし、問題発生時のみ`PERF_HEADLESS=0`と仮想ディスプレイへ切り替える。

### 6.4 Playwrightの役割

- Chromiumの起動と終了
- カメラ・マイク権限付与
- 複数ブラウザコンテキストの作成
- WHIP publishまたは実アプリ開始フックの実行
- WebRTC getStatsの定期取得
- 結果受信・描画時刻の取得
- console、pageerror、crashの保存
- 異常時もブラウザを閉じる

### 6.5 動画差し替え

```bash
PERF_SOURCE_VIDEO=/workspace/tmp/input/sample-input.mp4 \
PERF_FIXTURE_DURATION=30 \
PERF_FIXTURE_FPS=15 \
PERF_FIXTURE_WIDTH=640 \
PERF_FIXTURE_HEIGHT=360 \
bash scripts/performance/prepare-fixture.sh
```

実動画はpublic repositoryへ登録せず、`tmp/`またはローカル専用ディレクトリへ置く。

### 6.6 複数クライアント

- WebRTCは1つのChromiumプロセス内で複数browser contextを起動する
- 各クライアントは個別のWHIP pathを使用する
- 250msずつ開始をずらし、瞬間的な開始負荷を抑える
- RTSPはクライアント数と同数のFFmpegプロセスを起動する
- WSL側CPUが先に飽和した場合、接続数を減らすか、生成側とサーバ側の負荷を分離する

### 6.7 ログ収集

結果ディレクトリ例:

```text
tmp/performance-results/<run-id>/
  run.json
  scenarios.json
  cases/
    <scenario-id>_rep<n>/
      case.json
      browser-events.jsonl
      webrtc-stats.csv
      result-events.csv
      publisher-events.csv
      resource-samples.csv
      metrics/*.prom
      publishers/*.log
  summary/
    summary.csv
    summary.json
    graphs/*.png
```

### 6.8 開始・終了制御

- `run-scenarios.sh`がケースごとにリソース収集を開始
- WebRTCまたはRTSP publisherを指定時間実行
- publisher終了後にcollectorを待機・終了
- `case.json`へstatus、exit code、終了時刻を追記
- 全ケース終了後に集計を実行

### 6.9 異常終了時の後片付け

- shellの`trap`でFFmpegへTERM、残存時はKILL
- Nodeの`finally`でbrowser contextとChromiumを終了
- ケース失敗は`case.json`へ記録し、次ケースへ進む
- 最終的にDocker Composeを`down -v`する

### 6.10 命名規則

```text
run_id  : YYYYMMDDTHHMMSSZ
case_id : <scenario_id>_rep<repeat>
client  : webrtc-001 / rtsp-001
path    : live/perf/<scenario-id-lower>/<client-id>
```

### 6.11 設定値の外部化

- シナリオ: `configs/performance/scenarios.example.json`
- 実環境URL・認証: 環境変数または`.env`
- 実動画: `tmp/`配下
- 一部ケース再実行: `PERF_ONLY_SCENARIOS`
- 実アプリURL: `PERF_APP_URL`

### 6.12 実行コマンド

#### 環境準備

```bash
docker compose -f examples/docker-compose.performance.yml build performance-runner
docker compose -f examples/docker-compose.performance.yml up -d mediamtx
```

#### 入力動画生成

```bash
docker compose -f examples/docker-compose.performance.yml run --rm \
  --entrypoint bash performance-runner \
  scripts/performance/prepare-fixture.sh
```

#### 単体シナリオ

```bash
PERF_ONLY_SCENARIOS="P01_WEBRTC_1" \
docker compose -f examples/docker-compose.performance.yml run --rm \
  -e PERF_ONLY_SCENARIOS performance-runner
```

#### 必須シナリオ一括

```bash
PERF_ONLY_SCENARIOS="P01_WEBRTC_1 P02_RTSP_1 P03_WEBRTC_NORMAL P04_RTSP_NORMAL P05_WEBRTC_MEDIUM P06_RTSP_MEDIUM" \
docker compose -f examples/docker-compose.performance.yml run --rm \
  -e PERF_ONLY_SCENARIOS performance-runner
```

#### 実アプリ経由

```bash
PERF_APP_URL="https://example.invalid/performance-test" \
PERF_ONLY_SCENARIOS="P01_WEBRTC_1" \
docker compose -f examples/docker-compose.performance.yml run --rm \
  -e PERF_APP_URL -e PERF_ONLY_SCENARIOS performance-runner
```

#### 推論結果比較

```bash
docker compose -f examples/docker-compose.performance.yml run --rm \
  --entrypoint python3 performance-runner \
  scripts/performance/compare-results.py \
    --webrtc /workspace/tmp/results/webrtc.jsonl \
    --rtsp /workspace/tmp/results/rtsp.jsonl \
    --out /workspace/tmp/results/comparison \
    --tolerance-ms 50
```

#### 再集計

```bash
python3 scripts/performance/summarize-results.py tmp/performance-results/<run-id>
```

#### 後片付け

```bash
docker compose -f examples/docker-compose.performance.yml down -v
```

---

## 7. FFmpegとGStreamerの比較

| 観点 | FFmpeg | GStreamer | 今回の評価 |
|---|---|---|---|
| WSL導入 | パッケージ1つで導入しやすい | plugins一式が必要 | FFmpeg有利 |
| 疑似カメラ | Y4M生成が簡単 | v4l2loopback等はWSLで複雑 | FFmpeg有利 |
| Chromium連携 | `--use-file-for-fake-video-capture`用Y4Mを生成可能 | 直接連携にはパイプや仮想デバイスが必要 | FFmpeg有利 |
| 同一動画ループ | `-stream_loop -1` | `multifilesrc`等で可能 | 同等だがFFmpegが簡潔 |
| 複数クライアント | 複数プロセス起動が容易 | pipeline管理が必要 | FFmpeg有利 |
| FPS制御 | `-vf fps=`、`-r` | `videorate`、caps | 同等 |
| タイムスタンプ | drawtext、setpts、showinfo | timeoverlay等 | 同等 |
| RTSP配信 | `-f rtsp`で短いコマンド | rtspclientsink等のplugin差異 | FFmpeg有利 |
| トラブルシュート | 利用例・ログ・知見が多い | pipeline理解が必要 | FFmpeg有利 |
| 実装工数 | 小 | 中～大 | FFmpeg有利 |

### 採用判断

**今回の主方式はFFmpegとする。**

GStreamerは、FFmpegで必要なcodecまたは接続方式に対応できない場合のみ代替候補とし、必須測定での併用は行わない。ブラウザはFFmpeg生成Y4MをChromium疑似カメラとして使用し、RTSP比較は同じ内容のMP4をFFmpegでpublishする。

---

## 8. 3週間の作業計画

### 担当区分

- **本人**: 要件判断、条件承認、実機操作、結果レビュー
- **他メンバー**: アプリ計測フック、推論ログ、環境準備
- **自動**: 動画生成、シナリオ実行、ログ収集、集計、グラフ
- **待ち時間併行**: 長めのビルド・測定中に進められる作業

| 日程 | 作業内容 | 成果物 | 目安 | 担当 | 前提 | 完了条件 |
|---|---|---|---:|---|---|---|
| 準備1週目 Day1 AM | 対象URL、認証、代表動画、クライアント数の仮決定 | 要確認事項更新 | 本人30分、他1時間 | 本人・他 | なし | 暫定値で実装を止めず進められる |
| Day1 PM | performance-runner build、MediaMTX起動 | コンテナ起動手順 | 他2時間 | 他 | Docker | Compose build成功 |
| Day2 AM | 固定MP4/Y4M生成 | fixture一式 | 自動15分、他30分 | 自動・他 | FFmpeg | 同一内容のMP4/Y4Mを生成 |
| Day2 PM | WebRTC 1クライアントWHIP配信 | browser log、getStats | 他2時間 | 他 | MediaMTX | 5分配信とログ保存成功 |
| Day3 AM | RTSP 1クライアント配信 | publisher log | 他1時間 | 他 | fixture | 同じMP4で5分配信成功 |
| Day3 PM | シナリオrunnerとcase管理 | case.json、run directory | 他2時間 | 他・自動 | WebRTC/RTSP単体 | P01/P02を設定から実行 |
| Day4 | アプリ計測フック、推論JSONL追加 | result event、推論log | 他4時間 | 他 | 実アプリ | 最低限source/renderまたは推論開始終了を取得 |
| Day5 AM | P01/P02予備測定 | 予備CSV | 自動1時間 | 自動 | 計測フック | E2Eまたは簡易遅延が1件以上集計可能 |
| Day5 PM | 1週目レビュー | 条件修正、課題一覧 | 本人45分、他30分 | 本人・他 | 予備結果 | 2週目の条件を確定 |
| 準備2週目 Day6 | 3/6クライアント起動、WSL上限確認 | P03～P06 smoke | 他3時間 | 他・自動 | P01/P02 | クライアント生成側が先に詰まらない条件を確定 |
| Day7 | リソース収集統合 | metrics、resource CSV | 他2時間 | 他・自動 | 監視endpoint | CPU/GPU等が少なくとも1系統取得可能 |
| Day8 | compare-results実データ確認 | 比較CSV/JSON | 他2時間 | 他・自動 | WebRTC/RTSP結果log | 検出件数・クラス・信頼度を比較可能 |
| Day9 AM | 異常終了、再実行、後片付け確認 | 再測定手順 | 他2時間 | 他 | runner | 失敗ケースのみ再実行可能 |
| Day9 PM | 実機手順のリハーサル | 実機チェックリスト | 本人30分、他30分 | 本人・他 | 実アプリ | 5分測定を迷わず実施可能 |
| Day10 | 測定条件凍結、予備測定 | 凍結config、予備summary | 本人30分、他2時間 | 本人・他・自動 | 全機能 | 測定週に新機能を追加しない状態 |
| 測定週 Day11 | P01/P02本測定 | 基準値 | 自動約40分 | 自動 | 条件凍結 | 3反復完了、失敗時再実行 |
| Day12 | P03/P04本測定 | 通常負荷比較 | 自動約2時間 | 自動 | Day11 | 3反復完了 |
| Day13 | P05/P06本測定 | 中程度負荷比較 | 自動約1時間 | 自動 | Day12 | 2反復完了 |
| Day14 AM | 実スマートフォン3回 | 実機結果 | 本人45分、他30分 | 本人・他 | 実機環境 | 表示・遅延・接続を記録 |
| Day14 PM | 追加試験判断 | P07実施可否 | 本人15分 | 本人 | 必須結果 | 必須欠損がなければ追加へ進む |
| Day15 | 集計、比較表、レビュー | 最終summary、グラフ、課題 | 本人60分、他3時間、自動 | 本人・他・自動 | 全ログ | 設計判断と制約を説明可能 |

### 想定作業時間

- 本人: 約4時間15分
- 他メンバー: 約28～32時間
- 自動実行時間: 必須約4～6時間。待ち時間中は結果サマリー、実機手順、課題整理を進める

---

## 9. 成果物一覧

成果物は以下の6グループへ統合する。

| 成果物 | 内容 |
|---|---|
| 性能測定計画 | 本書。目的、スコープ、シナリオ、方式、3週間計画、リスクを統合 |
| 実行設定・手順 | scenario JSON、Compose、環境変数、再測定コマンド |
| 自動測定ツール | fixture生成、Playwright WebRTC、FFmpeg RTSP、resource収集、scenario runner |
| 生データ | 入力動画メタデータ、ブラウザJSONL、WebRTC stats、推論JSONL、MediaMTX metrics、publisher log |
| 集計・比較 | summary CSV/JSON/PNG、WebRTC/RTSP比較CSV/JSON |
| 結果サマリー | 設計判断、課題、制約、再測定条件を1つのMarkdownへ整理 |

実動画、実URL、認証情報、実環境ログはpublic repositoryへ含めない。

---

## 10. リスクと代替策

| リスク | 兆候 | 短期間の代替策 |
|---|---|---|
| WSLで疑似カメラが認識されない | `getUserMedia`失敗 | Docker内Playwright公式イメージへ固定。Y4Mを絶対パス指定。なお失敗する場合はcanvas captureのdirect WHIPへ切替 |
| headlessでカメラ入力不可 | headfulでは成功 | `PERF_HEADLESS=0`とXvfbへ切替。必須測定はheadfulでも実行可 |
| Playwright WebRTC接続が不安定 | WHIP失敗、ICE未接続 | クライアント開始をずらす。1ブラウザ1クライアントへ分離。接続数を6から3へ削減 |
| 自動再生制限 | 動画開始しない | `--autoplay-policy=no-user-gesture-required`を使用し、アプリ側も明示的に`play()`を呼ぶ |
| ブラウザ権限 | permission denied | Playwright context permissionsとfake UI optionを使用。HTTPS要件は実アプリ側で満たす |
| GPU/推論サーバが準備中に利用不可 | 接続不可、予約不可 | 1週目はMediaMTX＋モック結果イベントで測定系を完成。GPU利用可能後に推論区間だけ接続 |
| WebRTC/RTSPのフレーム対応不可 | frame_id欠落 | source timestamp最近傍50msへ変更。さらに難しい場合は1秒間隔サンプリングとクラス件数比較へ縮退 |
| 時計ずれ | 負の遅延、異常値 | NTP再同期。同一ホスト内区間のみ集計。E2Eはframe_idまたは動画周期マーカーで補完 |
| ログ量過多 | disk急増 | getStatsを5秒間隔、metricsを5秒間隔に固定。全フレーム画像保存は禁止。JSONLを圧縮保存 |
| 測定中の切断 | case失敗 | case単位で再実行。切断自体を安定性結果へ記録し、全マトリクスを最初からやり直さない |
| 構築に時間を使いすぎる | 1週目終了時に1配信未達 | 実アプリ統合を後回しにし、direct WHIP＋既存推論ログで基準測定を優先 |
| Y4Mが大きすぎる | 数GB、IO負荷 | 640x360/15fps/30秒へ縮小。必要時だけ720pを生成。ファイルはtmp配下に限定 |
| クライアント生成側がボトルネック | WSL CPU 90%以上 | 生成側resourceを同時記録し、6クライアントを3へ削減。または別ホストから生成 |
| RTSP側だけ結果表示経路がない | ブラウザ結果なし | RTSPは推論サーバJSONLで比較し、ブラウザ描画遅延はWebRTCのみ取得。比較範囲を明記 |

---

## 11. 中止基準・スコープ削減基準

### 準備1週目終了時

以下が未達の場合、詳細計測を追加せず最小測定系へ切り替える。

- 1クライアントのWebRTC publishが5分継続しない
- 同一動画のMP4/Y4Mを生成できない
- ブラウザログまたはMediaMTX metricsを保存できない

最小測定系は、direct WHIP、MediaMTX metrics、既存推論ログ、実機目視10サンプルとする。

### 準備2週目終了時

以下が未達の場合、測定週に新機能を追加しない。

- P01/P02予備測定が完了していない
- 推論結果のWebRTC/RTSP比較用JSONLが生成できない
- 失敗ケースの再実行ができない

### 削減順序

1. クライアント数を1/3/6から1/3へ減らす
2. P07の2時間試験を削除する
3. 詳細区間別遅延を削除し、source→browser renderのE2Eだけにする
4. 実機測定を3回から1回へ減らす
5. フレーム単位比較を1秒間隔のサンプリング比較へ変更する
6. 動画を1本、解像度を640x360、FPSを15へ固定する

可能な限り残す項目:

- WebRTCとRTSPの同一動画比較
- WebRTCの基本E2E遅延
- 1クライアントと通常想定クライアントの比較
- 接続成功率、推論FPS、主要リソース

---

## 12. 最終的な推奨計画

| 項目 | 推奨内容 |
|---|---|
| 必須測定 | P01～P06とP08。1/3/6クライアント、WebRTC/RTSP、固定動画1本、E2E、FPS、安定性、主要リソース、推論結果相対比較 |
| 追加測定 | 必須完了後のみP07の2時間試験。余裕があれば代表動画2本目 |
| 採用ツール | Docker Compose、Playwright、Chromium、FFmpeg、Python、shell、既存MediaMTX metrics、利用可能ならnvidia-smi |
| 自動化範囲 | fixture生成、publisher起動、複数クライアント、ログ、ケース管理、集計、グラフ、結果比較、後片付け |
| 本人の想定時間 | 約4時間。条件承認、1週目レビュー、実機45分、最終レビューを中心とする |
| 他メンバーの想定時間 | 約28～32時間。アプリ計測フックと推論ログ統合が中心 |
| 最大の技術リスク | 推論結果までframe_id/source timestampを伝搬できず、WebRTC/RTSPの正確な対応付けができないこと |
| 最初に着手する作業 | Docker内ChromiumへY4Mを疑似カメラ入力し、1クライアントWHIP publishとbrowser log保存を成功させる |
| 準備1週目終了時 | P01/P02を1回ずつ実行し、WebRTC/RTSP配信、ログ保存、最低限の遅延または推論時間を集計可能 |
| 準備2週目終了時 | P01～P06のsmoke、実アプリ計測フック、推論比較JSONL、再実行、集計まで完成し、条件を凍結 |
| 測定週終了時 | 必須シナリオ、実機確認、WebRTC/RTSP比較表、p95遅延/FPS/成功率グラフ、設計判断、制約、再測定手順を提出 |

本計画では、測定基盤の完成度よりも測定結果の取得を優先する。準備1週目で最低限動く1クライアント系を完成させ、準備2週目は安定化と比較ログ統合に限定し、測定週に新機能を追加しない。
