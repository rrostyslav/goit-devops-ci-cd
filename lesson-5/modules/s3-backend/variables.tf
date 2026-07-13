variable "bucket_name" {
  description = "Ім'я S3-бакета для збереження стейт-файлів Terraform (має бути глобально унікальним)"
  type        = string
}

variable "table_name" {
  description = "Ім'я DynamoDB-таблиці для блокування стейту"
  type        = string
  default     = "terraform-locks"
}
