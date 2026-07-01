# MediaMTX 負荷試験のコンテナ運用

## 目的

負荷試験に必要な FFmpeg、GStreamer、jq、Python、matplotlib をホストへ直接インストールせず、`load-runner` コンテナで実行する。

MediaMTX も同じ Docker Compose stack で起動し、`load-runner` から Docker network 内の service 名 `mediamtx` へ接続する。

## 追加構成

| ファイル | 用途 |
|---|---|
| `docker/load-runner/Dockerfile` | 負荷試験実行用イメージ |
| `examples/docker-compose.load.yml` | MediaMTX + load-runner の Compose stack |
| `scripts/load/run-load-matrix.sh` | コンテナ内でも実行できる負荷試験 runner |
| `scripts/load/render-load-graphs.py` | コンテナ内でグラフ生成 |

## 基本実行

まず build する。

```bash
docker compose -f examples/docker-compose.load.yml build load-runner
```

MediaMTX を起動する。

```bash
docker compose -f examples/docker-compose.load.yml up -d mediamtx
```

軽量な負荷試験を実行する。

```bash
docker compose -f examples/docker-compose.load.yml run --rm \
  -e LOAD_COUNTS="1 5" \
  -e LOAD_PROFILES="low" \
  -e LOAD_MODES="copy" \
  -e LOAD_REPEAT_COUNT="1" \
  -e LOAD_DURATION="30" \
  load-runner
```

停止する。

```bash
docker compose -f examples/docker-compose.load.yml down -v
```

## 出力先

コンテナ内の出力先は以下。

```text
/workspace/tmp/load-test/container
```

ホスト側では以下に保存される。

```text
tmp/load-test/container/
```

主な出力は以下。

| ファイル | 内容 |
|---|---|
| `case-results.csv` | case ごとの実行結果 |
| `run-config.txt` | 実行時パラメーター |
| `cases/<case-id>/samples.csv` | case ごとの時系列 sample |
| `cases/<case-id>/metrics-*.prom` | MediaMTX metrics の raw dump |
| `cases/<case-id>/publishers/*.log` | publisher log |
| `cases/<case-id>/readers/*.log` | reader log |
| `graphs/*.png` | 生成されたグラフ |
| `graphs/summary.csv` | グラフ用の集計CSV |

## 前回候補を一通り試す

```bash
docker compose -f examples/docker-compose.load.yml run --rm \
  -e LOAD_COUNTS="1 5 10 20 50 100" \
  -e LOAD_PROFILES="low medium high" \
  -e LOAD_MODES="copy encode" \
  -e LOAD_PUBLISHERS="ffmpeg" \
  -e LOAD_REPEAT_COUNT="1" \
  -e LOAD_DURATION="300" \
  -e LOAD_SAMPLE_INTERVAL="5" \
  load-runner
```

## 同じ条件を複数回測る

```bash
docker compose -f examples/docker-compose.load.yml run --rm \
  -e LOAD_COUNTS="10 20 50" \
  -e LOAD_PROFILES="medium" \
  -e LOAD_MODES="copy" \
  -e LOAD_REPEAT_COUNT="3" \
  -e LOAD_DURATION="300" \
  load-runner
```

`LOAD_REPEAT_COUNT=3` は、各パラメーターセットを3回測るという意味。

## 特定 case だけ再実行する

例: `ffmpeg_medium_encode_10s_0r_rep2` だけ再実行する。

```bash
docker compose -f examples/docker-compose.load.yml run --rm \
  -e LOAD_COUNTS="10" \
  -e LOAD_PROFILES="medium" \
  -e LOAD_MODES="copy encode" \
  -e LOAD_PUBLISHERS="ffmpeg" \
  -e LOAD_REPEAT_COUNT="3" \
  -e LOAD_ONLY_CASE_IDS="ffmpeg_medium_encode_10s_0r_rep2" \
  -e LOAD_DURATION="300" \
  load-runner
```

`LOAD_ONLY_CASE_IDS` は、条件マトリクスの中から一致した case だけを実行する。元の case が生成される `LOAD_COUNTS` / `LOAD_PROFILES` / `LOAD_MODES` / `LOAD_PUBLISHERS` / `LOAD_REPEAT_COUNT` も指定する。

## reader ありで試す

```bash
docker compose -f examples/docker-compose.load.yml run --rm \
  -e LOAD_COUNTS="5 10 20" \
  -e LOAD_PROFILES="medium" \
  -e LOAD_MODES="copy" \
  -e LOAD_READERS_PER_STREAM="1" \
  -e LOAD_DURATION="300" \
  load-runner
```

`LOAD_READERS_PER_STREAM=1` は、各 stream に 1 reader を接続するという意味。

## GStreamer で試す

```bash
docker compose -f examples/docker-compose.load.yml run --rm \
  -e LOAD_COUNTS="1 5 10" \
  -e LOAD_PROFILES="low medium" \
  -e LOAD_MODES="encode" \
  -e LOAD_PUBLISHERS="gstreamer" \
  -e LOAD_DURATION="120" \
  load-runner
```

GStreamer は現時点で `encode` のみ対応する。

## GitHub Actions

`.github/workflows/load-test-graphs.yml` も `load-runner` コンテナで実行する。

```text
Actions → MediaMTX load test graphs → Run workflow
```

workflow は `workflow_dispatch` 専用。push / pull_request では自動実行しない。

## Docker stats について

コンテナ運用では、`load-runner` から Docker socket を参照しない。そのため `docker stats` 由来の CPU / memory 欄は空になる。

MediaMTX の状態確認は以下を使う。

- Control API: path / session 数
- metrics endpoint: Prometheus raw metrics
- publisher / reader logs
- MediaMTX container logs

Docker stats まで取りたい場合は、ホスト実行にするか、別途監視用の仕組みを用意する。Docker socket を load-runner に mount する構成は、public example としては採用しない。

## 注意点

- 現時点の protocol は RTSP publish 前提
- RTMP / SRT / WebRTC の protocol 比較は別途拡張が必要
- `copy` は MediaMTX 受信負荷を見やすい
- `encode` は publisher 側 CPU が支配的になる場合がある
- 同一ホスト上で MediaMTX と大量 publisher を動かす場合、ホスト全体の CPU / network が先に詰まる可能性がある
