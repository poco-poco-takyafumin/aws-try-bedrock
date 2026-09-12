output "lambda_role_arn" {
  value = aws_iam_role.this.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.this.function_name
}

output "secret_arn" {
  value = aws_secretsmanager_secret.gdrive_service_account.arn
}

output "folder_id_parameter_name" {
  value = aws_ssm_parameter.gdrive_folder_id.name
}
