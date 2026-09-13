# ============================================================================
# ★人間レビュー必須（CLAUDE.md: コスト管理設定）
#
# これはBedrockサービス単体ではなく「AWSアカウント全体」の請求額に対するアラーム。
# アカウント共通の設定であり、ユースケースごとのTerraform（docs/0X-xxx/infra）では
# 重複作成しないこと。
#
# 前提条件（Terraformでは自動化できない、手動の一回限りの設定）:
#   AWS Billing コンソール → 「請求設定」→「請求アラートを受け取る」を有効化しないと
#   AWS/Billing の EstimatedCharges メトリクスがCloudWatch(us-east-1)に出現しない。
#   apply前にコンソールで有効化しておくこと。
# ============================================================================

resource "aws_sns_topic" "billing_alarm" {
  provider = aws.us_east_1
  name     = "${local.name_prefix}-billing-alarm"
}

resource "aws_sns_topic_subscription" "billing_alarm_email" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.billing_alarm.arn
  protocol  = "email"
  endpoint  = var.budget_alert_email
}

resource "aws_cloudwatch_metric_alarm" "billing" {
  provider            = aws.us_east_1
  alarm_name          = "${local.name_prefix}-account-billing-alarm"
  alarm_description   = "AWSアカウント全体の推定請求額がしきい値を超えた場合に通知する（Bedrock以外の全サービス合算）。"
  namespace           = "AWS/Billing"
  metric_name         = "EstimatedCharges"
  dimensions          = { Currency = "USD" }
  statistic           = "Maximum"
  period              = 21600 # 6時間ごと（EstimatedChargesの更新頻度に合わせる）
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.account_billing_alarm_threshold_usd
  alarm_actions       = [aws_sns_topic.billing_alarm.arn]
  ok_actions          = [aws_sns_topic.billing_alarm.arn]
}
