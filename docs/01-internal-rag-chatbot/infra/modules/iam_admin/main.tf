# ============================================================================
# 注意: docs/00-architecture-overview.md のAdminは本来アカウント共通の「型」であり、
# AppRuntimeのように1ユースケース=1ロールではない。しかしdocs/00の未決事項
# 「複数ユースケースを単一AWSアカウントで運用するか、アカウント分離するか」が
# 未確定だった当時の経緯から、他ユースケース(02, 03)のTerraformと同名ロールを
# 重複作成して衝突するのを避ける目的で、ここではユースケース名をロール名に
# 含めて作成している（暫定対応）。
# 将来的にアカウント横断の共通moduleへ切り出すリファクタリングが必要
# （issue #2、requirements.mdにも未決事項として追記済み）。
#
# Adminロールをmodules/iamから独立したこのmoduleに分離している理由:
# modules/knowledge_base（OpenSearchアクセスポリシーでAdminに管理アクセスを
# 許可する）がAdminロールのARNを必要とする一方、modules/iam（Developer/
# AppRuntime/Auditor）はmodules/knowledge_baseの出力（knowledge_base_arn等）を
# 必要とする。Adminロールの定義自体はknowledge_base側の出力に一切依存しない
# ため、このmoduleを独立させることでmodules/knowledge_base → modules/iam_admin
# の一方向の依存だけで済み、モジュール間の循環依存（および、それを回避するための
# 手組みARN文字列）を避けられる。
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
      # （admin_role_name変数経由。modules/iam_admin→modules/loggingの一方向依存で循環を回避）。
      {
        Sid      = "CostManagement"
        Effect   = "Allow"
        Action   = ["budgets:*", "ce:*"]
        Resource = "*"
      }
    ]
  })
}
