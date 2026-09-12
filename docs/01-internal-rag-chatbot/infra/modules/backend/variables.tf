variable "name_prefix" {
  type = string
}

variable "app_runtime_role_arn" {
  description = "modules/iamで作成したAppRuntimeロールのARN（このLambdaの実行ロールとして使う）。"
  type        = string
}

variable "knowledge_base_id" {
  type = string
}

variable "inference_profile_arn" {
  type = string
}

variable "guardrail_id" {
  type = string
}

variable "guardrail_version" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}
