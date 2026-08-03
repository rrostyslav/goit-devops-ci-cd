variable "ecr_name" {
  description = "Ім'я ECR-репозиторію"
  type        = string
}

variable "scan_on_push" {
  description = "Увімкнути автоматичне сканування образів під час push"
  type        = bool
  default     = true
}

variable "image_tag_mutability" {
  description = "Політика змінюваності тегів образів (MUTABLE або IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "force_delete" {
  description = "Дозволити видалення репозиторію разом з образами під час destroy"
  type        = bool
  default     = true
}
