# Terraform プロバイダー
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# プロバイダー設定
provider "aws" {
  region = var.region
}

# Variable: AWS リージョン
variable "region" {
  description = "AWS リージョン"
  type        = string
  default     = "ap-northeast-1"
}

# Variable: インスタンスタイプ
variable "instance_type" {
  description = "EC2 インスタンスタイプ"
  type        = string
  default     = "t3.micro"
}

# Variable: SSH キーペア名
variable "key_name" {
  description = "EC2 インスタンスに接続するための SSH キーペア名"
  type        = string
  default     = "network-fault-observation-key"
}

# Variable: SSH CIDR
variable "allowed_cidr" {
  description = "SSH/8080 access source CIDR"
  type        = string
}