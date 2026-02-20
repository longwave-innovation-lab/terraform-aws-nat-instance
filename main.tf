

locals {
  az_count           = length(var.public_subnet_ids)
  nat_instance_count = var.nat_instance_per_az ? local.az_count : 1
  
  # Template variables for user data
  userdata_template_vars = {
    enable_cloudwatch_logs = var.enable_cloudwatch_logs
    log_group_name        = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.natgw_logs[0].name : ""
  }
}

# SSH Key Generation
resource "tls_private_key" "pk_nat" {
  count     = var.create_ssh_keys ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "rsa_nat" {
  count      = var.create_ssh_keys ? 1 : 0
  key_name   = "${var.name_prefix}-ssh-key-natgateway"
  public_key = tls_private_key.pk_nat[0].public_key_openssh
}

resource "aws_ssm_parameter" "nat_instance_ssh_key" {
  count       = var.create_ssh_keys ? local.nat_instance_count : 0
  name        = "/nat-instances/${var.name_prefix}-natgw-${count.index + 1}-ssh-key"
  description = "Chiave privata SSH per la ec2-nat ${count.index + 1}"
  type        = "SecureString"
  value       = tls_private_key.pk_nat[0].private_key_pem
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



resource "aws_network_interface" "natgw_private" {
  count             = local.nat_instance_count
  subnet_id         = var.private_subnet_ids[count.index]
  description       = "Private ENI for ${var.name_prefix}-eth0-natgw-${count.index + 1}"
  security_groups   = [aws_security_group.natgw_private[count.index].id]
  source_dest_check = false

  tags = {
    Name = "${var.name_prefix}-eth1-natgw-${count.index + 1}-private"
  }
}

# Routes
resource "aws_route" "private_subs" {
  count                  = length(var.private_route_table_ids)
  route_table_id         = var.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.natgw_private[var.nat_instance_per_az ? count.index : 0].id
}


# Elastic IP for instance primary network interface
resource "aws_eip" "nat_eip" {
  count             = local.nat_instance_count
  network_interface = aws_instance.nat_instance[count.index].primary_network_interface_id
  domain            = "vpc"

  tags = {
    Name = "${var.name_prefix}-natgw-${count.index + 1}-az-${element(["a", "b", "c"], count.index)}"
  }
}


locals {
  ami_values = {
    "arm" = "al2023-ami-2023.*-kernel-*-arm64"
    "x86" = "al2023-ami-2023.*-kernel-*-x86_64"
  }
}



# Determina l'architettura in base al tipo di istanza
locals {
  is_arm       = can(regex("^[a-z0-9]+g\\.", var.instance_type)) # Cerca il suffisso "g." nel tipo di istanza
  architecture = local.is_arm ? "arm" : "x86"                    # Se è ARM, usa "arm64", altrimenti "x86_64"
}

# AMI Data Source - Finds latest Amazon Linux 2023 AMI
# AWS CLI commands to find AMI manually:
# For ARM64: aws ec2 describe-images --owners amazon --filters 'Name=name,Values=al2023-ami-*-kernel-*-arm64' 'Name=virtualization-type,Values=hvm' --query 'Images[*].[ImageId,Name,CreationDate]' --output table --region <your-region>
# For x86_64: aws ec2 describe-images --owners amazon --filters 'Name=name,Values=al2023-ami-*-kernel-*-x86_64' 'Name=virtualization-type,Values=hvm' --query 'Images[*].[ImageId,Name,CreationDate]' --output table --region <your-region>
data "aws_ami" "latest_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [local.is_arm ? "al2023-ami-2023.*-kernel-*-arm64" : "al2023-ami-2023.*-kernel-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  owners = ["amazon"]
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "natgw_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/ec2/natgw/logs"
  retention_in_days = var.log_retention_days
}

# EC2 Instance - Native Terraform Resources
resource "aws_instance" "nat_instance" {
  count                = local.nat_instance_count
  ami                  = var.ami_id != null ? var.ami_id : data.aws_ami.latest_ami.id
  instance_type        = var.instance_type
  key_name             = var.create_ssh_keys ? aws_key_pair.rsa_nat[0].key_name : null
  iam_instance_profile = aws_iam_instance_profile.ec2-nat-ssm-cloudwatch-instance-profile.name
  user_data_base64     = base64encode(
    var.user_data_script != "" ? 
    file(var.user_data_script) : 
    templatefile("${path.module}/ec2_conf/userdata.tpl", local.userdata_template_vars)
  )

  # Launch in public subnet
  subnet_id              = var.public_subnet_ids[count.index]
  vpc_security_group_ids = [aws_security_group.natgw_public[count.index].id]

  # Enable IMDSv2
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # CPU Credits for burstable instances
  credit_specification {
    cpu_credits = var.credits_mode
  }

  # Root block device
  root_block_device {
    delete_on_termination = var.disk_configuration.delete_on_termination
    encrypted             = var.disk_configuration.encrypted
    iops                  = var.disk_configuration.iops
    kms_key_id            = var.disk_configuration.kms_key_id
    throughput            = var.disk_configuration.throughput
    volume_size           = var.disk_configuration.size
    volume_type           = var.disk_configuration.type
    tags                  = var.disk_configuration.tags
  }

  tags = {
    Name = "${var.name_prefix}-natgw-${count.index + 1}"
  }

}

# Network Interface Attachment for private interface
resource "aws_network_interface_attachment" "nat_private" {
  count                = local.nat_instance_count
  instance_id          = aws_instance.nat_instance[count.index].id
  network_interface_id = aws_network_interface.natgw_private[count.index].id
  device_index         = 1
}

