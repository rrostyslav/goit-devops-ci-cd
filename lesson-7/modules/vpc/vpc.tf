resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc_name
  }
}

locals {
  # EKS шукає підмережі для балансувальників за тегами. Публічні мають нести
  # `kubernetes.io/role/elb`, приватні — `kubernetes.io/role/internal-elb`, і
  # обидві — тег належності до кластера. Якщо cluster_name порожній, модуль
  # лишається звичайним VPC без прив'язки до Kubernetes.
  eks_common_tags = var.cluster_name == "" ? {} : {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  eks_public_subnet_tags  = var.cluster_name == "" ? {} : merge(local.eks_common_tags, { "kubernetes.io/role/elb" = "1" })
  eks_private_subnet_tags = var.cluster_name == "" ? {} : merge(local.eks_common_tags, { "kubernetes.io/role/internal-elb" = "1" })
}

resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name = "${var.vpc_name}-public-${count.index + 1}"
      Tier = "public"
    },
    local.eks_public_subnet_tags,
  )
}

resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    {
      Name = "${var.vpc_name}-private-${count.index + 1}"
      Tier = "private"
    },
    local.eks_private_subnet_tags,
  )
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.vpc_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# Один NAT Gateway на всі приватні підмережі (економія; для HA роблять по одному на AZ).
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.vpc_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}
