variable "name_prefix" {
  type = string
}

variable "auditor_role_arn" {
  description = "ログ閲覧を許可するAuditorロールのARN（modules/iamの出力）。"
  type        = string
  default     = null
}

variable "admin_role_name" {
  description = <<-EOT
    Adminロール名（modules/iamの出力）。ログバケットのバケットポリシー変更権限
    （s3:GetBucketPolicy/PutBucketPolicy）をこのバケットに限定して付与するために使う。
    レビュー指摘対応: 以前はmodules/iam側でResource="*"（全バケット）に付与しており、
    ログバケット以外（KBデータバケット等）まで書き換え可能だった。
  EOT
  type        = string
  default     = null
}

variable "auditor_role_name" {
  description = <<-EOT
    Auditorロール名（modules/iamの出力）。ログ用KMSキーへのkms:Decrypt権限を
    インラインポリシーとして付与するために使う（aws_iam_role_policyはロール名を要求するため）。
    レビュー指摘対応: 以前はS3バケットポリシーでの読み取り許可のみで、KMS復号権限が
    欠落しておりAuditorがログを読めなかった。
  EOT
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch Logsの保持日数。"
  type        = number
  default     = 365
}

variable "tags" {
  type    = map(string)
  default = {}
}
