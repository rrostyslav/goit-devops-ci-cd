# УВАГА (bootstrap): бакет і таблиця нижче створюються модулем s3-backend,
# тож на першому запуску їх ще немає. Спершу закоментуйте цей блок і виконайте
# `terraform apply -target=module.s3_backend`, потім розкоментуйте та
# `terraform init -migrate-state`. Детально — у README.md.
terraform {
  backend "s3" {
    bucket         = "rachynskyi-terraform-state"
    key            = "lesson-5/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
