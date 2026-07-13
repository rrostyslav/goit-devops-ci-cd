terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "s3_backend" {
  source = "./modules/s3-backend"

  # Ім'я має бути глобально унікальним і збігатися з `bucket` у backend.tf.
  bucket_name = "rachynskyi-terraform-state"
  table_name  = "terraform-locks"
}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block     = "10.0.0.0/16"
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets    = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
  vpc_name           = "lesson-5-vpc"
}

module "ecr" {
  source = "./modules/ecr"

  ecr_name     = "lesson-5-ecr"
  scan_on_push = true
}
