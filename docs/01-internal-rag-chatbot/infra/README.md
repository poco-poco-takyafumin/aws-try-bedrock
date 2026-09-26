# インフラ実装（Phase A: インフラ骨格）

`../requirements.md` の要件確定内容をもとにしたTerraform実装。土台リポジトリは
[`aws-samples/sample-bedrock-knowledge-base-terraform`](https://github.com/aws-samples/sample-bedrock-knowledge-base-terraform)
（`modules/knowledge_base/` に移植・改修して取り込み済み）。

## スコープ

**Phase A（完了）**: インフラ骨格一式をTerraformコードとして用意し、`terraform apply`済み（2026-09-21）。
**Phase B（進行中、issue [#7](https://github.com/poco-poco-takyafumin/aws-try-bedrock/issues/7)）**: `modules/gdrive_sync` と
`modules/backend` の中身（Python実装本体）。進捗はリポジトリ直下の[README.md](../../../README.md#01-社内ragチャットボット--phase-b-todo)のTODOを参照。

- **2026-09-23、方針転換**: Google Drive連携は後回しにし、まずS3への手動アップロードでRAGパイプライン
  本体の動作確認を優先する（`requirements.md`の「データソース方針の見直し」参照）
- `modules/gdrive_sync`: サービスアカウント認証・S3同期ロジックは実装済み（B-1、[PR #8](https://github.com/poco-poco-takyafumin/aws-try-bedrock/pull/8)）だが、上記方針転換によりマージ・apply未実施のまま保留
- `modules/backend`: 引き続きプレースホルダーハンドラー（`src/handler.py`、501を返すだけ）。B-3で実装予定

## ★人間レビュー必須モジュール（CLAUDE.mdより）

`terraform apply` 前に必ず `terraform plan` の差分を人間がレビューすること:

| モジュール | 該当理由 |
|---|---|
| `modules/iam` | IAMポリシー・ロールの新規作成/変更（`bedrock:InvokeModel`系アクションの許可範囲） |
| `modules/guardrails` | Guardrailsの設定内容（Content filters・PII filters・Contextual grounding） |
| `modules/logging` | ログ出力先（S3バケットポリシー・KMSキー・CloudWatch Logsアクセス権限） |
| `modules/cost` | コスト管理設定（Budgetsしきい値・Application Inference Profileのタグ付け） |

アカウント全体の請求アラーム（旧`billing_alarm.tf`）とCost allocation tagの有効化
（旧`modules/cost`内`aws_ce_cost_allocation_tag`）は、リポジトリ直下の [`infra/`](../../../infra/README.md)
（アカウント共通Terraform）に切り出し済み（[#1](https://github.com/poco-poco-takyafumin/aws-try-bedrock/issues/1)）。
このユースケースのTerraformとは依存関係を持たない自己完結型リソースのため、参照の配線は不要。

## 既知の構成リスク・要判断事項

- **OpenSearch Serverless network policyが`AllowFromPublic = true`**（土台リポジトリのデフォルト継承）。
  アクセス制御はdata policyのprincipal限定で担保しており、VPC化はしていない。許容可否は実装レビュー時に判断する
- **`aws_bedrock_model_invocation_logging_configuration`はアカウント×リージョン単位のシングルトン設定**。
  複数ユースケース(02, 03)を同一AWSアカウントに展開する場合、後から適用した方の設定で上書きされる。
  `docs/00-architecture-overview.md`の未決事項「アカウント分離するか」が解決するまでは、
  2つ目以降のユースケースでこのリソースを重複適用しないよう注意すること
- **Admin/Developer/Auditorロールはユースケース名を含めた暫定命名**にしている（本来はアカウント共通の型）。
  共通moduleへのリファクタリングは[#2](https://github.com/poco-poco-takyafumin/aws-try-bedrock/issues/2)で設計中
- `var.anthropic_model_id`（jp.anthropic.*推論プロファイルのモデルID）はプレースホルダー値。
  apply前に `aws bedrock list-inference-profiles --region ap-northeast-1` 等で実在するIDに置き換えること
- **Model invocation loggingのS3宛出力は未マスクPIIを含む**（コードレビューで指摘）。CloudWatch Logs
  data protectionはCloudWatch Logs宛のみに効く機能で、S3宛オブジェクトの同等の自動マスキング機能は
  AWSに存在しない。緩和策はS3読み取りをAuditorロールに限定することのみ（`requirements.md`未決事項参照）
- **`modules/backend`のAPI GatewayルートはPhase A時点では暫定的にAWS_IAM認証**。
  Phase BのB-4で **APIキー方式** に置き換える方針を決定済み（`requirements.md`参照）
- **`modules/knowledge_base/opensearch.tf`のprovider "opensearch"ブロックは既知のTerraform制約**を持つ。
  初回applyでエラーになる場合は下記デプロイ手順の2段階apply対応を参照

## デプロイ手順

アカウント共通リソース（請求アラーム・Cost allocation tag）は先にリポジトリ直下の
[`infra/`](../../../infra/README.md)でapply済みにしておくこと（このユースケースのTerraformからの
参照はないが、アカウント設定として先に揃えておくのが望ましい）。

```bash
cd docs/01-internal-rag-chatbot/infra

# Phase Bの現行方針では、まずS3へ文書を手動アップロードして動作確認する
# Google Drive同期を導入する段階になったら、google-setup.md の手順1〜4を先に行う

terraform init
terraform fmt -recursive
terraform validate

# 変数を設定（terraform.tfvars等）
#   budget_alert_email = "you@example.com"
#   anthropic_model_id = "<実在するモデルIDに置き換え>"

terraform plan -out=tfplan
# ↑ このplan出力の差分を、上記「人間レビュー必須モジュール」について必ず確認する

terraform apply tfplan
# ↑ 初回applyで「provider configuration value depends on resource attributes」相当の
#   エラーが出た場合（modules/knowledge_base/opensearch.tfの既知の制約）は、
#   先に以下でOpenSearch Serverlessコレクションだけ作成してから再度applyする:
#   terraform apply -target=module.knowledge_base.aws_opensearchserverless_collection.resource_kb
#   terraform apply

# Google Drive同期を導入する段階になったら、google-setup.md の手順5・6に従い
# シークレット・パラメータを登録する
```

## タグ付け方針

`provider "aws" { default_tags { ... } }`（`providers.tf`）により、Terraformで作成する全リソースに
`Project` / `UseCase` / `Environment` / `ManagedBy` タグを自動付与する。加えて `modules/cost` の
Application Inference Profileには `CostCenter` タグを付与し、Cost Explorerでユースケース単位に
コストを絞り込めるようにしている（要Cost Explorer側でのコスト配分タグのアクティブ化）。

## ディレクトリ構成

```
infra/
├── providers.tf / variables.tf / outputs.tf / main.tf / s3.tf / kms.tf
├── google-setup.md      # Google Workspace側の手順書
├── modules/
│   ├── knowledge_base/  # S3データソース + OpenSearch Serverless + Knowledge Base（土台リポジトリ移植）
│   ├── iam/              # Developer/AppRuntime/Auditorロール
│   ├── iam_admin/         # Adminロール（knowledge_baseとの循環依存を避けるため独立moduleに分離）
│   ├── guardrails/        # Bedrock Guardrail
│   ├── logging/            # CloudTrail + Model invocation logging + CloudWatch Logs data protection
│   ├── cost/                # AWS Budgets + Application Inference Profile
│   ├── gdrive_sync/         # Google Drive同期Lambda（箱のみ、中身はPhase B）
│   └── backend/             # API Gateway + チャットバックエンドLambda（箱のみ、中身はPhase B）
```

## 検証方法

- `terraform fmt -recursive`
- `terraform init -backend=false` + `terraform validate`
- `terraform plan` / `apply`: 人間レビュー必須モジュールのdiffを確認した上で実施済み（2026-09-21、apply成功）

再applyする場合も、上記の人間レビュー必須モジュールのdiffを確認した上で実行すること。
