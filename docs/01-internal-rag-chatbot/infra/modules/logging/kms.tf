# ログ専用KMSキー。KBデータ用キー（kms.tf の aws_kms_key.kb_data）とは分離する。
resource "aws_kms_key" "logs" {
  description             = "${var.name_prefix} ログ（CloudTrail/Model invocation logging）用KMSキー"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.this.partition}:iam::${data.aws_caller_identity.this.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowCloudTrailEncrypt"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:${data.aws_partition.this.partition}:cloudtrail:${data.aws_region.this.name}:${data.aws_caller_identity.this.account_id}:trail/${var.name_prefix}-trail"
          }
        }
      },
      {
        Sid    = "AllowBedrockLoggingEncrypt"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action   = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.this.account_id
          }
        }
      },
      {
        # レビュー指摘対応: CloudWatch Logsロググループ（Model invocation logging用）が
        # このキーで暗号化する設定（aws_cloudwatch_log_group.kms_key_id）になっているが、
        # CloudWatch Logsサービスプリンシパルへの許可が欠けていたため追加。
        # リージョン別のサービスプリンシパル（logs.<region>.amazonaws.com）を使う必要がある。
        Sid    = "AllowCloudWatchLogsEncrypt"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.this.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.this.partition}:logs:${data.aws_region.this.name}:${data.aws_caller_identity.this.account_id}:log-group:*"
          }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name_prefix}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

# Auditorロールへのログ閲覧権限（KMS復号）。
# このキーの鍵ポリシー（EnableRootAccountPermissions）がアカウントルートにkms:*を
# 委譲しているため、IAM側のアイデンティティポリシーでの許可のみで足り、
# 鍵ポリシー自体の追加変更は不要（modules/iamとの循環依存も回避できる）。
resource "aws_iam_role_policy" "auditor_kms_decrypt" {
  count = var.auditor_role_name == null ? 0 : 1
  name  = "${var.name_prefix}-auditor-logs-kms-decrypt"
  role  = var.auditor_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowDecryptLogsKey"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = aws_kms_key.logs.arn
      }
    ]
  })
}

data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}
data "aws_region" "this" {}
