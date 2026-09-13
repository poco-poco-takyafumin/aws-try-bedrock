# aws-samples/sample-bedrock-knowledge-base-terraform の modules/variables.tf を土台に、
# このユースケース向けにデフォルト値・変数名を整理したもの。

variable "kb_model_id" {
  description = "Knowledge Baseの埋め込みモデルID。"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "kb_name" {
  description = "Knowledge Base名。"
  type        = string
}

variable "kb_s3_bucket_name" {
  description = "データソースとして使う既存S3バケット名（ルートモジュールでs3.tfにより作成済み）。"
  type        = string
}

variable "kb_kms_key_arn" {
  description = <<-EOT
    KBデータS3バケットの暗号化に使うKMSキーARN（ルートのkms.tf）。
    バケットはSSE-KMSで暗号化されているため、KB実行ロールにもkms:Decrypt権限が必要
    （レビュー指摘対応: 以前はこの権限が欠落しており取り込みがAccessDeniedになっていた）。
  EOT
  type        = string
}

variable "kb_oss_collection_name" {
  description = "OpenSearch Serverlessコレクション名。"
  type        = string
}

variable "admin_principal_arn" {
  description = <<-EOT
    OpenSearch Serverlessのdata access policyに管理アクセスを許可する管理者ロールのARN。
    レビュー指摘対応: 以前はdata.aws_caller_identity.this.arn（apply実行者の一時的な
    STS assumed-roleセッションARN）を使っており、SSO再ログインやCI実行のたびにARNが
    変わって以前のapplyで許可した対象と一致しなくなる問題があった。安定したIAMロールARN
    （modules/iamのAdminロール）を渡すことで解消する。
  EOT
  type        = string
}

variable "vector_dimension" {
  description = "埋め込みベクトルの次元数。"
  type        = number
  default     = 1024
}

variable "chunking_strategy" {
  type        = string
  description = "チャンク分割戦略（DEFAULT, FIXED_SIZE, HIERARCHICAL, SEMANTIC, NONE）。"
  default     = "DEFAULT"
  validation {
    condition     = contains(["DEFAULT", "FIXED_SIZE", "HIERARCHICAL", "SEMANTIC", "NONE"], var.chunking_strategy)
    error_message = "chunking_strategy must be one of: DEFAULT, FIXED_SIZE, HIERARCHICAL, SEMANTIC, NONE"
  }
}

variable "fixed_size_max_tokens" {
  type    = number
  default = 512
}

variable "fixed_size_overlap_percentage" {
  type    = number
  default = 20
}

variable "hierarchical_overlap_tokens" {
  type    = number
  default = 70
}

variable "hierarchical_parent_max_tokens" {
  type    = number
  default = 1000
}

variable "hierarchical_child_max_tokens" {
  type    = number
  default = 500
}

variable "semantic_max_tokens" {
  type    = number
  default = 512
}

variable "semantic_buffer_size" {
  type    = number
  default = 1
}

variable "semantic_breakpoint_percentile_threshold" {
  type    = number
  default = 75
}

variable "tags" {
  description = "追加タグ（provider default_tagsに加えて付与する場合）。"
  type        = map(string)
  default     = {}
}
