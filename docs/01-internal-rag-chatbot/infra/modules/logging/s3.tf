# ログ専用S3バケット。KBデータ用バケット（ルートのs3.tf）とは別バケットにし、
# docs/00-architecture-overview.md「ログバケットは実行環境と権限分離する」を満たす。
# 読み取りはAuditorロールのみに許可する。

resource "random_id" "log_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.name_prefix}-logs-${random_id.log_bucket_suffix.hex}"
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.logs.arn,
          "${aws_s3_bucket.logs.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid    = "AllowCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.this.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:${data.aws_partition.this.partition}:cloudtrail:${data.aws_region.this.name}:${data.aws_caller_identity.this.account_id}:trail/${var.name_prefix}-trail"
          }
        }
      },
      {
        Sid    = "AllowCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:${data.aws_partition.this.partition}:cloudtrail:${data.aws_region.this.name}:${data.aws_caller_identity.this.account_id}:trail/${var.name_prefix}-trail"
          }
        }
      },
      {
        Sid    = "AllowBedrockModelInvocationLoggingWrite"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/bedrock-invocation-logs/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.this.account_id
          }
        }
      }
      ],
      var.auditor_role_arn == null ? [] : [
        {
          Sid    = "AllowAuditorReadOnly"
          Effect = "Allow"
          Principal = {
            AWS = var.auditor_role_arn
          }
          Action = [
            "s3:GetObject",
            "s3:ListBucket"
          ]
          Resource = [
            aws_s3_bucket.logs.arn,
            "${aws_s3_bucket.logs.arn}/*"
          ]
        }
    ])
  })
}

# レビュー指摘対応: Adminロールのバケットポリシー変更権限（GetBucketPolicy/PutBucketPolicy）を
# このログバケットに限定したアイデンティティポリシーとして付与する（以前はmodules/iam側で
# Resource="*"となっており、ログバケット以外も書き換え可能だった。auditor_kms_decryptと
# 同様にmodules/logging側で付与することでmodules/iamとの循環依存を回避）。
resource "aws_iam_role_policy" "admin_log_bucket_policy_management" {
  count = var.admin_role_name == null ? 0 : 1
  name  = "${var.name_prefix}-admin-log-bucket-policy"
  role  = var.admin_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowLogBucketPolicyManagement"
        Effect   = "Allow"
        Action   = ["s3:GetBucketPolicy", "s3:PutBucketPolicy"]
        Resource = aws_s3_bucket.logs.arn
      }
    ]
  })
}
