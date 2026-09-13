# ============================================================================
# 注意: docs/00-architecture-overview.md のAdmin/Developer/Auditorは本来アカウント
# 共通の「型」であり、AppRuntimeのように1ユースケース=1ロールではない。
# しかしdocs/00の未決事項「複数ユースケースを単一AWSアカウントで運用するか、
# アカウント分離するか」が未確定のため、他ユースケース(02, 03)のTerraformと
# 同名ロースを重複作成して衝突するのを避ける目的で、ここではユースケース名を
# ロール名に含めて作成している（暫定対応）。
# 将来的に「単一アカウント運用」に決まった場合は、これらのロールをユースケース
# 横断の共通moduleに切り出し、本ユースケースのmoduleからは呼び出しに留めるよう
# リファクタリングが必要（未決事項として requirements.md に追記済み）。
# ============================================================================

data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}

locals {
  account_root_principal = "arn:${data.aws_partition.this.partition}:iam::${data.aws_caller_identity.this.account_id}:root"
}

# --- Admin: Model access申請、Guardrails管理、ログ/Budgets設定変更（少数の管理者のみ） ---
resource "aws_iam_role" "admin" {
  name = "${var.name_prefix}-admin"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # TODO(要レビュー): 本来はIAM Identity Center経由のSSO権限セットで統制すべき。
        # ここではPoC簡略化のためアカウントrootからのAssumeRoleのみ許可し、
        # 実際に引き受けられる主体はIAMポリシー/Identity Center側で別途絞ること。
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { AWS = local.account_root_principal }
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "admin" {
  name = "${var.name_prefix}-admin"
  role = aws_iam_role.admin.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockGovernance"
        Effect = "Allow"
        Action = [
          "bedrock:*Guardrail*",
          "bedrock:GetFoundationModel",
          "bedrock:ListFoundationModels",
          "bedrock:GetInferenceProfile",
          "bedrock:ListInferenceProfiles",
          "bedrock:CreateInferenceProfile",
          "bedrock:TagResource",
          "bedrock:UntagResource"
        ]
        Resource = "*"
      },
      {
        # レビュー指摘対応: 以前は logs:* / cloudtrail:* のワイルドカードで
        # ログ「内容」の読み取り（logs:GetLogEvents, logs:FilterLogEvents,
        # logs:GetLogRecord, logs:StartQuery/GetQueryResults, cloudtrail:LookupEvents 等）
        # まで許可してしまっていた。docs/00「ログへの読み取り権限はAuditorロールのみに
        # 付与する」に反するため、設定変更系アクションのみに絞り込む。
        Sid    = "LoggingConfig"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:DescribeLogGroups",
          "logs:PutDataProtectionPolicy",
          "logs:DeleteDataProtectionPolicy",
          "logs:GetDataProtectionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
          "cloudtrail:CreateTrail",
          "cloudtrail:UpdateTrail",
          "cloudtrail:DeleteTrail",
          "cloudtrail:StartLogging",
          "cloudtrail:StopLogging",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:GetEventSelectors",
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:AddTags",
          "cloudtrail:RemoveTags"
        ]
        Resource = "*"
      },
      # レビュー指摘対応: s3:GetBucketPolicy/PutBucketPolicyをResource="*"で持たせていると、
      # ログバケット以外（KBデータバケット等）のバケットポリシーも書き換えられてしまうため、
      # ログバケットに限定したインラインポリシーとして modules/logging 側で付与する
      # （admin_role_name変数経由。modules/iam→modules/loggingの一方向依存で循環を回避）。
      {
        Sid      = "CostManagement"
        Effect   = "Allow"
        Action   = ["budgets:*", "ce:*"]
        Resource = "*"
      }
    ]
  })
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
    Statement = [
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
      },
      {
        Sid      = "DenyInvokeWithDifferentGuardrail"
        Effect   = "Deny"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "*"
        Condition = {
          StringNotEquals = { "bedrock:GuardrailIdentifier" = var.guardrail_arn }
        }
      },
      {
        # レビュー指摘対応: StringNotEqualsはキー不在時はDenyしないため、Guardrailを
        # 一切指定しない呼び出しを別途Nullチェックで拒否する（AppRuntimeと同じ理由）。
        Sid      = "DenyInvokeWithoutAnyGuardrail"
        Effect   = "Deny"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "*"
        Condition = {
          Null = { "bedrock:GuardrailIdentifier" = "true" }
        }
      }
    ]
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
