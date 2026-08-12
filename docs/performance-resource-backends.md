# 性能測定のリソース採取バックエンド

WebRTC / RTSP性能測定では、MediaMTXコンテナのCPU、メモリ、ネットワーク通信量を`resource-samples.csv`へ保存する。

Docker実行環境によってcAdvisorからDockerコンテナメトリクスを取得できない場合があるため、性能測定ツールはcAdvisorとDocker Engine statsの2方式を選択できる。

## バックエンド

`PERF_RESOURCE_BACKEND`で以下を指定する。

| 値 | 動作 |
|---|---|
| `auto` | 既定値。cAdvisorメトリクスが取得できればcAdvisorを使用し、取得できなければDocker Engine statsへフォールバックする |
| `cadvisor` | Prometheus経由のcAdvisorメトリクスを使用する |
| `docker` | Docker Engine APIのstatsを使用する |

実際に選択された方式は各ケースの`resource-backend.txt`へ保存する。

```text
requested=auto
selected=docker
```

## autoの判定

`auto`はOS名やWSLの有無では判定しない。

1. Prometheusから`mediamtx`サービスのcAdvisorメモリメトリクスを取得できるか確認する
2. 取得できれば`cadvisor`を選択する
3. 取得できなければ、Docker socketから`mediamtx-poc`コンテナを参照できるか確認する
4. 参照できれば`docker`を選択する
5. どちらも利用できなければMediaMTXコンテナのリソース列を空欄にする

この方式により、通常のLinux Docker環境ではcAdvisorを利用しつつ、Docker DesktopなどcAdvisorがコンテナを認識できない環境ではDocker Engine statsへフォールバックできる。

## 取得値

CSV列はバックエンドによらず共通とする。

```text
mediamtx_cpu_cores
mediamtx_memory_bytes
mediamtx_network_receive_bps
mediamtx_network_transmit_bps
```

`cadvisor`ではPrometheusの以下のメトリクスを使用する。

- `container_cpu_usage_seconds_total`
- `container_memory_working_set_bytes`
- `container_network_receive_bytes_total`
- `container_network_transmit_bytes_total`

`docker`ではDocker Engine stats JSONから以下を算出する。

- CPU: CPU使用時間差分とsystem CPU時間差分からCPUコア相当値を算出
- memory: usageからinactive fileを除いたworking set相当値
- network: RX/TX累積バイトの前回サンプルとの差分をサンプル間隔で割り、bytes/secへ変換

Docker方式のネットワーク速度は連続サンプルの差分から計算するため、最初の1行はRX/TXが空欄になる。

また、Docker Desktopや`network_mode: service:...`のようにnetwork namespaceを共有する構成では、Docker Engine statsのNET I/Oが実際の配信トラフィックを正確に反映しない場合がある。Docker backendではCPU・メモリを主要なリソース指標として扱い、RX/TXはボトルネック分析の補助指標として扱う。ネットワーク帯域を主要な判断材料にする場合は、cAdvisorやホスト側のNIC監視など別の観測手段でも確認する。

## 実行例

### 自動選択

通常は明示指定不要。

```bash
docker compose -f examples/docker-compose.performance.yml run --rm \
  performance-runner
```

### cAdvisorを明示

先にmonitoring profileを起動する。

```bash
docker compose -f examples/docker-compose.performance.yml --profile monitoring \
  up -d mediamtx prometheus cadvisor

docker compose -f examples/docker-compose.performance.yml run --rm \
  -e PERF_RESOURCE_BACKEND=cadvisor \
  performance-runner
```

### Docker Engine statsを明示

Prometheus / cAdvisorを起動せずにMediaMTXコンテナのリソースを取得できる。

```bash
docker compose -f examples/docker-compose.performance.yml run --rm \
  -e PERF_RESOURCE_BACKEND=docker \
  performance-runner
```

## cAdvisorの確認

cAdvisorが利用可能な環境では、以下のようにCompose service label付きメトリクスが返ることを確認する。

```bash
curl -s http://127.0.0.1:8080/metrics \
  | grep -m 5 'container_label_com_docker_compose_service="mediamtx"'
```

`auto`ではこのメトリクスがPrometheusから取得できない場合にDocker方式へ切り替える。

## Docker socketの注意

Docker方式のため、`performance-runner`には`/var/run/docker.sock`をmountする。

Docker socketへアクセスできるコンテナはDocker Engineに対して強い権限を持つ。Compose上でsocketを`:ro` mountしていても、Docker API自体が読み取り専用になるわけではない。

この構成はローカルの短期PoC・性能測定専用とし、以下を守る。

- 信頼できないイメージやスクリプトを`performance-runner`内で実行しない
- public CIへ秘密情報を渡さない
- 本番サーバへそのまま適用しない
- Docker socketを外部ポートへ公開しない

より強い分離が必要な環境では、Docker socket proxyやホスト側collectorへの置き換えを検討する。
