# ============================================================================
# 注意: docs/00-architecture-overview.md のDeveloper/Auditorは本来アカウント
# 共通の「型」であり、AppRuntimeのように1ユースケース=1ロールではない。
# しかしdocs/00の未決事項「複数ユースケースを単一AWSアカウントで運用するか、
# アカウント分離するか」が未確定だった当時の経緯から、他ユースケース(02, 03)の
# Terraformと同名ロールを重複作成して衝突するのを避ける目的で、ここでは
# ユースケース名をロール名に含めて作成している（暫定対応）。
# 将来的に「単一アカウント運用」に決まった場合は、これらのロールをユースケース
# 横断の共通moduleに切り出し、本ユースケースのmoduleからは呼び出しに留めるよう
# リファクタリングが必要（issue #2、未決事項として requirements.md に追記済み）。
#
# Adminロールはこのファイルではなく独立した modules/iam_admin で定義している
# （modules/knowledge_baseとの循環依存を避けるため。詳細は同moduleのコメント参照）。
# ============================================================================

data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}

locals {
  account_root_principal = "arn:${data.aws_partition.this.partition}:iam::${data.aws_caller_identity.this.account_id}:root"
}

# --- Developer: 検証目的のモデル呼び出し（Guardrails必須の条件付き） ---
resource "aws_iam_role" "developer" {
  name = "${var.name_prefix}-developer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { AWS = local.account_root_principal }
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "developer" {
  name = "${var.name_prefix}-developer"
  role = aws_iam_role.developer.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        # レビュー指摘対応: AppRuntimeと同様にGuardrailVersionも一致条件に含める
        # （以前はGuardrailIdentifierのみで、GuardrailのDRAFT版や別バージョンでも
        # 通過できてしまっていた）。基盤モデルARN直接指定も許可しない（AppRuntimeと同じ理由）。
        Sid      = "AllowInvokeWithGuardrailOnly"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = var.inference_profile_arns
        Condition = {
          StringEquals = {
            "bedrock:GuardrailIdentifier" = var.guardrail_arn
            "bedrock:GuardrailVersion"    = var.guardrail_version
          }
        }
      }
    ], local.guardrail_deny_statements_by_actions["developer"])
  })
}

# --- Auditor: ログ閲覧のみ（セキュリティ・監査担当） ---
resource "aws_iam_role" "auditor" {
  name = "${var.name_prefix}-auditor"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { AWS = local.account_root_principal }
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "auditor" {
  name = "${var.name_prefix}-auditor"
  role = aws_iam_role.auditor.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnlyLogs"
        Effect = "Allow"
        Action = [
          "logs:Get*",
          "logs:Describe*",
          "logs:FilterLogEvents",
          "cloudtrail:LookupEvents",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:DescribeTrails"
        ]
        Resource = "*"
      }
      # S3ログバケットへの読み取り権限は modules/logging 側のバケットポリシーで
      # このロールのARNを指定して付与する（auditor_role_arn変数）。
    ]
  })
}
