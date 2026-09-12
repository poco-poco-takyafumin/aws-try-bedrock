# Knowledge Baseデータソース用S3バケット。
# ログ用バケット（modules/logging）とは別バケット・別KMSキーにし、
# docs/00-architecture-overview.md の「ログバケットは実行環境と権限分離する」を満たす。

resource "random_id" "kb_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "kb_data" {
  bucket = "${local.name_prefix}-kb-data-${random_id.kb_bucket_suffix.hex}"
}

resource "aws_s3_bucket_versioning" "kb_data" {
  bucket = aws_s3_bucket.kb_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kb_data" {
  bucket = aws_s3_bucket.kb_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.kb_data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "kb_data" {
  bucket                  = aws_s3_bucket.kb_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# バケットポリシーで、Knowledge Base実行ロールとgdrive_sync Lambdaロール以外からのアクセスを拒否する。
# ロールARNはIAM/knowledge_baseモジュールの出力に依存するため、循環を避けてmain.tf側のmodule宣言後に評価される。
resource "aws_s3_bucket_policy" "kb_data" {
  bucket = aws_s3_bucket.kb_data.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.kb_data.arn,
          "${aws_s3_bucket.kb_data.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowKnowledgeBaseRole"
        Effect = "Allow"
        Principal = {
          AWS = module.knowledge_base.kb_role_arn
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.kb_data.arn,
          "${aws_s3_bucket.kb_data.arn}/*"
        ]
      },
      {
        Sid    = "AllowGdriveSyncWrite"
        Effect = "Allow"
        Principal = {
          AWS = module.gdrive_sync.lambda_role_arn
        }
        Action = [
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.kb_data.arn,
          "${aws_s3_bucket.kb_data.arn}/*"
        ]
      }
    ]
  })
}
