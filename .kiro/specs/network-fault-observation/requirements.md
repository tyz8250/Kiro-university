# Requirements Document

## Introduction

AWS上にTerraform + EC2 + Docker + Goで小さなHTTPサーバーを構築し、ネットワーク障害（Public SubnetのRoute Tableからデフォルトルートを削除）を意図的に発生させて通信経路を観測する実験システム。

実験のフロー：**Hypothesis → Build → Baseline → Break → Observe → Explain → Restore**

実験では各リクエストにTrace IDを付与し、Mac・EC2・Docker・Goアプリのログを横断的に紐付けることで、障害発生時に通信がどの境界で遮断されるかを検証する。

本ドキュメントは Experiment 1「Route Table の default route を削除する」を対象とする。実験前の仮説は `docs/experiment-1-hypothesis.md` に記録されており、Requirementsはその仮説を変更せず参照する。

---

## Glossary

- **Experiment_System**: Terraform・EC2・Docker・Goで構成されたネットワーク観測実験システム全体
- **Terraform**: インフラをコードで管理するツール。VPC・Subnet・IGW・Route Table・Security Group・EC2を管理する
- **VPC**: AWS Virtual Private Cloud。実験環境を隔離するネットワーク空間
- **Public_Subnet**: インターネットゲートウェイへのルートを持つサブネット
- **Internet_Gateway**: VPCとインターネットを接続するAWSコンポーネント（略称: IGW）
- **Route_Table**: パケットの転送先を定義するAWSリソース。`0.0.0.0/0 → IGW` がデフォルトルート
- **Default_Route**: Route Table上の `0.0.0.0/0 → Internet_Gateway` エントリ
- **Security_Group**: EC2インスタンスへのインバウンド/アウトバウンドを制御するファイアウォール
- **EC2**: 実験用Amazon Linux 2インスタンス。DockerとGoアプリをホストする
- **Go_Server**: EC2上のDockerコンテナ内で動作するGoのHTTPサーバー（ポート8080）
- **Docker**: EC2上でGo_Serverを実行するコンテナランタイム
- **Trace_ID**: 各HTTPリクエストに付与するユニークな識別子。形式は `[A-Za-z0-9\-_]{1,64}`。HTTPヘッダー `X-Trace-ID` で伝搬する
- **Baseline**: 障害発生前の正常状態における各観測点の記録
- **Observer**: 実験者（Mac上でcurlを実行し、EC2上でtcpdumpを実行する人または自動スクリプト）
- **tcpdump**: EC2のNIC上でパケットをキャプチャするコマンドラインツール
- **Host_curl**: EC2ホスト（コンテナ外）から実行するcurlコマンド
- **Incident_Investigator**: 障害調査専用のKiro Custom Agent。観測のみ行い、変更は行わない
- **Hypothesis_Document**: `docs/experiment-1-hypothesis.md` に記録された実験前の仮説

---

## Requirements

### Requirement 1: インフラのプロビジョニング

**User Story:** As an Observer, I want to provision the AWS infrastructure with Terraform, so that I have a reproducible experimental environment.

#### Acceptance Criteria

1. THE Terraform SHALL provision a VPC with a single Public_Subnet, an Internet_Gateway, a Route_Table containing a Default_Route, a Security_Group, and one EC2 instance.
2. WHEN `terraform apply` completes successfully, THE Terraform SHALL output the EC2 public IP address.
3. WHEN `terraform plan` is executed after a successful apply with no changes, THE Terraform SHALL report zero infrastructure drift.
4. IF `terraform validate` fails, THEN THE Terraform SHALL exit with a non-zero status code and print a descriptive error message.
5. THE Terraform SHALL store state in a manner that allows `terraform destroy` to cleanly remove all provisioned resources.

---

### Requirement 2: Go HTTPサーバーの構築

**User Story:** As an Observer, I want a small Go HTTP server running inside Docker on EC2, so that I have a controllable HTTP endpoint to probe during experiments.

#### Acceptance Criteria

1. THE Go_Server SHALL listen on port 8080 and respond to `GET /health` with HTTP 200.
2. WHEN a request contains the header `X-Trace-ID: <id>`, THE Go_Server SHALL include the same `<id>` value in the response header `X-Trace-ID`.
3. WHEN a request does not contain the header `X-Trace-ID`, THE Go_Server SHALL generate a new Trace_ID and include it in the response header `X-Trace-ID`.
4. THE Go_Server SHALL log each request in a structured format containing: timestamp, Trace_ID, HTTP method, URL path, response status code.
5. THE Docker SHALL map host port 8080 to container port 8080 and keep the Go_Server container in a running state.
6. WHILE the Go_Server is running, THE Go_Server SHALL respond to `GET /health` from within the EC2 host (Host_curl) within 1000ms.

---

### Requirement 3: Trace IDによるリクエスト追跡

**User Story:** As an Observer, I want every request to carry a Trace ID across Mac, EC2, Docker, and Go layers, so that I can correlate log entries across all observation points during experiments.

#### Acceptance Criteria

1. WHEN the Observer sends a curl request with `X-Trace-ID: <id>`, THE Go_Server SHALL return the identical `<id>` in the response header `X-Trace-ID`.
2. THE Go_Server SHALL write a log line containing the Trace_ID for every received HTTP request.
3. WHEN the Observer filters `docker logs` by a specific Trace_ID, THE Docker SHALL surface at least one log line containing that Trace_ID for each request that reached the Go_Server.
4. FOR ALL Trace_ID values matching `[A-Za-z0-9\-_]{1,64}`, WHEN a request with that Trace_ID is sent to the Go_Server, THE Go_Server SHALL echo the same Trace_ID in the response (round-trip property).
5. IF a Trace_ID value is 65 characters or longer, OR contains characters outside `[A-Za-z0-9\-_]`, THEN THE Go_Server SHALL return HTTP 400 with a descriptive error body. Valid Trace_ID values are exactly 1–64 characters matching `[A-Za-z0-9\-_]{1,64}`.
6. tcpdump captures operate at the TCP (L4) layer and cannot directly observe HTTP headers such as `X-Trace-ID`. Therefore, tcpdump log entries SHALL be correlated with other observation logs using **timestamp, source IP address, and destination port** rather than Trace_ID.

---

### Requirement 4: Baselineの取得

**User Story:** As an Observer, I want to record a baseline of all observation points before any fault is introduced, so that I can compare post-fault observations against a known-good state.

#### Acceptance Criteria

1. WHEN the Default_Route is present in the Route_Table, THE Observer SHALL record a successful curl response (HTTP 200) from Mac to the EC2 public IP on port 8080 as Baseline evidence.
2. WHEN the Default_Route is present, THE Observer SHALL record a tcpdump capture on the EC2 NIC showing TCP SYN, SYN-ACK, and ACK packets for the baseline request as Baseline evidence.
3. WHEN the Default_Route is present, THE Observer SHALL record `docker ps` output showing the Go_Server container in Running state as Baseline evidence.
4. WHEN the Default_Route is present, THE Observer SHALL record a successful Host_curl response (HTTP 200) from within EC2 to `localhost:8080` as Baseline evidence.
5. WHEN the Default_Route is present, THE Observer SHALL record Go_Server log output containing the Trace_ID of the baseline request as Baseline evidence.
6. THE Experiment_System SHALL store all Baseline evidence in a structured record (file or structured log) that can be compared against post-fault observations.

---

### Requirement 5: 障害の注入（Route Table変更）

**User Story:** As an Observer, I want to remove the Default_Route from the Route_Table using Terraform, so that I can observe how network connectivity changes when the Internet Gateway path is removed.

#### Acceptance Criteria

1. WHEN the Observer removes the Default_Route entry from the Terraform configuration and runs `terraform apply`, THE Terraform SHALL remove only the `0.0.0.0/0 → Internet_Gateway` route from the Route_Table without modifying any other infrastructure resource.
2. WHEN `terraform plan` is executed after the Default_Route removal, THE Terraform SHALL show exactly one planned change: deletion of the Default_Route entry.
3. THE Experiment_System SHALL preserve the Terraform state and all other infrastructure resources intact during the Default_Route removal.

---

### Requirement 6: 障害中の観測

**User Story:** As an Observer, I want to observe the behavior of curl, tcpdump, Docker, and the Go application after the Default_Route is removed, so that I can verify or falsify the pre-experiment hypotheses recorded in the Hypothesis_Document.

> **注意:** Route Table のデフォルトルート削除後はMacからEC2へのSSH接続が失われる可能性がある。このため、tcpdump と定期 health チェックは**障害注入前**にEC2上でバックグラウンド起動し、Route Table 復旧・SSH回復後に回収する。

#### Acceptance Criteria

1. BEFORE the Default_Route is removed, THE Observer SHALL start tcpdump on the EC2 NIC as a background process to capture TCP packets on port 8080, writing output to a log file on EC2.
2. BEFORE the Default_Route is removed, THE Observer SHALL start a periodic health-check monitor on EC2 that polls `localhost:8080/health` at regular intervals and writes results (timestamp, HTTP status) to a log file on EC2.
3. WHEN the Default_Route has been removed, THE Observer SHALL attempt a curl request from Mac to the EC2 public IP on port 8080 and record the result (response, timeout, or connection error) with the same Trace_ID format used in Baseline.
4. AFTER the Default_Route has been restored and SSH connectivity to EC2 is confirmed, THE Observer SHALL retrieve the tcpdump log and health-check log from EC2 and record whether TCP SYN packets from Mac were visible during the fault window.
5. WHEN the Default_Route has been removed, THE Observer SHALL record `docker ps` output (via the docker log collected by pre-fault-monitor.sh) to verify whether the Go_Server container remains in Running state during the fault.
6. THE Experiment_System SHALL record all fault-state observations in a structured format that enables direct comparison with the corresponding Baseline entries from Requirement 4.

---

### Requirement 7: 復旧（Route Table の復元）

**User Story:** As an Observer, I want to restore the Default_Route after the experiment, so that the infrastructure is returned to its original state and is ready for the next experiment.

#### Acceptance Criteria

1. WHEN the Observer restores the Default_Route in the Terraform configuration and runs `terraform apply`, THE Terraform SHALL re-add the `0.0.0.0/0 → Internet_Gateway` route to the Route_Table.
2. WHEN the Default_Route has been restored, THE Observer SHALL verify that a curl request from Mac to the EC2 public IP on port 8080 returns HTTP 200 within 30 seconds of the Terraform apply completing.
3. THE Experiment_System SHALL return to the identical infrastructure state as recorded in the Baseline after restoration.

---

### Requirement 8: 実験結果の記録

**User Story:** As an Observer, I want to produce a structured experiment result document comparing hypotheses to actual observations, so that I can clearly articulate what I understood correctly and what I misunderstood.

#### Acceptance Criteria

1. THE Experiment_System SHALL produce a result document that includes, for each observation point (Mac curl, EC2 tcpdump, Docker, Go_Server), a side-by-side comparison of the hypothesis from the Hypothesis_Document and the actual observed result.
2. THE result document SHALL reference the Hypothesis_Document (`docs/experiment-1-hypothesis.md`) without modifying or correcting the hypothesis text.
3. THE result document SHALL record the Trace_ID used during the fault experiment to allow log correlation after the fact.
4. WHEN actual observations differ from the hypothesis, THE result document SHALL include a section explaining the discrepancy with reference to AWS Route Table and Internet Gateway behavior.
5. THE result document SHALL record the timestamp of: Baseline capture, Default_Route removal, each observation during fault, and Default_Route restoration.

---

### Requirement 9: 自動検証（Hook）

**User Story:** As an Observer, I want automated validation to run after Kiro makes any code or Terraform change, so that I do not blindly trust AI-generated modifications.

#### Acceptance Criteria

1. WHEN Kiro completes a task that modifies Go source files, THE Experiment_System SHALL automatically execute `go test ./...` and report pass or fail.
2. WHEN Kiro completes a task that modifies Terraform files, THE Experiment_System SHALL automatically execute `terraform fmt -check` and `terraform validate` and report pass or fail.
3. IF `go test ./...` fails, THEN THE Experiment_System SHALL surface the failure output before proceeding to the next task.
4. IF `terraform validate` fails, THEN THE Experiment_System SHALL surface the failure output before proceeding to the next task.

---

### Requirement 10: Incident Investigatorエージェント

**User Story:** As an Observer, I want a read-only Kiro agent that organizes symptoms and evidence without making changes, so that I can investigate faults systematically without risk of accidental modification.

#### Acceptance Criteria

1. THE Incident_Investigator SHALL read and summarize the current state of: Terraform plan output, `docker ps` / `docker logs`, network interface state (`ss`, `ip`), and Go_Server log files.
2. THE Incident_Investigator SHALL propose a ranked list of boundary candidates (Route_Table, Security_Group, Docker port mapping, Go_Server process) where the fault may reside, with supporting evidence for each.
3. THE Incident_Investigator SHALL NOT execute `terraform apply`, `terraform destroy`, any Docker stop or remove command, or any file modification.
4. WHEN the Incident_Investigator references network behavior, THE Incident_Investigator SHALL cite the relevant AWS documentation section to distinguish observed behavior from assumptions.
