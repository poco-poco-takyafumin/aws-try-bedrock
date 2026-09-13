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

variable "environment" {
  description = "環境識別子（poc / prod 等）。タグにのみ使用する。"
  type        = string
  default     = "poc"
}

variable "budget_alert_email" {
  description = "AWSアカウント全体の請求アラームの通知先メールアドレス。"
  type        = string
}

variable "account_billing_alarm_threshold_usd" {
  description = "AWSアカウント全体の推定請求額アラームのしきい値（USD）。Bedrock以外の全サービス合算。"
  type        = number
  default     = 10
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Scope       = "account-shared"
  }

  # アカウント共通リソースの命名プレフィックス。ユースケース名を含めない
  # （docs/00-architecture-overview.md 0章: アカウント×リージョン単位のシングルトンリソースは
  # ユースケースごとに重複作成せず、共有Terraformとして1箇所で管理する）。
  name_prefix = "bedrock"
}
