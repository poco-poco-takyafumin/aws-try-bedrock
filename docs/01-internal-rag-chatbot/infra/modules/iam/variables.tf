variable "name_prefix" {
  type = string
}

variable "app_runtime_role_name" {
  type = string
}

variable "knowledge_base_arn" {
  type = string
}

variable "guardrail_arn" {
  type = string
}

variable "guardrail_version" {
  type = string
}

variable "inference_profile_arns" {
  description = <<-EOT
    InvokeModelの許可対象とする推論プロファイルARNのリスト。
    コストタグ付けのため実際の呼び出しはmodules/costで作成したApplication Inference Profile
    (カスタム)を使うが、その裏側であるjp.anthropic.*システム定義プロファイルにも
    IAM許可が必要になるケースがあるため両方を含める。
  EOT
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
