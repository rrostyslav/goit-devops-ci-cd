terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Потрібен рівно для одного: витягнути сертифікат OIDC-ендпоінта кластера
    # й порахувати його відбиток для aws_iam_openid_connect_provider.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
