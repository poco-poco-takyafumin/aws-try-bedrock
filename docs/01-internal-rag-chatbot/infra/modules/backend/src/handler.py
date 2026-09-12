"""チャットバックエンドLambda（プレースホルダー）。

Phase Aではインフラの箱（Lambda, API Gateway）のみを用意し、実際のロジックは
Phase Bで実装する。

Phase Bで実装する内容の概要（requirements.md / 実装計画より）:
  1. Slack app / チャットUI(Web) / CLI / プログラムからのリクエストをAPI Gateway経由で受ける
  2. bedrock:RetrieveAndGenerate を呼び出す（env: KNOWLEDGE_BASE_ID）
     - 推論プロファイル: env INFERENCE_PROFILE_ARN (jp.anthropic.* を経由したApplication Inference Profile)
     - Guardrail: env GUARDRAIL_ID / GUARDRAIL_VERSION を必ず指定する
  3. Guardrailでマスクされた箇所は、Knowledge Baseの引用（citation）から出典リンクを付与して返す
  4. 呼び出し元インターフェース（Slack/ChatUI/CLI/プログラム）ごとのレスポンス整形
"""

import json
import os


def handler(event, context):
    return {
        "statusCode": 501,
        "body": json.dumps(
            {
                "message": "backend chat handler is not implemented yet (Phase B).",
                "knowledge_base_id": os.environ.get("KNOWLEDGE_BASE_ID"),
            }
        ),
    }
