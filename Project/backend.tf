# =============================================================================
# Віддалений стейт: S3 + DynamoDB
# =============================================================================
# S3 зберігає сам стейт і версіонує його, DynamoDB тримає блокування: поки один
# apply працює, другий не почнеться й не перетре чужі зміни.
#
# Бакет `rachynskyi-terraform-state` і таблиця `terraform-locks` створені ще в
# ДЗ5 і не видалялись, тому фінальний проєкт пише свій стейт у той самий бакет
# під окремим `key` — bootstrap повторювати не треба, достатньо `terraform init`.
#
# ЯКЩО РОЗГОРТАЄТЕ З НУЛЯ (бакета ще не існує), тут виникає замкнене коло: блок
# нижче вказує на бакет, який створює цей самий код, тож найперший `init`
# провалиться. Розривається воно у два кроки — поставте `create_state_backend =
# true` у main.tf і виконайте:
#
#   1. закоментуйте блок `backend "s3"` нижче
#   2. terraform init                                # локальний стейт
#   3. terraform apply -target=module.s3_backend     # створити бакет і таблицю
#   4. розкоментуйте блок назад
#   5. terraform init -migrate-state                 # перенести стейт у S3
#
# І навпаки, на видаленні: `terraform destroy` знесе бакет разом із таблицею,
# а стейт у цей момент лежить саме в них. Тому спершу
# `terraform state pull > backup.tfstate`, і лише потім destroy.
terraform {
  backend "s3" {
    bucket         = "rachynskyi-terraform-state"
    key            = "final-project/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
