output "api_endpoint" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "lambda_function_name" {
  value = aws_lambda_function.this.function_name
}
