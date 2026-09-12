# インフラ実装（Phase A: インフラ骨格）

`../requirements.md` の要件確定内容をもとにしたTerraform実装。土台リポジトリは
[`aws-samples/sample-bedrock-knowledge-base-terraform`](https://github.com/aws-samples/sample-bedrock-knowledge-base-terraform)
（`modules/knowledge_base/` に移植・改修して取り込み済み）。

## スコープ

**Phase A（本実装）**: インフラ骨格一式をTerraformコードとして用意。`terraform apply`は未実施。
**Phase B（別セッション予定）**: `modules/gdrive_sync` と `modules/backend` の中身（Python実装本体）。
現状はどちらもプレースホルダーハンドラー（`src/handler.py`、501を返すだけ）。

## ★人間レビュー必須モジュール（CLAUDE.mdより）

`terraform apply` 前に必ず `terraform plan` の差分を人間がレビューすること:

| モジュール | 該当理由 |
|---|---|
| `modules/iam` | IAMポリシー・ロールの新規作成/変更（`bedrock:InvokeModel`系アクションの許可範囲） |
| `modules/guardrails` | Guardrailsの設定内容（Content filters・PII filters・Contextual grounding） |
| `modules/logging` | ログ出力先（S3バケットポリシー・KMSキー・CloudWatch Logsアクセス権限） |
| `modules/cost` | コスト管理設定（Budgetsしきい値・Application Inference Profileのタグ付け） |
| `billing_alarm.tf`（ルート） | コスト管理設定（アカウント全体のCloudWatch請求アラーム） |

## 既知の構成リスク・要判断事項

- **OpenSearch Serverless network policyが`AllowFromPublic = true`**（土台リポジトリのデフォルト継承）。
  アクセス制御はdata policyのprincipal限定で担保しており、VPC化はしていない。許容可否は実装レビュー時に判断する
- **`aws_bedrock_model_invocation_logging_configuration`はアカウント×リージョン単位のシングルトン設定**。
  複数ユースケース(02, 03)を同一AWSアカウントに展開する場合、後から適用した方の設定で上書きされる。
  `docs/00-architecture-overview.md`の未決事項「アカウント分離するか」が解決するまでは、
  2つ目以降のユースケースでこのリソースを重複適用しないよう注意すること
- **Admin/Developer/Auditorロールはユースケース名を含めた暫定命名**にしている（本来はアカウント共通の型）。
  アカウント分離しない方針が確定したら、共通moduleへのリファクタリングが必要
- `var.anthropic_model_id`（jp.anthropic.*推論プロファイルのモデルID）はプレースホルダー値。
  apply前に `aws bedrock list-inference-profiles --region ap-northeast-1` 等で実在するIDに置き換えること
- **`billing_alarm.tf`のアカウント全体請求アラームはユースケース横断の共通リソース**。複数ユースケースを
  同一アカウントで運用する場合、02/03側では重複適用しないこと。また、apply前にAWS Billingコンソールで
  「請求アラートを受け取る」を手動で有効化しておく必要がある（Terraformでは自動化不可）

## デプロイ手順

```bash
cd docs/01-internal-rag-chatbot/infra

# Google Workspace側の準備を先に行う（google-setup.md参照、手順1〜4）

terraform init
terraform fmt -recursive
terraform validate

# 変数を設定（terraform.tfvars等）
#   budget_alert_email = "you@example.com"
#   anthropic_model_id = "<実在するモデルIDに置き換え>"

terraform plan -out=tfplan
# ↑ このplan出力の差分を、上記「人間レビュー必須モジュール」について必ず確認する

terraform apply tfplan

# apply後、google-setup.md の手順5・6に従いシークレット・パラメータを登録する
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
│   ├── iam/              # Admin/Developer/AppRuntime/Auditorロール
│   ├── guardrails/        # Bedrock Guardrail
│   ├── logging/            # CloudTrail + Model invocation logging + CloudWatch Logs data protection
│   ├── cost/                # AWS Budgets + Application Inference Profile
│   ├── gdrive_sync/         # Google Drive同期Lambda（箱のみ、中身はPhase B）
│   └── backend/             # API Gateway + チャットバックエンドLambda（箱のみ、中身はPhase B）
```

## 検証方法（このセッションで実施したこと）

AWS認証情報が構成されていない前提のため、以下のみ実施した:

- `terraform fmt -recursive`
- `terraform init -backend=false` + `terraform validate`

`terraform plan` / `apply` はAWS認証情報がある環境で、上記の人間レビュー必須モジュールの
diffを確認した上で実行すること。
