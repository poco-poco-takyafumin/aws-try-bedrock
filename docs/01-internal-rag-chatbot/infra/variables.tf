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
  description = "環境識別子（poc / prod 等）。"
  type        = string
  default     = "poc"
}

variable "app_runtime_role_name" {
  description = "このユースケース専用のAppRuntime IAMロール名（requirements.mdで確定済み）。"
  type        = string
  default     = "bedrock-approntime-internal-rag-chatbot"
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

variable "budget_alert_email" {
  description = "AWS Budgetsアラートの通知先メールアドレス。"
  type        = string
}

variable "monthly_budget_limit_usd" {
  description = "Bedrockサービスの月次予算上限（USD）。"
  type        = number
  default     = 5
}

variable "account_billing_alarm_threshold_usd" {
  description = "AWSアカウント全体の推定請求額アラームのしきい値（USD）。Bedrock以外の全サービス合算。"
  type        = number
  default     = 10
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
  name_prefix = "bedrock-rag01"
}
