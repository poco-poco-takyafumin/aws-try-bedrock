# ============================================================================
# ★人間レビュー必須モジュール★ (CLAUDE.md: ログ出力先)
#
# 重要な注意点: aws_bedrock_model_invocation_logging_configuration は
# 「AWSアカウント×リージョン」単位のシングルトン設定であり、Knowledge Base単位・
# ユースケース単位には分離できない。docs/00-architecture-overview.mdの未決事項
# 「複数ユースケースを単一AWSアカウントで運用するか、アカウント分離するか」が
# 未確定のまま複数ユースケース(02, 03)を同一アカウントに展開すると、
# 本リソースの設定は後から適用した方で上書きされる（取り合いになる）。
# アカウント分離しない場合は、02/03のユースケースでは本モジュールの
# bedrock_invocation_logging.tf 部分を重複適用せず、既存設定を参照するのみに
# 変更する必要がある。実装時に要判断（人間レビュー対象）。
# ============================================================================

resource "aws_cloudwatch_log_group" "bedrock_invocation" {
  name              = "/${var.name_prefix}/bedrock/model-invocation-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn
  tags              = var.tags
}

resource "aws_cloudwatch_log_data_protection_policy" "bedrock_invocation" {
  log_group_name = aws_cloudwatch_log_group.bedrock_invocation.name

  policy_document = jsonencode({
    Name    = "${var.name_prefix}-pii-protection"
    Version = "2021-06-01"
    Statement = [
      {
        Sid = "audit-financial-pii"
        DataIdentifier = [
          "arn:aws:dataprotection::aws:data-identifier/BankAccountNumber-JP",
          "arn:aws:dataprotection::aws:data-identifier/Address-JP",
          "arn:aws:dataprotection::aws:data-identifier/PhoneNumber-JP",
          "arn:aws:dataprotection::aws:data-identifier/CreditCardNumber",
          "arn:aws:dataprotection::aws:data-identifier/CreditCardExpiration",
          "arn:aws:dataprotection::aws:data-identifier/CreditCardSecurityCode",
          "arn:aws:dataprotection::aws:data-identifier/SwiftCode",
          "arn:aws:dataprotection::aws:data-identifier/Name",
          "arn:aws:dataprotection::aws:data-identifier/EmailAddress"
        ]
        Operation = {
          Audit = {
            FindingsDestination = {}
          }
        }
      },
      {
        Sid = "redact-financial-pii"
        DataIdentifier = [
          "arn:aws:dataprotection::aws:data-identifier/BankAccountNumber-JP",
          "arn:aws:dataprotection::aws:data-identifier/Address-JP",
          "arn:aws:dataprotection::aws:data-identifier/PhoneNumber-JP",
          "arn:aws:dataprotection::aws:data-identifier/CreditCardNumber",
          "arn:aws:dataprotection::aws:data-identifier/CreditCardExpiration",
          "arn:aws:dataprotection::aws:data-identifier/CreditCardSecurityCode",
          "arn:aws:dataprotection::aws:data-identifier/SwiftCode",
          "arn:aws:dataprotection::aws:data-identifier/Name",
          "arn:aws:dataprotection::aws:data-identifier/EmailAddress"
        ]
        Operation = {
          Deidentify = {
            MaskConfig = {}
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "bedrock_logging" {
  name = "${var.name_prefix}-bedrock-logging-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.this.account_id }
        }
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "bedrock_logging_cw" {
  name = "${var.name_prefix}-bedrock-logging-cw"
  role = aws_iam_role.bedrock_logging.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.bedrock_invocation.arn}:*"
      }
    ]
  })
}

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  logging_config {
    text_data_delivery_enabled      = true
    image_data_delivery_enabled     = false
    embedding_data_delivery_enabled = true

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocation.name
      role_arn       = aws_iam_role.bedrock_logging.arn
    }

    s3_config {
      bucket_name = aws_s3_bucket.logs.id
      key_prefix  = "bedrock-invocation-logs"
    }
  }

  depends_on = [
    aws_iam_role_policy.bedrock_logging_cw,
    aws_s3_bucket_policy.logs
  ]
}
