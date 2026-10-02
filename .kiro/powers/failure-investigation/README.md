# failure-investigation Power

## 目的

`failure-investigation` は、AWS上のネットワーク障害を調査するためのKiro Custom Powerです。調査は次の順序で進めます。

> Hypothesis → Observe → Evidence → Root Cause → Verify

観測結果を整理し、AWS公式ドキュメントと照合して原因候補と追加の確認方法を提示します。安全のため、障害の自動修復は行いません。

## パッケージ構成

```text
failure-investigation/
├── plugin.json
├── mcp.json
└── skills/
    └── investigate-network-failure/
        └── SKILL.md
```

### 各ファイルの役割

- `plugin.json`: Powerの名前、バージョン、Description、作者、キーワードなどのメタデータを定義するマニフェストです。
- `mcp.json`: AWS Documentation MCPを`aws-docs`という名前で登録し、`uvx`を使って起動する設定です。
- `skills/investigate-network-failure/SKILL.md`: 調査の発火条件、5段階の調査手順、利用する証拠、安全上の禁止事項、報告形式を定義します。

## 前提条件

- KiroでCustom Powerを利用できること
- `uvx`コマンドが利用可能であること
- `uvx awslabs.aws-documentation-mcp-server@latest`によりAWS Documentation MCPを起動できること
- MCPパッケージの取得やAWS公式ドキュメントの参照に必要なネットワーク接続があること

## 別プロジェクトへの再利用手順

1. `.kiro/powers/failure-investigation`ディレクトリ全体を、再利用先から参照できる場所へコピーします。配下の構成を変更せず、`plugin.json`を含む`failure-investigation`フォルダとしてコピーしてください。
2. KiroのPowers画面を開き、`Add Custom Power`を選択します。
3. `Import power from a folder`を選択します。
4. コピーした`failure-investigation`フォルダを選択します。
5. `Install`を実行します。
6. `Try power`からサンプルプロンプトを入力し、Powerが発火することを確認します。

## 正常確認

インストール後は、次のすべてを確認してください。

- PowerのDescriptionにネットワーク障害調査用であることが表示される
- Skills欄に`investigate-network-failure`が表示される
- `Component Issues`が表示されていない
- `aws-docs` MCPが利用可能になっている
- `Try power`で調査フローに沿った応答が返り、自動修復が実行されない

## サンプル利用プロンプト

```text
AWSのRoute Tableから「0.0.0.0/0 → Internet Gateway (IGW)」の経路を削除したところ、
外部からEC2上のGo Serverへ接続できなくなりました。

Hypothesis → Observe → Evidence → Root Cause → Verify の順で、
Route Table、Internet Gateway、Security Group、Dockerのポート公開、Go Serverのログを調査してください。
AWS公式ドキュメントと観測結果を照合し、原因候補と次に人間が確認すべき内容を報告してください。

調査のみを行い、自動修復はしないでください。
terraform apply / destroy、Docker stop / rm、ファイル書き込み、AWSリソース変更は実行しないでください。
```

## 安全上の制約

このPowerは観測と分析に限定します。次の操作を自動実行してはいけません。

- `terraform apply`
- `terraform destroy`
- `docker stop`および`docker rm`
- ファイルの作成、変更、削除などの書き込み
- AWSリソースの作成、変更、削除

修復が必要な場合は、根拠と推奨する確認手順を提示し、実際の変更は人間の判断と操作に委ねます。

## トラブルシューティング

### `plugin.json has an unsupported or missing $schema`

`plugin.json`の先頭に、対応するスキーマが正確に指定されているか確認します。このPowerでは次の値を使用しています。

```json
"$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
```

URLのタイプミス、`$schema`キーの欠落、別バージョンの形式との混在がないか確認してください。

### `SKILL.md has no frontmatter block`

`skills/investigate-network-failure/SKILL.md`のファイル先頭に、`---`で囲まれたYAML frontmatterがあるか確認します。このPowerでは`name: investigate-network-failure`と`description`を定義しています。frontmatterより前に本文やコードフェンスを置かないでください。

### `mcp.json has an unsupported or missing $schema`

`mcp.json`の先頭に、対応するスキーマが正確に指定されているか確認します。このPowerでは次の値を使用しています。

```json
"$schema": "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json"
```

スキーマが正しくてもMCPを起動できない場合は、`uvx`がPATH上にあること、パッケージを取得できること、`awslabs.aws-documentation-mcp-server@latest`を起動できることを確認してください。

### 修正内容が反映されない

Powerを修正しても、Kiroに古いinstalled copyが残る場合があります。その場合は、対象Powerを一度`Uninstall`し、`Add Custom Power` → `Import power from a folder`から修正済みフォルダを再Importして、改めて`Install`してください。その後、`Component Issues`と各コンポーネントの表示を再確認します。

## 注意事項

- PowerがInstalled一覧に表示されることと、すべてのコンポーネントが正常にロードされることは別です。必ず`Component Issues`を確認してください。
- 動作確認では、Power自体が発火したのか、`SKILL.md`だけを直接読ませたのかを区別してください。再利用確認にはPowers画面の`Try power`を使用します。
- 調査結果に修復案が含まれていても、それは人間が判断するための提案です。このPower自身に変更操作を実行させないでください。
