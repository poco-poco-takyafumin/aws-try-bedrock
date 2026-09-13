# ============================================================================
# ★人間レビュー必須モジュール★ (CLAUDE.md: コスト管理設定)
# ============================================================================

# ユースケース単位のコストタグ分離用 Application Inference Profile。
# jp.anthropic.* システム定義プロファイルをラップし、UseCase/CostCenterタグを付与することで
# Cost Explorer上でこのユースケースのBedrock利用コストのみを集計できるようにする。
resource "aws_bedrock_inference_profile" "this" {
  name        = "${var.name_prefix}-inference-profile"
  description = "internal-rag-chatbot用のコスト配分タグ付きApplication Inference Profile"

  model_source {
    copy_from = var.system_inference_profile_arn
  }

  tags = merge(var.tags, {
    CostCenter = var.use_case_name
  })
}

# CostCenterタグのコスト配分タグとしての有効化（aws_ce_cost_allocation_tag）は
# アカウント全体のシングルトンリソースのため、共有Terraform（infra/cost_allocation_tag.tf）に
# 切り出し済み（#1）。ここでは付与するタグの値（CostCenter = var.use_case_name）のみ管理する。

resource "aws_budgets_budget" "bedrock" {
  name         = "${var.name_prefix}-bedrock-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Bedrock"]
  }

  dynamic "notification" {
    for_each = var.budget_alert_thresholds_percent
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_alert_email]
    }
  }
}
