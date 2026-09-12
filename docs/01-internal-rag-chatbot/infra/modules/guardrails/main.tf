# ============================================================================
# ★人間レビュー必須モジュール★ (CLAUDE.md: Guardrailsの設定内容)
# requirements.md「Guardrailsプロファイル方針」の確定内容を反映。
# apply前に必ずdiff（terraform plan）を人間がレビューすること。
# ============================================================================

resource "aws_bedrock_guardrail" "this" {
  name                      = "${var.name_prefix}-guardrail"
  blocked_input_messaging   = "この内容にはお答えできません。別の聞き方を試してください。"
  blocked_outputs_messaging = "回答内容がガイドラインに抵触するため表示できません。出典元の文書を直接ご確認ください。"

  # Content filters: 全カテゴリ最も厳しい設定（requirements.md確定: 家庭利用・子どもが触れる可能性を考慮）
  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "INSULTS"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "MISCONDUCT"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE" # Bedrock仕様上、PROMPT_ATTACKはoutput側の強度指定不可
    }
  }

  # Denied topics: requirements.md確定により設定しない（家庭内利用のため業務外話題の制限は不要）
  # topic_policy_config はブロックなし

  # PII filters: Bedrock標準PIIエンティティを広く適用。
  # action=ANONYMIZE（本文中の値をマスクして応答自体は継続する）を採用。
  # BLOCKにすると応答全体が拒否され、「出典リンクを提示する」というrequirements.mdの方針が実現できないため。
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "NAME"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "ADDRESS"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "AGE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_CVV"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_EXPIRY"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "INTERNATIONAL_BANK_ACCOUNT_NUMBER"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      # 日本の口座番号には直接該当しないが念のため広く有効化
      type   = "US_BANK_ACCOUNT_NUMBER"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "SWIFT_CODE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PASSWORD"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "USERNAME"
      action = "ANONYMIZE"
    }

    # 日本の銀行口座番号（支店番号+口座番号等、7桁前後の数字列）はBedrock標準PIIエンティティに
    # 直接対応するものがないため、正規表現フィルタで補う。パターンは実データに合わせて実装レビュー時に調整すること。
    regexes_config {
      name        = "jp_bank_account_number"
      description = "日本の銀行口座番号（7桁の数字列）を想定した簡易パターン。要調整。"
      pattern     = "\\b\\d{7}\\b"
      action      = "ANONYMIZE"
    }
  }

  # Contextual grounding check: 厳しめ（高しきい値）。
  # 銀行口座・保険等の正確性が重要な情報を扱うため、根拠のない推論回答を厳しくブロックする。
  contextual_grounding_policy_config {
    filters_config {
      type      = "GROUNDING"
      threshold = 0.85
    }
    filters_config {
      type      = "RELEVANCE"
      threshold = 0.85
    }
  }

  tags = var.tags
}

# DRAFTは変更可能なため、実際の呼び出しには不変なバージョンを発行して使う。
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "requirements.md確定内容の初版"
}
