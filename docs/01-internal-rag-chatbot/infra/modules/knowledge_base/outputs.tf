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

output "vector_index_arn" {
  value       = aws_s3vectors_index.resource_kb.index_arn
  description = "S3 VectorsのベクトルインデックスARN"
}
