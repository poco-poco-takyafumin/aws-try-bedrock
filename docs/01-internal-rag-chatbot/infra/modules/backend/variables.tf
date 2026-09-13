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

variable "guardrail_arn" {
  description = <<-EOT
    GuardrailのARN（IDではなくARN）。modules/iamのAppRuntimeロールのIAM Condition
    (bedrock:GuardrailIdentifier) がARNと比較しているため、アプリ側もARNを渡して
    一致させる必要がある（レビュー指摘対応: 以前はIDのみ渡しておりIAM Denyと不一致だった）。
  EOT
  type        = string
}

variable "guardrail_version" {
  type = string
}

variable "developer_role_name" {
  description = <<-EOT
    modules/iamのDeveloperロール名。API GatewayのAWS_IAM認証ルートに対する
    execute-api:Invoke権限を付与し、検証目的の呼び出しができるようにするために使う。
    レビュー指摘対応: 以前はauthorization_type = "AWS_IAM"を設定しただけで、
    execute-api:Invokeを許可するIAMポリシーがリポジトリ内に一つも存在せず、
    SigV4署名で正しく認証してもAccessDeniedになり誰も呼び出せない状態だった。
  EOT
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
