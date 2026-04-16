

locals {
  az_count           = length(var.public_subnet_ids)
  nat_instance_count = var.nat_instance_per_az ? local.az_count : 1
  ami_values = {
    "arm" = "al2023-ami-2023.*-kernel-*-arm64"
    "x86" = "al2023-ami-2023.*-kernel-*-x86_64"
  }
  is_arm       = can(regex("^[a-z0-9]+g\\.", var.instance_type)) # Look for "g." suffix in instance type
  architecture = local.is_arm ? "arm" : "x86"                    # If ARM, use "arm64", otherwise "x86_64"
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
  description = "SSH private key for ec2-nat ${count.index + 1}"
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


# Elastic IP - allocation only, no inline association.
# Inline association causes lifecycle issues when switching SINGLE → MULTI-AZ:
# Terraform would attempt to associate the EIP with already-terminated instances.
# A separate aws_eip_association resource guarantees the correct order:
# de-associate EIP → destroy instance → create new instance → re-associate EIP.
resource "aws_eip" "nat_eip" {
  count  = local.nat_instance_count
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-natgw-${count.index + 1}-az-${element(["a", "b", "c"], count.index)}"
  }
}

# Separate EIP association to correctly manage lifecycle.
# Uses network_interface_id (primary/public ENI, eth0) instead of instance_id:
# with two ENIs attached, AWS requires specifying the interface explicitly.
resource "aws_eip_association" "nat_eip" {
  count                = local.nat_instance_count
  allocation_id        = aws_eip.nat_eip[count.index].id
  network_interface_id = aws_instance.nat_instance[count.index].primary_network_interface_id

  depends_on = [
    aws_instance.nat_instance,
    aws_network_interface_attachment.nat_private,
  ]
}

# Trigger for forced recreation of NAT instances when nat_instance_count changes.
# When nat_instance_per_az changes (SINGLE→MULTI-AZ or vice versa), this resource
# is replaced, activating replace_triggered_by on aws_instance.nat_instance.
resource "terraform_data" "nat_instance_trigger" {
  input = local.nat_instance_count
}

# AMI Data Source - Finds latest Amazon Linux 2023 AMI
# AWS CLI commands to find AMI manually:
# For ARM64: aws ec2 describe-images --owners amazon --filters 'Name=name,Values=al2023-ami-*-kernel-*-arm64' 'Name=virtualization-type,Values=hvm' --query 'Images[*].[ImageId,Name,CreationDate]' --output table --region <your-region>
# For x86_64: aws ec2 describe-images --owners amazon --filters 'Name=name,Values=al2023-ami-*-kernel-*-x86_64' 'Name=virtualization-type,Values=hvm' --query 'Images[*].[ImageId,Name,CreationDate]' --output table --region <your-region>
data "aws_ami" "latest_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-*"]
  }

  filter {
    name   = "architecture"
    values = [local.is_arm ? "arm64" : "x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}
# EC2 Instance - Native Terraform Resources
resource "aws_instance" "nat_instance" {
  count                = local.nat_instance_count
  ami                  = var.ami_id != null ? var.ami_id : data.aws_ami.latest_ami.id
  instance_type        = var.instance_type
  key_name             = var.create_ssh_keys ? aws_key_pair.rsa_nat[0].key_name : null
  iam_instance_profile = aws_iam_instance_profile.ec2_nat_ssm_cloudwatch_instance_profile.name
  user_data_base64 = base64encode(
    var.user_data_script != "" ?
    file(var.user_data_script) :
    file("${path.module}/ec2_conf/userdata.tpl")
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

  # Forced recreation when nat_instance_count changes (SINGLE→MULTI-AZ or vice versa).
  # Ensures all instances are recreated with updated userdata and correct routing
  # instead of leaving existing instances in an inconsistent state.
  lifecycle {
    replace_triggered_by = [terraform_data.nat_instance_trigger]
  }

}

# Network Interface Attachment for private interface
resource "aws_network_interface_attachment" "nat_private" {
  count                = local.nat_instance_count
  instance_id          = aws_instance.nat_instance[count.index].id
  network_interface_id = aws_network_interface.natgw_private[count.index].id
  device_index         = 1
}
