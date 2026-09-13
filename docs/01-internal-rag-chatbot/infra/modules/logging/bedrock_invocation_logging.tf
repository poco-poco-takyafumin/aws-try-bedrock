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

locals {
  # レビュー指摘対応: audit/redact両ステートメントで同一リストを二重管理していたのを一本化。
  pii_data_identifiers = [
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
}

resource "aws_cloudwatch_log_data_protection_policy" "bedrock_invocation" {
  log_group_name = aws_cloudwatch_log_group.bedrock_invocation.name

  policy_document = jsonencode({
    Name    = "${var.name_prefix}-pii-protection"
    Version = "2021-06-01"
    Statement = [
      {
        Sid            = "audit-financial-pii"
        DataIdentifier = local.pii_data_identifiers
        Operation = {
          Audit = {
            FindingsDestination = {}
          }
        }
      },
      {
        Sid            = "redact-financial-pii"
        DataIdentifier = local.pii_data_identifiers
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

    # ============================================================================
    # ★レビュー指摘・既知の限界（要人間レビュー）★
    # CloudWatch Logs data protectionはCloudWatch Logs宛のログのみをマスクする機能であり、
    # 同等のS3宛オブジェクトの自動マスキング機能はAWSに存在しない。そのため、この
    # s3_config経由でS3に書き込まれるModel invocation logは常に「マスク前の生データ」
    # （銀行口座番号等の未マスクPIIを含む）のままとなる。
    # docs/00「CloudWatch LogsとS3の両方に出力する」は必須要件のためS3宛出力自体は
    # 無効化できない。現状の緩和策はS3読み取りをAuditorロールのみに限定すること
    # （modules/logging/s3.tf）のみであり、残存リスクとして requirements.md の
    # 未決事項に追記済み。将来的にはS3 Object Lambda等での再マスキングパイプライン
    # 追加を検討すること。
    # ============================================================================
    s3_config {
      bucket_name = aws_s3_bucket.logs.id
      key_prefix  = "bedrock-invocation-logs"
    }
  }

  depends_on = [
    aws_iam_role_policy.bedrock_logging_cw,
    aws_s3_bucket_policy.logs,
    # レビュー指摘対応: data protectionポリシーが先に適用されるよう明示的に依存させる
    # （適用順序が入れ替わると、マスキングされていない生ログがCloudWatch Logsに
    # 書き込まれる窓が生じうるため）。
    aws_cloudwatch_log_data_protection_policy.bedrock_invocation
  ]
}
