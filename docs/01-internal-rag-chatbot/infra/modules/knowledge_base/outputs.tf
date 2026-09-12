output "knowledge_base_id" {
  value       = aws_bedrockagent_knowledge_base.resource_kb.id
  description = "Knowledge BaseのID"
}

output "knowledge_base_arn" {
  value       = aws_bedrockagent_knowledge_base.resource_kb.arn
  description = "Knowledge BaseのARN"
}

output "kb_role_arn" {
  value       = aws_iam_role.kb_execution.arn
  description = "Knowledge Base実行ロールのARN（S3バケットポリシーから参照）"
}

output "oss_collection_arn" {
  value       = aws_opensearchserverless_collection.resource_kb.arn
  description = "OpenSearch ServerlessコレクションのARN"
}
