# ============================================================================
# ★人間レビュー必須モジュール★ (CLAUDE.md: ログ出力先)
# ============================================================================

resource "aws_cloudtrail" "this" {
  name                          = "${var.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.logs.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.logs.arn

  tags = var.tags

  depends_on = [aws_s3_bucket_policy.logs]
}
