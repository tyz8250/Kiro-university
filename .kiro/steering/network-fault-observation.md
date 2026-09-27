---
inclusion: auto
name: Network Fault Observation System
description: AWS Network Fault Observation Experiment System - Terraform + EC2 + Docker + Go
---

# Network Fault Observation System

## プロジェクト概要

AWS上で動作するネットワーク障害観測実験システム。外部からのHTTPリクエストをEC2上のGoサーバーで受信し、ネットワーク障害（Internet Gatewayへの経路削除）を発生させて観測することで、AWSネットワークの振る舞いを可視化する。

### 実験対象: Experiment 1

- **目的**: Default Route（0.0.0.0/0）の削除によるEC2のInternet Gatewayへの到達性を検証する
- **観測対象**: Macからのcurl、EC2上のtcpdump、Dockerコンテナ状態、Goサーバーログ
- **成功条件**: 障害注入後にHTTPリクエストがタイムアウトまたは接続エラーとなり、Default Route復元後に再びHTTP 200を確認できること

## 技術スタック

| レイヤー | 技術 |
|---------|------|
| インフラ | Terraform |
| コンピューティング | EC2 (Amazon Linux 2) |
| コンテナ | Docker |
| アプリケーション | Go 1.22 |
| テスト | pgregory.net/rapid (プロパティベーステスト) |

## 実験フロー

```
[Baseline] → [Break] → [Observe] → [Restore] → [Record]
```

1. **Baseline**: 正常時の各観測点（Mac curl, tcpdump, Docker, Goログ）を記録
2. **Break**: Default Routeを削除してネットワーク遮断
3. **Observe**: Macからcurlを実行し、タイムアウトまたは接続エラーを確認
4. **Restore**: Default Routeを復元
5. **Record**: 復元後の観測データを回収・比較レポート作成

## ディレクトリ構成

```
Kiro-university/
├── infra/          # Terraform インフラ定義
├── app/            # Go HTTPサーバー + テスト
├── scripts/        # 実験自動化スクリプト
├── results/        # 実験結果出力
└── .kiro/          # Kiro設定
    ├── steering/   # 本ファイル
    ├── specs/      # 仕様・タスク定義
    └── hooks/      # 自動化フック
```

## Trace ID 仕様

### 形式

- **UUID v4 ベース**: ランダム生成
- **パターン**: `[A-Za-z0-9\-_]{1,64}` (1〜64文字)
- **最大長**: 64文字 (65文字以降は invalid)

### HTTP伝搬

- **ヘッダー名**: `X-Trace-ID`
- **伝搬フロー**: 
  1. リクエスト受信時にヘッダーをチェック
  2. 存在しない場合は自動生成（UUID v4）
  3. バリデーション失敗時は HTTP 400 を返却
  4. レスポンスヘッダーにも `X-Trace-ID` を設定

### バリデーションルール

- 空文字は invalid
- 65文字以上は invalid
- `[A-Za-z0-9\-_]` 以外の文字を含む場合は invalid
