data "archive_file" "this" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.build/gdrive_sync.zip"
}

resource "aws_iam_role" "this" {
  name = "${var.name_prefix}-gdrive-sync-role"
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

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "this" {
  name = "${var.name_prefix}-gdrive-sync"
  role = aws_iam_role.this.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadServiceAccountSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.gdrive_service_account.arn
      },
      {
        Sid      = "ReadFolderIdParameter"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = aws_ssm_parameter.gdrive_folder_id.arn
      },
      {
        Sid      = "WriteKbBucket"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:ListBucket"]
        Resource = [var.kb_bucket_arn, "${var.kb_bucket_arn}/*"]
      },
      {
        Sid      = "UseKbKmsKey"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = var.kb_kms_key_arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name_prefix}-gdrive-sync"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# 同期頻度はPoC初期は手動実行（requirements.md確定）。EventBridge Schedulerによるトリガーは設定しない。
# 運用が安定したら定期実行化を検討する際に aws_scheduler_schedule を追加する。
resource "aws_lambda_function" "this" {
  function_name    = "${var.name_prefix}-gdrive-sync"
  role             = aws_iam_role.this.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 512
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  environment {
    variables = {
      KB_BUCKET_NAME       = var.kb_bucket_name
      GDRIVE_SECRET_ARN    = aws_secretsmanager_secret.gdrive_service_account.arn
      GDRIVE_FOLDER_ID_SSM = aws_ssm_parameter.gdrive_folder_id.name
    }
  }

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.this]
}
