# レビュー指摘対応: Guardrail強制のDeny文（「別のGuardrailを指定した」「Guardrailを
# 一切指定しなかった」の2パターンをそれぞれ拒否する）が、app_runtime.tfとDeveloper用
# ポリシー（admin_developer_auditor.tf）に一字一句重複していた。ロールごとに許可アクションの
# 集合が異なる（AppRuntimeはbedrock:RetrieveAndGenerateも含む）ため、対象アクションのリストを
# 引数化した関数的なlocalとして一本化し、両ファイルから参照する。
locals {
  guardrail_deny_statements_by_actions = {
    for key, actions in {
      app_runtime = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:RetrieveAndGenerate"]
      developer   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      } : key => [
      {
        # 保険的なDeny: 万一Allow条件を満たさない別経路で呼ぼうとした場合に
        # 「指定Guardrail以外」を使った呼び出しを明示的に拒否する（docs/00の強制方法に対応）。
        # 注意: StringNotEqualsは条件キー自体がリクエストに存在しない場合はfalseと評価され
        # （IAMの仕様）、Denyが発火しない。「別のGuardrailを指定した」場合はこれで拒否できるが、
        # 「Guardrailを一切指定しなかった」場合は下のNullチェックのDenyで別途拒否する。
        Sid      = "DenyInvokeWithDifferentGuardrail"
        Effect   = "Deny"
        Action   = actions
        Resource = "*"
        Condition = {
          StringNotEquals = { "bedrock:GuardrailIdentifier" = var.guardrail_arn }
        }
      },
      {
        # 上のDenyが捕捉できない「Guardrailを一切指定しなかった」呼び出しを拒否する追加Deny。
        # Null条件キーが"true"（＝キーが存在しない）の場合に発火する。
        Sid      = "DenyInvokeWithoutAnyGuardrail"
        Effect   = "Deny"
        Action   = actions
        Resource = "*"
        Condition = {
          Null = { "bedrock:GuardrailIdentifier" = "true" }
        }
      }
    ]
  }
}
