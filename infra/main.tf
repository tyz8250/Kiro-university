data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "network-fault-observation-vpc"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "network-fault-observation-public-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "network-fault-observation-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "network-fault-observation-rt"
  }
}

# aws_route.default - 独立リソースとして定義
# Experiment 1 ではこの aws_route.default を構成から外し、
# Internet Gateway への Default Route を削除する
resource "aws_route" "default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group - TCP 22/8080 inbound
resource "aws_security_group" "ec2" {
  name        = "network-fault-observation-sg"
  description = "Security group for EC2 instance - allows SSH and HTTP"
  vpc_id      = aws_vpc.main.id

  # SSH (port 22) - 任意のIPv4アドレスから許可
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # HTTP (port 8080) - 任意のIPv4アドレスから許可
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # すべてのアウトバウンドトラフィックを許可
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "network-fault-observation-ec2-sg"
  }
}

# EC2 Instance
resource "aws_instance" "server" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type
  key_name      = var.key_name
  subnet_id     = aws_subnet.public.id

  vpc_security_group_ids = [aws_security_group.ec2.id]

  # ルートボリュームの設定
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  # ユーザーデータ - Docker インストールスクリプト
  user_data = <<-EOF
            #!/bin/bash
            yum update -y
            yum install -y docker
            systemctl enable --now docker
            usermod -aG docker ec2-user
            EOF

  tags = {
    Name = "network-fault-observation-ec2"
  }
}