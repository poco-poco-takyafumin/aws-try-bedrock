output "app_runtime_role_arn" {
  value = aws_iam_role.app_runtime.arn
}

output "app_runtime_role_name" {
  value = aws_iam_role.app_runtime.name
}

output "developer_role_arn" {
  value = aws_iam_role.developer.arn
}

output "developer_role_name" {
  value = aws_iam_role.developer.name
}

output "auditor_role_arn" {
  value = aws_iam_role.auditor.arn
}

output "auditor_role_name" {
  value = aws_iam_role.auditor.name
}
