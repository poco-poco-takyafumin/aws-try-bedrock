variable "name_prefix" {
  type = string
}

variable "auditor_role_arn" {
  description = "ログ閲覧を許可するAuditorロールのARN（modules/iamの出力）。"
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
