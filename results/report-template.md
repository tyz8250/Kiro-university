# Experiment 1 Result Report

## Source hypothesis

- Hypothesis document: [Experiment 1 hypothesis](../Docs/experiment-1-hypothesis.md)
- The hypothesis text must be evaluated as written in the linked document; do not rewrite it after observing the result.

## Experiment metadata

### Trace ID

| Item | Value |
|---|---|
| Fault experiment Trace ID | `<trace-id>` |

### Timeline

| Event | Timestamp |
|---|---|
| Baseline取得 | `<timestamp>` |
| `pre-fault-monitor.sh` 起動 | `<timestamp>` |
| Default Route削除 | `<timestamp>` |
| `observe.sh` 実行 | `<timestamp>` |
| Default Route復元 | `<timestamp>` |
| `post-restore-collect.sh` 実行 | `<timestamp>` |

## Hypothesis vs Actual Observation

| Observation Point | Hypothesis（リンク先の原文に基づく） | Actual Observation（観測事実のみ） | Match |
|---|---|---|---|
| Mac curl | `<hypothesis>` | `<fact>` | `<yes / no / partial>` |
| EC2 tcpdump | `<hypothesis>` | `<fact>` | `<yes / no / partial>` |
| Docker | `<hypothesis>` | `<fact>` | `<yes / no / partial>` |
| Go Server | `<hypothesis>` | `<fact>` | `<yes / no / partial>` |

## Observed facts

このセクションには、コマンド出力や時刻から直接確認できる事実だけを記録する。

### Mac curl

- Timestamp: `<timestamp>`
- HTTP status / curl exit code: `<value>`
- Trace ID: `<trace-id>`
- Observed output: `<fact>`

### EC2 tcpdump

- Capture interval: `<start> - <end>`
- Source IP / destination port 8080: `<fact>`
- SYN observed: `<yes / no / unknown>`
- Observed output: `<fact>`
- Note: Trace ID is not visible at L4; correlate using timestamp, source IP, and destination port.

### Docker

- Timestamp range: `<start> - <end>`
- Container name / status: `<fact>`
- Observed output: `<fact>`

### Go Server

- Host health-check timestamp range: `<start> - <end>`
- Host health-check status: `<fact>`
- Go Server log for the fault Trace ID: `<fact / not collected>`
- Observed output: `<fact>`

## Interpretation

このセクションには、上記の観測事実から導いた解釈を書く。観測できなかった内容を事実として扱わない。

- MacからEC2までの通信経路について: `<interpretation>`
- EC2内部のDocker / Go Serverについて: `<interpretation>`
- tcpdumpとアプリケーションログの相関について: `<interpretation>`
- 未確認事項: `<unknowns>`

## Explanation of differences

仮説と観測結果が異なった項目ごとに記録する。

| Observation Point | Difference | Explanation | Supporting evidence |
|---|---|---|---|
| `<point>` | `<hypothesis vs fact>` | `<explanation>` | `<timestamp / log / packet>` |

## AWS Route Table / Internet Gateway behavior check

| Item | Entry |
|---|---|
| Official AWS documentation URL | `<url>` |
| Route Table behavior confirmed from documentation | `<summary>` |
| Internet Gateway behavior confirmed from documentation | `<summary>` |
| How the official behavior explains the observation | `<explanation>` |
| Remaining uncertainty | `<unknowns>` |

## Final conclusion

### Confirmed facts

- `<fact>`

### Interpretation supported by those facts

- `<interpretation>`

### Hypothesis evaluation

- `<supported / falsified / partially supported>`

### Next investigation

- `<next step or none>`
