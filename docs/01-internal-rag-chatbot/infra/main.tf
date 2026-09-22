data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}

locals {
  # jp.anthropic.* JP Geo推論プロファイル（システム定義）のARN。
  # requirements.md確定: データ主権優先のためjp.anthropic.*を採用（global.*は不採用）。
  jp_anthropic_system_profile_arn = "arn:${data.aws_partition.this.partition}:bedrock:${var.aws_region}:${data.aws_caller_identity.this.account_id}:inference-profile/jp.anthropic.${var.anthropic_model_id}"
}

# modules/knowledge_baseが必要とするadmin_principal_arnをmodules/iam（developer等）より
# 先に、かつmodules/knowledge_baseに依存しない形で確定させるため独立モジュールに分離している
# （modules/iam_admin側のコメント参照。循環依存の手組みARN回避）。
module "iam_admin" {
  source = "./modules/iam_admin"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

module "knowledge_base" {
  source = "./modules/knowledge_base"

  kb_name                = "${local.name_prefix}-kb"
  kb_s3_bucket_name      = aws_s3_bucket.kb_data.bucket
  kb_kms_key_arn         = aws_kms_key.kb_data.arn
  kb_oss_collection_name = "${local.name_prefix}-oss"
  kb_model_id            = var.kb_embedding_model_id
  vector_dimension       = 1024
  chunking_strategy      = "DEFAULT"
  admin_principal_arn    = module.iam_admin.admin_role_arn
  tags                   = local.common_tags
}

module "guardrails" {
  source = "./modules/guardrails"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

module "cost" {
  source = "./modules/cost"

  name_prefix                  = local.name_prefix
  use_case_name                = var.use_case_name
  system_inference_profile_arn = local.jp_anthropic_system_profile_arn
  monthly_budget_limit_usd     = var.monthly_budget_limit_usd
  budget_alert_email           = var.budget_alert_email
  tags                         = local.common_tags
}

module "iam" {
  source = "./modules/iam"

  name_prefix           = local.name_prefix
  app_runtime_role_name = var.app_runtime_role_name
  knowledge_base_arn    = module.knowledge_base.knowledge_base_arn
  guardrail_arn         = module.guardrails.guardrail_arn
  guardrail_version     = module.guardrails.guardrail_version
  # レビュー指摘対応: 基盤モデルARNを直接許可すると、コストタグ付きの
  # Application Inference Profileを経由しない呼び出しが可能になり、コスト配分・
  # jp.anthropic.*限定の両方を迂回できてしまうため、推論プロファイル経由のみ許可する。
  inference_profile_arns = [module.cost.inference_profile_arn, local.jp_anthropic_system_profile_arn]
  tags                   = local.common_tags
}

module "logging" {
  source = "./modules/logging"

  name_prefix        = local.name_prefix
  auditor_role_arn   = module.iam.auditor_role_arn
  auditor_role_name  = module.iam.auditor_role_name
  admin_role_name    = module.iam_admin.admin_role_name
  log_retention_days = var.log_retention_days
  tags               = local.common_tags
}

module "gdrive_sync" {
  source = "./modules/gdrive_sync"

  name_prefix                     = local.name_prefix
  kb_bucket_name                  = aws_s3_bucket.kb_data.bucket
  kb_bucket_arn                   = aws_s3_bucket.kb_data.arn
  kb_kms_key_arn                  = aws_kms_key.kb_data.arn
  gdrive_folder_id_default        = var.gdrive_sync_folder_id_parameter_default
  gdrive_impersonate_user_default = var.gdrive_sync_impersonate_user_parameter_default
  log_retention_days              = var.log_retention_days
  tags                            = local.common_tags
}

module "backend" {
  source = "./modules/backend"

  name_prefix           = local.name_prefix
  app_runtime_role_arn  = module.iam.app_runtime_role_arn
  developer_role_name   = module.iam.developer_role_name
  knowledge_base_id     = module.knowledge_base.knowledge_base_id
  inference_profile_arn = module.cost.inference_profile_arn
  guardrail_arn         = module.guardrails.guardrail_arn
  guardrail_version     = module.guardrails.guardrail_version
  log_retention_days    = var.log_retention_days
  tags                  = local.common_tags
}
