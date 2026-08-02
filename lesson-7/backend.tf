# Бакет `rachynskyi-terraform-state` і таблиця `terraform-locks` створені ще в
# ДЗ5 і не видалялись, тому ДЗ7 пише свій стейт у той самий бакет під іншим
# `key` — bootstrap повторювати не треба, достатньо звичайного `terraform init`.
#
# Якщо ви розгортаєте цей код «з нуля» (бакета ще не існує), поставте
# `create_state_backend = true` у main.tf і виконайте двоетапний bootstrap із
# README.md: спершу локальний стейт із закоментованим блоком нижче, потім
# `terraform init -migrate-state`.
terraform {
  backend "s3" {
    bucket         = "rachynskyi-terraform-state"
    key            = "lesson-7/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
