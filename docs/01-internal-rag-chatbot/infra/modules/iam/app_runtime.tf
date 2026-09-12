# ============================================================================
# ★人間レビュー必須モジュール★ (CLAUDE.md: bedrock:InvokeModel系アクションの許可範囲)
#
# AppRuntimeロール = このユースケース専用（docs/00「1ユースケース=1ロール」原則）。
# requirements.md確定のロール名 bedrock-approntime-internal-rag-chatbot を使用。
# 許可範囲は「このKnowledge Base」「jp.anthropic.*推論プロファイル」「指定Guardrail」に限定し、
# 他のモデル・他ユースケースのリソースには一切触れない設計とする。
# さらにdocs/00「IAM側での強制方法（bedrock:GuardrailIdentifier条件キーでのDeny）」に従い、
# 指定Guardrail以外を使ったInvokeModelを明示的にDenyする。
# ============================================================================

resource "aws_iam_role" "app_runtime" {
  name = var.app_runtime_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "app_runtime_basic_execution" {
  role       = aws_iam_role.app_runtime.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "app_runtime_bedrock" {
  name = "${var.app_runtime_role_name}-bedrock"
  role = aws_iam_role.app_runtime.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # レビュー指摘対応: バックエンドの実際の呼び出し経路である RetrieveAndGenerate に
        # Guardrail指定を強制するConditionを付与する（InvokeModel側の強制だけでは
        # このAPIを経由するGuardrail未適用呼び出しを防げなかったため）。
        # 単純な bedrock:Retrieve（生成なし・Guardrail非対応）はこのユースケースの
        # バックエンド実装では使わないため許可しない（modules/backend/src/handler.pyのdocstring参照）。
        Sid      = "AllowKnowledgeBaseRetrieveAndGenerateWithGuardrailOnly"
        Effect   = "Allow"
        Action   = "bedrock:RetrieveAndGenerate"
        Resource = var.knowledge_base_arn
        Condition = {
          StringEquals = {
            "bedrock:GuardrailIdentifier" = var.guardrail_arn
            "bedrock:GuardrailVersion"    = var.guardrail_version
          }
        }
      },
      {
        Sid    = "AllowInvokeWithGuardrailOnly"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = concat(var.inference_profile_arns, [var.foundation_model_arn])
        Condition = {
          StringEquals = {
            "bedrock:GuardrailIdentifier" = var.guardrail_arn
            "bedrock:GuardrailVersion"    = var.guardrail_version
          }
        }
      },
      {
        Sid      = "AllowApplyGuardrail"
        Effect   = "Allow"
        Action   = "bedrock:ApplyGuardrail"
        Resource = var.guardrail_arn
      },
      {
        # 保険的なDeny: 万一上のAllow条件を満たさない別経路でInvokeModelを呼ぼうとした場合に
        # Guardrail未指定・別Guardrail指定での呼び出しを明示的に拒否する（docs/00の強制方法に対応）。
        Sid    = "DenyInvokeWithoutThisGuardrail"
        Effect = "Deny"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:RetrieveAndGenerate"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "bedrock:GuardrailIdentifier" = var.guardrail_arn
          }
        }
      }
    ]
  })
}
