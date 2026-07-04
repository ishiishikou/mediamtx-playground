# Prometheus / cAdvisor を使った負荷試験監視

## 目的

MediaMTX の `/metrics` と、cAdvisor が出す Docker container metrics を Prometheus に集約し、負荷試験後に Prometheus API から CSV / PNG を出力する。

`docker stats` は標準では使わない。コンテナ CPU / memory / network は cAdvisor → Prometheus 経由で見る。

## 構成

```text
Docker Compose
├── mediamtx
├── load-runner
├── prometheus
└── cadvisor
```

| service | 役割 |
|---|---|
| `mediamtx` | 動画 publish / read の対象 |
| `load-runner` | FFmpeg / GStreamer で負荷をかけ、結果とグラフを出力 |
| `prometheus` | MediaMTX metrics と cAdvisor metrics を scrape |
| `cadvisor` | container CPU / memory / network を Prometheus metrics として公開 |

## 追加ファイル

| ファイル | 用途 |
|---|---|
| `examples/docker-compose.monitoring.yml` | Prometheus / cAdvisor を追加する Compose overlay |
| `monitoring/prometheus/prometheus.yml` | Prometheus scrape 設定 |
| `monitoring/prometheus/load-test-queries.json` | 負荷試験用 Prometheus query preset |
| `scripts/load/export-prometheus-range.py` | Prometheus API から時系列を取得して CSV / PNG を出力 |
| `scripts/load/run-container-load.sh` | 負荷試験、既存グラフ、Prometheus グラフをまとめて実行 |

## 起動

`docker-compose.load.yml` に `docker-compose.monitoring.yml` を重ねる。

```bash
docker compose \
  -f examples/docker-compose.load.yml \
  -f examples/docker-compose.monitoring.yml \
  build load-runner
```

```bash
docker compose \
  -f examples/docker-compose.load.yml \
  -f examples/docker-compose.monitoring.yml \
  up -d mediamtx prometheus cadvisor
```

Prometheus UI は localhost だけに公開する。

```text
http://127.0.0.1:9090
```

cAdvisor UI も localhost だけに公開する。

```text
http://127.0.0.1:8080
```

## 負荷試験を実行する

```bash
docker compose \
  -f examples/docker-compose.load.yml \
  -f examples/docker-compose.monitoring.yml \
  run --rm \
  -e LOAD_COUNTS="1 5 10" \
  -e LOAD_PROFILES="low medium" \
  -e LOAD_MODES="copy" \
  -e LOAD_PUBLISHERS="ffmpeg" \
  -e LOAD_REPEAT_COUNT="1" \
  -e LOAD_DURATION="60" \
  load-runner
```

`load-runner` は以下を順番に実行する。

1. `scripts/load/run-load-matrix.sh`
2. `scripts/load/render-load-graphs.py`
3. `scripts/load/export-prometheus-range.py`

## 出力

既定の出力先は以下。

```text
tmp/load-test/container/
```

Prometheus 由来の出力は以下。

```text
tmp/load-test/container/prometheus/
  summary.csv
  csv/
    mediamtx_container_cpu_percent.csv
    mediamtx_container_memory_working_set_bytes.csv
    mediamtx_container_network_receive_bytes_per_sec.csv
    mediamtx_container_network_transmit_bytes_per_sec.csv
    load_runner_container_cpu_percent.csv
    load_runner_container_memory_working_set_bytes.csv
  graphs/
    mediamtx_container_cpu_percent.png
    mediamtx_container_memory_working_set_bytes.png
    mediamtx_container_network_receive_bytes_per_sec.png
    mediamtx_container_network_transmit_bytes_per_sec.png
    load_runner_container_cpu_percent.png
    load_runner_container_memory_working_set_bytes.png
```

## Prometheus query preset

既定の query は `monitoring/prometheus/load-test-queries.json` に定義する。

主な対象は以下。

| query名 | 内容 |
|---|---|
| `mediamtx_container_cpu_percent` | MediaMTX container CPU |
| `mediamtx_container_memory_working_set_bytes` | MediaMTX container memory |
| `mediamtx_container_network_receive_bytes_per_sec` | MediaMTX container network receive |
| `mediamtx_container_network_transmit_bytes_per_sec` | MediaMTX container network transmit |
| `load_runner_container_cpu_percent` | load-runner container CPU |
| `load_runner_container_memory_working_set_bytes` | load-runner container memory |

query を追加する場合は、同じ JSON に以下の形式で追記する。

```json
{
  "name": "example_metric_name",
  "query": "PromQL expression",
  "unit": "bytes"
}
```

`unit` はグラフ表示用。現在は以下を変換する。

| unit | 表示 |
|---|---|
| `bytes` | MiB |
| `bytes_per_second` | MiB/s |
| `percent` | percent |

## 手動で Prometheus export だけ実行する

すでに Prometheus が動いている場合、以下で Prometheus API から取得できる。

```bash
docker compose \
  -f examples/docker-compose.load.yml \
  -f examples/docker-compose.monitoring.yml \
  run --rm --entrypoint python3 load-runner \
  scripts/load/export-prometheus-range.py \
  --prometheus-url http://prometheus:9090 \
  --queries-file /workspace/monitoring/prometheus/load-test-queries.json \
  --out /workspace/tmp/load-test/container/prometheus \
  --lookback-seconds 3600 \
  --step 5
```

## docker stats との関係

`docker stats` は標準では使わない。

`scripts/load/run-load-matrix.sh` には `LOAD_DOCKER_STATS=1` を指定した場合だけ、ホスト実行時の補助として `docker stats` を読む処理を残している。

コンテナ運用では `LOAD_DOCKER_STATS=0` を使う。CPU / memory / network は cAdvisor → Prometheus 経由で見る。

## 停止

```bash
docker compose \
  -f examples/docker-compose.load.yml \
  -f examples/docker-compose.monitoring.yml \
  down -v
```

## 注意点

- cAdvisor は Docker host の情報を読むため、local PoC 用の optional service として扱う
- Prometheus と cAdvisor の port は `127.0.0.1` にだけ公開する
- この構成に実カメラ URL、実 IP、実ホスト名、実認証情報を入れない
- GitHub Actions の手動負荷試験でも同じ overlay を使うが、Actions runner の性能値は本番相当の性能評価として扱わない
