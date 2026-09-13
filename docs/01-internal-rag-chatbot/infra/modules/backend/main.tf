# Slack app / チャットUI(Web) / CLI / プログラムからの呼び出しを一元的に受ける単一バックエンド
# （requirements.md確定: 各IFが個別にBedrockへ直接アクセスしない構成）。
# 実行ロールはmodules/iamで作成したAppRuntimeロールをそのまま使う（1ユースケース=1ロール）。

data "archive_file" "this" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.build/backend.zip"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name_prefix}-backend"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "this" {
  function_name    = "${var.name_prefix}-backend"
  role             = var.app_runtime_role_arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 512
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  environment {
    variables = {
      KNOWLEDGE_BASE_ID     = var.knowledge_base_id
      INFERENCE_PROFILE_ARN = var.inference_profile_arn
      GUARDRAIL_ARN         = var.guardrail_arn
      GUARDRAIL_VERSION     = var.guardrail_version
    }
  }

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name_prefix}-backend-api"
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
  tags        = var.tags
}

resource "aws_apigatewayv2_integration" "this" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "chat" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"

  # ============================================================================
  # ★レビュー指摘対応★ (CLAUDE.md: bedrock:InvokeModel系アクションの許可範囲に波及するIAM相当の変更)
  # 以前は認証設定が一切なく、エンドポイントURLを知っていれば誰でも呼び出せる状態だった。
  # Phase Aの暫定策としてAWS_IAM認証（SigV4署名必須）を設定し、無認証の外部公開を防ぐ。
  # Slack app等、SigV4署名できない呼び出し元向けの実際の認証方式（Slack署名検証を
  # ハンドラー内で行う専用ルートの追加、APIキー、Cognito等）はPhase Bで設計する
  # （未決事項としてrequirements.mdに追記済み）。
  # ============================================================================
  authorization_type = "AWS_IAM"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
