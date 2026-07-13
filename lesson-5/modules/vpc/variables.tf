variable "vpc_cidr_block" {
  description = "CIDR-блок для VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Список CIDR-блоків для публічних підмереж"
  type        = list(string)
}

variable "private_subnets" {
  description = "Список CIDR-блоків для приватних підмереж"
  type        = list(string)
}

variable "availability_zones" {
  description = "Список зон доступності (AZ) для розміщення підмереж"
  type        = list(string)
}

variable "vpc_name" {
  description = "Ім'я (тег Name) для VPC та пов'язаних ресурсів"
  type        = string
  default     = "lesson-5-vpc"
}
