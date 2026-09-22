output "log_bucket_name" {
  value = aws_s3_bucket.logs.id
}

output "log_bucket_arn" {
  value = aws_s3_bucket.logs.arn
}

output "cloudtrail_arn" {
  value = aws_cloudtrail.this.arn
}

output "bedrock_invocation_log_group_name" {
  value = aws_cloudwatch_log_group.bedrock_invocation.name
}

output "logs_kms_key_arn" {
  value = aws_kms_key.logs.arn
}
