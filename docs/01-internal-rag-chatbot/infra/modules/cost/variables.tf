variable "name_prefix" {
  type = string
}

variable "use_case_name" {
  type = string
}

variable "system_inference_profile_arn" {
  description = "コストタグ付与元となるjp.anthropic.*システム定義推論プロファイルのARN。"
  type        = string
}

variable "monthly_budget_limit_usd" {
  description = "Bedrockサービスの月次予算上限（USD）。"
  type        = number
  default     = 50
}

variable "budget_alert_thresholds_percent" {
  description = "予算のうち何%消化した時点でアラートするか（複数指定可）。"
  type        = list(number)
  default     = [50, 80, 100]
}

variable "budget_alert_email" {
  description = "予算アラートの通知先メールアドレス。"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
