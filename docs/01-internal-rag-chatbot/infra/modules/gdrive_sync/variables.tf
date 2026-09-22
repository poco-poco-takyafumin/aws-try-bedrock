variable "name_prefix" {
  type = string
}

variable "kb_bucket_name" {
  description = "同期先（Knowledge BaseデータソースS3バケット名）。"
  type        = string
}

variable "kb_bucket_arn" {
  type = string
}

variable "kb_kms_key_arn" {
  description = "KBバケットの暗号化に使うKMSキーARN（Lambdaに復号・暗号化権限を付与するため）。"
  type        = string
}

variable "gdrive_folder_id_default" {
  type = string
}

variable "gdrive_impersonate_user_default" {
  description = "ドメイン全体委譲でなりすます対象ユーザー（Google Workspaceのメールアドレス）の初期値。"
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}
