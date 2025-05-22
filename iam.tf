
# Creazione di un ruolo IAM per l'istanza EC2
resource "aws_iam_role" "ec2-nat-ssm-cloudwatch" {
  name_prefix = "${var.name_prefix}-nat-logs-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2-nat-ssm-cloudwatch-instance-profile" {
  name_prefix = "${var.name_prefix}-ec2-nat-ssm-cloudwatch-"
  role = aws_iam_role.ec2-nat-ssm-cloudwatch.name
}

# Attach cloudwatch Policy
resource "aws_iam_role_policy_attachment" "cloudwatch-nat-logs-policy2" {
  role     = aws_iam_role.ec2-nat-ssm-cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach SSM Policy
resource "aws_iam_role_policy_attachment" "ssm-nat-policy2" {
  role       = aws_iam_role.ec2-nat-ssm-cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
