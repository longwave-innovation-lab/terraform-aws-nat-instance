

locals {
  az_count             = length(var.public_subnet_ids)
  nat_instance_count   = var.nat_instance_per_az ? local.az_count : 1
  userdata_script_path = var.user_data_script != "" ? var.user_data_script : "${path.module}/ec2_conf/default_userdata.sh"
}

# SSH Key Generation
resource "tls_private_key" "pk_nat" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "rsa_nat" {
  key_name   = "${var.name_prefix}-ssh-key-natgateway"
  public_key = tls_private_key.pk_nat.public_key_openssh
}

resource "aws_ssm_parameter" "nat_instance_ssh_key" {
  count       = local.nat_instance_count
  name        = "/${var.name_prefix}/ec2-nat-sshkey-${count.index + 1}"
  description = "Chiave privata SSH per la ec2-nat ${count.index + 1}"
  type        = "SecureString"
  value       = tls_private_key.pk_nat.private_key_pem
}

# Security Groups
resource "aws_security_group" "natgw_public" {
  count       = local.nat_instance_count
  vpc_id      = var.vpc_id
  name_prefix = "${var.name_prefix}-eth0-natgw-${count.index + 1}-public-"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Output vs ANY"
  }

  tags = {
    Name = "${var.name_prefix}-eth0-natgw-${count.index + 1}-public"
  }
}

resource "aws_security_group" "natgw_private" {
  count       = local.nat_instance_count
  vpc_id      = var.vpc_id
  name_prefix = "${var.name_prefix}-eth1-natgw-${count.index + 1}-private-"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Output vs ANY"
  }

  tags = {
    Name = "${var.name_prefix}-eth1-natgw-${count.index + 1}-private"
  }
}

# Network Interfaces
resource "aws_network_interface" "natgw_public" {
  count       = local.nat_instance_count
  subnet_id   = var.public_subnet_ids[count.index]
  description = "${var.name_prefix}-eth0-natgw-${count.index + 1}"

  tags = {
    Name = "${var.name_prefix}-eth0-natgw-${count.index + 1}-public"
  }
}

resource "aws_network_interface" "natgw_private" {
  count             = local.nat_instance_count
  subnet_id         = var.private_subnet_ids[count.index]
  security_groups   = [aws_security_group.natgw_private[count.index].id]
  source_dest_check = false

  tags = {
    Name = "${var.name_prefix}-eth1-natgw-${count.index + 1}-private"
  }
}

# Routes
resource "aws_route" "nat_route" {
  count                  = length(var.private_route_table_ids)
  route_table_id         = var.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.natgw_private[var.nat_instance_per_az ? count.index : 0].id
}


# Elastic IP
resource "aws_eip" "nat_eip" {
  count             = local.nat_instance_count
  domain            = "vpc"
  network_interface = aws_network_interface.natgw_public[count.index].id

  tags = {
    Name = "${var.name_prefix}-natgw-${count.index + 1}-az-${element(["a", "b", "c"], count.index)}"
  }
}

# Security Group Attachment
resource "aws_network_interface_sg_attachment" "natgw_public_sg_attachment" {
  count                = local.nat_instance_count
  security_group_id    = aws_security_group.natgw_public[count.index].id
  network_interface_id = aws_network_interface.natgw_public[count.index].id
}

locals {
  ami_values = {
    "arm" = "al2023-ami-*-kernel-*-arm64"
    "x86" = "al2023-ami-*-kernel-*-x86_64"
  }
}

# Determina l'architettura in base al tipo di istanza
locals {
  is_arm       = can(regex("^[a-z0-9]+g\\.", var.instance_type)) # Cerca il suffisso "g." nel tipo di istanza
  architecture = local.is_arm ? "arm" : "x86"                    # Se è ARM, usa "arm64", altrimenti "x86_64"
}

# AMI Data Source
data "aws_ami" "immagine-arm64" {
  most_recent = true

  filter {
    name   = "name"
    values = [lookup(local.ami_values, local.architecture, "al2023-ami-*-kernel-*-arm64")] # Default ARM se non trova valore
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["amazon"]
  #owners = ["${var.ami_owner}"]
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "natgw_logs" {
  name              = "/aws/ec2/natgw/logs"
  retention_in_days = var.log_retention_days
}

# EC2 Instance
module "ec2_natgw" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.8.0"

  count                = local.nat_instance_count
  name                 = "${var.name_prefix}-natgw-${count.index + 1}"
  ami                  = data.aws_ami.immagine-arm64.id
  instance_type        = var.instance_type
  key_name             = aws_key_pair.rsa_nat.key_name
  cpu_credits          = "unlimited"
  iam_instance_profile = aws_iam_instance_profile.ec2-nat-ssm-cloudwatch-instance-profile.name

  network_interface = [
    {
      device_index         = 0
      network_interface_id = aws_network_interface.natgw_public[count.index].id
    },
    {
      device_index         = 1
      network_interface_id = aws_network_interface.natgw_private[count.index].id
    }
  ]

  root_block_device = [
    {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
    }
  ]
  user_data = filebase64("${local.userdata_script_path}")
}


