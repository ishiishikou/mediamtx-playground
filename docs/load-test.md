# MediaMTX 負荷試験手順

## 目的

MediaMTX が複数の動画 publisher を同時に受信したとき、どの程度まで安定して動作するかを確認する。

この手順では、まず RTSP publish を対象にする。FFmpeg を主軸にし、GStreamer は任意で試せるようにする。

## 測定する観点

| 観点 | パラメーター |
|---|---|
| 同時 publisher 数 | `1 5 10 20 50 100` |
| profile | `low medium high` |
| mode | `copy encode` |
| publisher 実装 | `ffmpeg gstreamer` |
| 繰り返し回数 | `LOAD_REPEAT_COUNT=1`、`2`、`3` など |
| 特定 case の再実行 | `LOAD_ONLY_CASE_IDS` |
| reader 有無 | `LOAD_READERS_PER_STREAM=0` または `1` 以上 |
| 測定時間 | `LOAD_DURATION` |
| metrics 取得間隔 | `LOAD_SAMPLE_INTERVAL` |

profile の内容は以下。

| profile | 解像度 | FPS | bitrate |
|---|---:|---:|---:|
| `low` | 640x360 | 15 | 500kbps |
| `medium` | 1280x720 | 30 | 1Mbps |
| `high` | 1920x1080 | 30 | 3Mbps |

mode の意味は以下。

| mode | 意味 | 主な用途 |
|---|---|---|
| `copy` | 事前生成した MP4 を `-c copy` で RTSP publish | MediaMTX 側の受信安定性を見やすい |
| `encode` | testsrc をリアルタイム encode して RTSP publish | publisher 側の encode 負荷込みで見る |

GStreamer は `encode` のみ対応する。`copy` は FFmpeg で確認する。

## 追加されたファイル

| ファイル | 用途 |
|---|---|
| `scripts/load/generate-fixtures.sh` | `low` / `medium` / `high` の検証用 MP4 を生成 |
| `scripts/load/run-load-matrix.sh` | 条件を変えながら MediaMTX 負荷試験を実行 |
| `scripts/load/render-load-graphs.py` | metrics / samples から CSV と PNG グラフを生成 |
| `.github/workflows/load-test-graphs.yml` | 手動実行専用の負荷試験 + グラフ生成 workflow |

## 前提

ローカルで実行する場合は以下が必要。

- Docker / Docker Compose
- FFmpeg
- curl
- jq
- Python 3
- matplotlib
- GStreamer を使う場合のみ `gst-launch-1.0`

## MediaMTX を起動する

```bash
docker compose -f examples/docker-compose.poc.yml up -d
```

この Compose では Control API に加えて metrics endpoint も localhost に公開する。

```text
http://127.0.0.1:9997/v3/paths/list
http://127.0.0.1:9998/metrics
```

## 1. 軽量な smoke 負荷試験

まずは短時間・少数で動作確認する。

```bash
LOAD_COUNTS="1 5" \
LOAD_PROFILES="low" \
LOAD_MODES="copy" \
LOAD_REPEAT_COUNT="1" \
LOAD_DURATION="30" \
LOAD_SAMPLE_INTERVAL="5" \
bash scripts/load/run-load-matrix.sh
```

出力先は既定で以下。

```text
tmp/load-test/<timestamp>/
```

## 2. 前回挙げた候補を一通り試す

FFmpeg で、同時 publisher 数・profile・mode を一通り回す。

```bash
LOAD_COUNTS="1 5 10 20 50 100" \
LOAD_PROFILES="low medium high" \
LOAD_MODES="copy encode" \
LOAD_PUBLISHERS="ffmpeg" \
LOAD_REPEAT_COUNT="1" \
LOAD_DURATION="300" \
LOAD_SAMPLE_INTERVAL="5" \
bash scripts/load/run-load-matrix.sh
```

注意点:

- `encode` は publisher 側の CPU 負荷が大きい
- 100本 x high x encode はローカル PC では先に FFmpeg 側が詰まる可能性が高い
- MediaMTX の限界を見たい場合は、まず `copy` を優先する

## 3. 繰り返し測定する

ばらつきを見る場合は `LOAD_REPEAT_COUNT` を増やす。

```bash
LOAD_COUNTS="10 20 50" \
LOAD_PROFILES="medium" \
LOAD_MODES="copy" \
LOAD_REPEAT_COUNT="3" \
LOAD_DURATION="300" \
bash scripts/load/run-load-matrix.sh
```

`LOAD_REPEAT_COUNT=3` は、各パラメーターセットを3回測るという意味。

たとえば以下の場合:

```bash
LOAD_COUNTS="10" \
LOAD_PROFILES="medium" \
LOAD_MODES="copy encode" \
LOAD_REPEAT_COUNT="3" \
bash scripts/load/run-load-matrix.sh
```

実行される case は以下。

| case_id | 意味 |
|---|---|
| `ffmpeg_medium_copy_10s_0r_rep1` | medium / copy / 10 streams の1回目 |
| `ffmpeg_medium_copy_10s_0r_rep2` | medium / copy / 10 streams の2回目 |
| `ffmpeg_medium_copy_10s_0r_rep3` | medium / copy / 10 streams の3回目 |
| `ffmpeg_medium_encode_10s_0r_rep1` | medium / encode / 10 streams の1回目 |
| `ffmpeg_medium_encode_10s_0r_rep2` | medium / encode / 10 streams の2回目 |
| `ffmpeg_medium_encode_10s_0r_rep3` | medium / encode / 10 streams の3回目 |

## 4. 特定 case だけ再実行する

失敗した case だけ再確認したい場合は、`case-results.csv` または `cases/<case-id>/case.json` の `case_id` を使う。

例: `ffmpeg_medium_encode_10s_0r_rep2` だけ再実行する。

```bash
LOAD_COUNTS="10" \
LOAD_PROFILES="medium" \
LOAD_MODES="copy encode" \
LOAD_PUBLISHERS="ffmpeg" \
LOAD_REPEAT_COUNT="3" \
LOAD_ONLY_CASE_IDS="ffmpeg_medium_encode_10s_0r_rep2" \
LOAD_DURATION="300" \
bash scripts/load/run-load-matrix.sh
```

`LOAD_ONLY_CASE_IDS` を指定した場合、条件マトリクスの中から一致する case だけ実行する。

複数 case を再実行する場合:

```bash
LOAD_COUNTS="10 20" \
LOAD_PROFILES="medium" \
LOAD_MODES="copy encode" \
LOAD_PUBLISHERS="ffmpeg" \
LOAD_REPEAT_COUNT="3" \
LOAD_ONLY_CASE_IDS="ffmpeg_medium_encode_10s_0r_rep2 ffmpeg_medium_copy_20s_0r_rep1" \
bash scripts/load/run-load-matrix.sh
```

注意点:

- `LOAD_ONLY_CASE_IDS` は完全一致
- 元の case が生成される条件、つまり `LOAD_COUNTS` / `LOAD_PROFILES` / `LOAD_MODES` / `LOAD_PUBLISHERS` / `LOAD_REPEAT_COUNT` も含めて指定する
- `LOAD_ONLY_CASE_IDS` だけを指定しても、元の条件マトリクスに含まれない case は実行されない

## 5. reader ありで試す

MediaMTX が受信するだけでなく、同時に reader へ配信する場合の負荷を見る。

```bash
LOAD_COUNTS="5 10 20" \
LOAD_PROFILES="medium" \
LOAD_MODES="copy" \
LOAD_READERS_PER_STREAM="1" \
LOAD_DURATION="300" \
bash scripts/load/run-load-matrix.sh
```

`LOAD_READERS_PER_STREAM=1` は、各 stream に 1 reader を接続するという意味。

## 6. GStreamer で試す

GStreamer を使う場合は `LOAD_PUBLISHERS="gstreamer"` を指定する。

```bash
LOAD_COUNTS="1 5 10" \
LOAD_PROFILES="low medium" \
LOAD_MODES="encode" \
LOAD_PUBLISHERS="gstreamer" \
LOAD_DURATION="120" \
bash scripts/load/run-load-matrix.sh
```

GStreamer は現時点で `encode` のみ対応する。

## 7. グラフを生成する

負荷試験の出力ディレクトリを指定する。

```bash
python3 scripts/load/render-load-graphs.py tmp/load-test/<timestamp>
```

生成先:

```text
tmp/load-test/<timestamp>/graphs/
```

生成される主なファイル:

| ファイル | 内容 |
|---|---|
| `summary.csv` | case ごとの最大値・Prometheus metric delta の要約 |
| `peak_cpu_by_case.png` | case ごとの MediaMTX peak CPU |
| `peak_memory_by_case.png` | case ごとの MediaMTX peak memory |
| `peak_active_paths_by_case.png` | case ごとの active path 最大数 |
| `peak_rtsp_sessions_by_case.png` | case ごとの RTSP session 最大数 |
| `prometheus_selected_deltas_by_case.png` | Prometheus metrics の主な増分 |
| `cpu_over_time.png` | CPU 時系列 |

## 8. GitHub Actions で実行する

`.github/workflows/load-test-graphs.yml` は `workflow_dispatch` 専用である。push や pull request では自動実行しない。

GitHub 上で以下を開く。

```text
Actions → MediaMTX load test graphs → Run workflow
```

入力例:

| input | 軽量例 | フル候補例 |
|---|---|---|
| counts | `1 5 10` | `1 5 10 20 50 100` |
| profiles | `low medium` | `low medium high` |
| modes | `copy` | `copy encode` |
| publishers | `ffmpeg` | `ffmpeg` または `ffmpeg gstreamer` |
| repeat_count | `1` | `3` |
| only_case_ids | 空欄 | `ffmpeg_medium_encode_10s_0r_rep2` |
| duration | `60` | `300` 以上 |
| sample_interval | `5` | `5` |
| readers_per_stream | `0` | `0` または `1` |

GitHub Actions runner は性能が固定ではないため、重い条件の結論を本番相当の性能評価として扱わない。Actions では軽量な回帰確認、ローカルまたは専用 VM では長時間・多本数の測定に使う。

## 出力ディレクトリ構造

```text
tmp/load-test/<run-id>/
  run-config.txt
  case-results.csv
  cases/
    <case-id>/
      case.json
      samples.csv
      metrics-0.prom
      metrics-1.prom
      publishers/
      readers/
  graphs/
    summary.csv
    *.png
```

## 判定基準の例

以下を満たす場合、その条件では安定とみなす。

- 指定本数の publisher が接続できる
- 指定時間 MediaMTX が落ちない
- active path 数が想定通り増える
- metrics endpoint が応答し続ける
- Control API が応答し続ける
- memory が一方向に増え続けない
- publisher / reader 側に異常終了が出ない

## 注意点

- `copy` は MediaMTX 受信負荷を見やすい
- `encode` は publisher 側の CPU が支配的になる場合がある
- 同じマシン上で MediaMTX と大量 FFmpeg を動かすと、MediaMTX ではなく FFmpeg 側が先に限界になる可能性がある
- 100本以上の測定や 30分以上の長時間測定は、GitHub Actions ではなくローカルまたは専用 VM で行う
