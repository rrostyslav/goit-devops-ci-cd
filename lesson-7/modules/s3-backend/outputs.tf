output "s3_bucket_name" {
  description = "Ім'я створеного S3-бакета"
  value       = aws_s3_bucket.terraform_state.id
}

output "s3_bucket_arn" {
  description = "ARN створеного S3-бакета"
  value       = aws_s3_bucket.terraform_state.arn
}

output "s3_bucket_url" {
  description = "URL створеного S3-бакета"
  value       = "https://${aws_s3_bucket.terraform_state.bucket_regional_domain_name}"
}

output "dynamodb_table_name" {
  description = "Ім'я створеної DynamoDB-таблиці для блокування"
  value       = aws_dynamodb_table.terraform_locks.name
}
