variable "aws_region" {
  description = "デプロイ先リージョン。docs/00-architecture-overview.mdの方針により東京リージョンを基本とする。"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "リソース命名・タグ付けに使うプロジェクト名。"
  type        = string
  default     = "aws-try-bedrock"
}

variable "use_case_name" {
  description = "ユースケース識別子（docs/配下のディレクトリ名と一致させる）。コスト配分タグ・命名にも使う。"
  type        = string
  default     = "01-internal-rag-chatbot"
}

variable "environment" {
  description = <<-EOT
    環境識別子（poc / prod 等）。タグ（local.common_tags）にのみ使用する。
    local.name_prefix（リソース名の素材）には含めていない — 理由はlocal.name_prefixの
    コメントを参照（AWS側の名前長制約により、現状は1アカウント=1環境が前提）。
  EOT
  type        = string
  default     = "poc"
}

variable "app_runtime_role_name" {
  description = "このユースケース専用のAppRuntime IAMロール名（requirements.mdで確定済み）。"
  type        = string
  default     = "bedrock-appruntime-internal-rag-chatbot"
}

variable "anthropic_model_id" {
  description = <<-EOT
    jp.anthropic.* 推論プロファイル経由で呼び出すAnthropicモデルID（リージョンプレフィックスなしのベースID）。
    Bedrockのモデルカタログは変動するため、apply前に `aws bedrock list-inference-profiles --region ap-northeast-1`
    等で実際に利用可能な jp.anthropic.* プロファイルIDを確認し、必要なら上書きすること（人間レビュー対象）。
  EOT
  type        = string
  default     = "claude-sonnet-4-5-20250929-v1:0" # 要最新確認。プレースホルダー。
}

variable "kb_embedding_model_id" {
  description = "Knowledge Base埋め込み用モデルID（生成側のjp.anthropic.*とは別軸）。"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "gdrive_sync_folder_id_parameter_default" {
  description = <<-EOT
    SSM Parameter Store（String）に格納する同期対象Google DriveフォルダIDの初期値。
    実際の値は機密ではないが運用中に変更されうるため、terraform管理下に置きつつ
    Parameter Store経由でLambdaに渡す（コード変更・再デプロイなしで変更可能にする）。
  EOT
  type        = string
  default     = "REPLACE_WITH_ACTUAL_FOLDER_ID"
}

variable "gdrive_sync_impersonate_user_parameter_default" {
  description = <<-EOT
    ドメイン全体委譲でなりすます対象ユーザー（Google Workspaceのメールアドレス。
    通常は同期対象フォルダの所有者）の初期値。フォルダIDと同様に非機密だが運用中に
    変更されうるため、SSM Parameter Store（String）経由でLambdaに渡す
    （google-setup.md 手順6と同様の運用）。
  EOT
  type        = string
  default     = "REPLACE_WITH_ACTUAL_IMPERSONATE_USER_EMAIL"
}

variable "budget_alert_email" {
  description = "AWS Budgets（Bedrock予算）アラートの通知先メールアドレス。アカウント全体の請求アラームは別途 infra/ で管理する。"
  type        = string
}

variable "monthly_budget_limit_usd" {
  description = "Bedrockサービスの月次予算上限（USD）。"
  type        = number
  default     = 5
}

variable "log_retention_days" {
  description = <<-EOT
    全ロググループ共通のCloudWatch Logs保持日数。
    レビュー指摘対応: 以前はmodule.loggingにのみ明示的に365を渡し、
    backend/gdrive_syncは各モジュールの既定値(90日)に暗黙にフォールバックしていて
    監査要件（365日保持）との間に無自覚な乖離があった。ルートで一元管理する。
  EOT
  type        = number
  default     = 365
}

locals {
  common_tags = {
    Project     = var.project_name
    UseCase     = var.use_case_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # OpenSearch Serverlessのコレクション名（32文字上限）やBedrock Guardrail名（50文字上限）、
  # IAMロール名の上限（64文字、AWS側の固定プレフィックスと連結されるケースあり）等、
  # 名前長に厳しい制約を持つAWSリソースが多いため、素材名は短縮形にする
  # （project_name+use_case_nameをそのまま連結すると40文字になり、これらの上限を圧迫するため）。
  #
  # レビュー指摘対応（既知の制限・意図的な設計判断）: var.environmentをここに含めていない。
  # 含めると、既に余裕がほぼないKnowledge Base実行ロール名
  # （"AmazonBedrockExecutionRoleForKnowledgeBase_" + kb_name ≤ 64文字、kb_name自体の
  # 予算は20文字前後）やOpenSearch Serverlessコレクション名（32文字上限）の制約を
  # 容易に超えてしまう。そのため現状は「1 AWSアカウント = 1環境」を前提とした設計とする。
  # 複数環境（poc/prod等）を同一アカウントに同時展開する必要が生じた場合は、
  # 単純にenvironmentを連結するのではなく、命名の短縮方針自体を見直すこと
  # （未決事項としてrequirements.mdに追記済み）。
  name_prefix = "bedrock-rag01"
}
