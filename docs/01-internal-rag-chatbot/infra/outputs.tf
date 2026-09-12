output "knowledge_base_id" {
  value = module.knowledge_base.knowledge_base_id
}

output "kb_data_bucket_name" {
  value = aws_s3_bucket.kb_data.bucket
}

output "guardrail_id" {
  value = module.guardrails.guardrail_id
}

output "guardrail_version" {
  value = module.guardrails.guardrail_version
}

output "app_runtime_role_arn" {
  value = module.iam.app_runtime_role_arn
}

output "inference_profile_arn" {
  value = module.cost.inference_profile_arn
}

output "log_bucket_name" {
  value = module.logging.log_bucket_name
}

output "backend_api_endpoint" {
  value = module.backend.api_endpoint
}

output "gdrive_sync_lambda_function_name" {
  value = module.gdrive_sync.lambda_function_name
}

output "gdrive_sync_secret_arn" {
  value = module.gdrive_sync.secret_arn
}
