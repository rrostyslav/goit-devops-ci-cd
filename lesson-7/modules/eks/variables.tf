variable "cluster_name" {
  description = "Ім'я EKS-кластера"
  type        = string
}

variable "cluster_version" {
  description = "Версія Kubernetes. `null` — AWS підставить поточну дефолтну версію"
  type        = string
  default     = null
}

variable "public_subnet_ids" {
  description = "ID публічних підмереж (потрібні для зовнішніх LoadBalancer)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "ID приватних підмереж — саме в них піднімаються воркер-ноди"
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Чи доступний Kubernetes API з інтернету (потрібно для kubectl з локальної машини)"
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Чи доступний Kubernetes API зсередини VPC"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "Список CIDR, яким дозволено доступ до публічного endpoint'а API"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = "Типи логів control plane, які слати в CloudWatch (порожній список — вимкнено, щоб не платити за логи)"
  type        = list(string)
  default     = []
}

variable "cluster_addons" {
  description = "EKS add-ons. metrics-server обов'язковий для роботи HPA"
  type        = list(string)
  default     = ["vpc-cni", "kube-proxy", "coredns", "metrics-server"]
}

variable "node_instance_types" {
  description = "Типи інстансів для воркер-нод (не менше t3.small)"
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_ami_type" {
  description = "Тип AMI для нод"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_capacity_type" {
  description = "Тип ємності: ON_DEMAND або SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_disk_size" {
  description = "Розмір кореневого диска ноди, ГБ"
  type        = number
  default     = 20
}

variable "node_desired_size" {
  description = "Бажана кількість воркер-нод"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Мінімальна кількість воркер-нод"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Максимальна кількість воркер-нод (має бути > 1, інакше HPA нікуди шедулити поди)"
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_size > 1
    error_message = "node_max_size має бути більшим за 1, інакше HPA не зможе розмістити додаткові поди."
  }
}

variable "node_labels" {
  description = "Kubernetes-лейбли для воркер-нод"
  type        = map(string)
  default     = {}
}

variable "admin_principal_arns" {
  description = "ARN IAM-користувачів/ролей, яким видати права адміністратора кластера (окрім його творця)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Додаткові теги для всіх ресурсів модуля"
  type        = map(string)
  default     = {}
}
