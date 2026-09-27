# EC2 インスタンスのパブリックIPアドレス
output "ec2_public_ip" {
  description = "EC2 instance public IP address"
  value       = aws_instance.server.public_ip
}

# EC2 インスタンスID
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.server.id
}

# VPC ID
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

# パブリックサブネットID
output "subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

# セキュリティグループID
output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.ec2.id
}