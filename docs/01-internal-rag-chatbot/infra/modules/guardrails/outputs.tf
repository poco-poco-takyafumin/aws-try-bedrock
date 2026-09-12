output "guardrail_id" {
  value = aws_bedrock_guardrail.this.guardrail_id
}

output "guardrail_arn" {
  value = aws_bedrock_guardrail.this.guardrail_arn
}

output "guardrail_version" {
  value       = aws_bedrock_guardrail_version.this.version
  description = "IAMポリシー・アプリ呼び出しで参照する固定バージョン番号"
}
