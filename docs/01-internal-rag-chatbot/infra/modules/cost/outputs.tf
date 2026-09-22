output "inference_profile_arn" {
  value       = aws_bedrock_inference_profile.this.arn
  description = "コストタグ付きApplication Inference Profile ARN。バックエンドLambdaはこのARNをInvokeModelの呼び出し先にする。"
}

output "budget_name" {
  value = aws_budgets_budget.bedrock.name
}
