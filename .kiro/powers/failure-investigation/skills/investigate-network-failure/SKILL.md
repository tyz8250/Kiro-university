---
name: investigate-network-failure
description: Investigate AWS network failures using Hypothesis → Observe → Evidence → Root Cause → Verify. Use when diagnosing Route Table, Security Group, Docker port mapping, or Go server reachability issues without performing automatic remediation.
---

# Investigate Network Failure Skill

## 目的

ネットワーク障害の調査を行い、観測結果を整理し、AWS公式ドキュメントと照合し、原因候補と次の確認方法を提示します。**自動修復は行いません**。

## 調査フロー

1. **Hypothesis** - 仮説の立案
2. **Observe** - 観測データの収集
3. **Evidence** - 証拠の整理
4. **Root Cause** - 根本原因の特定
5. **Verify** - 検証方法の提示

## 禁止操作

以下の破壊的操作は**一切含めません**：
- `terraform apply` / `terraform destroy`
- Dockerの停止/削除 (`docker stop` / `docker rm`)
- ファイルの変更、削除、書き込み
- システム設定の変更
- リソースの作成/削除

## 収集すべき情報源

調査時に参照すべき情報源：
1. **Terraform関連**
   - `terraform plan` 出力
   - `terraform show` 出力
   - Terraform設定ファイルの内容

2. **システム状態**
   - `docker ps` - コンテナの実行状態
   - `docker logs` - コンテナログ
   - `ss -tulpn` - ポートリスニング状態
   - `ip route show` - ルーティングテーブル
   - `ping` / `traceroute` 結果
   - ネットワークインターフェース設定

3. **アプリケーションログ**
   - Goサーバーログファイル
   - アクセスログ
   - エラーログ
   - Trace IDの伝搬状態

4. **AWS環境情報**
   - EC2インスタンス状態
   - セキュリティグループ設定
   - ルートテーブル設定
   - VPC/サブネット設定
   - インターネットゲートウェイ接続

## 調査手順

### 1. Hypothesis (仮説立案)
- 観測された問題現象を確認
- 最も可能性の高い障害箇所を仮説として提示
- ネットワークレイヤーで考えられる原因（Route Table, Security Group, VPC, IGW, EC2インスタンスなど）

### 2. Observe (観測データ収集)
- 上記「収集すべき情報源」からデータを収集
- タイムスタンプ付きで観測結果を記録
- 各観測点での成功/失敗状態を記録

### 3. Evidence (証拠整理)
- 収集したデータをカテゴリ別に整理
- 矛盾点や異常点を特定
- AWS公式ドキュメントと照合して正しい動作か確認

### 4. Root Cause (根本原因特定)
- 観測データとAWSドキュメントを照合
- 遮断境界の候補を優先度順にリストアップ：
  1. Route Table / ルート設定
  2. Security Group / セキュリティグループ設定
  3. Dockerポートマッピング
  4. Goサーバープロセス状態
  5. VPC/サブネット設定
  6. インターネットゲートウェイ接続

- 各候補について根拠となる証拠とAWSドキュメント参照を提示

### 5. Verify (検証方法提示)
- 根本原因を確認するための検証手順を提示
- 安全で非破壊的な検証方法のみ
- 追加で収集すべき観測データの提案
- AWSドキュメントでの関連セクションへの参照

## AWS Documentation MCPの活用方法

Powerに含まれる `aws-docs` MCPサーバーを活用して、以下の情報を参照：

### 検索例：
- Route Tableの動作と設定
- Security Groupのインバウンド/アウトバウンドルール
- VPCネットワーキングの基本
- EC2インスタンスのネットワーク設定
- インターネットゲートウェイの接続性

### ドキュメント参照戦略：
1. まず `search_documentation` で関連キーワード検索
2. 関連するページが見つかったら `read_sections` で特定セクションを抽出
3. 必要に応じて `search_table` で詳細なテーブルデータを検索
4. `recommend` で関連する追加ドキュメントを発見

## 出力フォーマット

調査結果は以下の構造で提示：

```markdown
# ネットワーク障害調査報告

## 1. 問題現象
[観測された問題を簡潔に説明]

## 2. 仮説 (Hypothesis)
[立案した仮説とその根拠]

## 3. 観測データ (Observe)
### 3.1 収集した情報源
- [情報源1]: [状態/結果]
- [情報源2]: [状態/結果]
- ...

### 3.2 異常点の特定
- [異常点1]: [詳細と影響]
- [異常点2]: [詳細と影響]
- ...

## 4. 証拠と分析 (Evidence)
### 4.1 AWSドキュメント参照
- [参照したドキュメントタイトル]: [URL]
  - [関連する内容の要約]

### 4.2 観測データとの比較
- [観測データ]: [AWSドキュメントとの一致/不一致]
- ...

## 5. 根本原因候補 (Root Cause)
### 優先度1: [原因候補1]
- **根拠**: [観測データとAWSドキュメントに基づく根拠]
- **関連AWSドキュメント**: [URLとセクション]
- **確信度**: [高/中/低]

### 優先度2: [原因候補2]
- **根拠**: [観測データとAWSドキュメントに基づく根拠]
- **関連AWSドキュメント**: [URLとセクション]
- **確信度**: [高/中/低]

## 6. 検証方法 (Verify)
### 6.1 確認すべき追加観測
1. [確認項目1]: [観測方法と期待結果]
2. [確認項目2]: [観測方法と期待結果]
3. ...

### 6.2 安全な検証手順
1. [手順1]: [非破壊的な確認方法]
2. [手順2]: [非破壊的な確認方法]
3. ...

## 7. 次のステップ
- [推奨アクション1]
- [推奨アクション2]
- [注意事項/警告]
```

## 使用例

**シナリオ**: Route Tableのデフォルトルート削除によるネットワーク障害

1. **Hypothesis**: Route Tableの設定不備が原因
2. **Observe**:
   - `ip route show` でデフォルトルート欠如を確認
   - EC2から外部への `ping` 失敗
   - セキュリティグループ設定は正常
3. **Evidence**:
   - AWSドキュメントでRoute Tableの動作確認
   - 観測データとドキュメントを比較
4. **Root Cause**: Route Tableのデフォルトルート（0.0.0.0/0）がIGWに向いていない
5. **Verify**:
   - `aws ec2 describe-route-tables` でRoute Table設定を確認
   - AWSコンソールでRoute Tableを確認

このPowerは観測と分析のみを行い、実際の修復操作はユーザーが行うことを前提としています。