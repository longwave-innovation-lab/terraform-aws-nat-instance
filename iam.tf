
# Create IAM role for EC2 instance
resource "aws_iam_role" "ec2_nat_ssm_cloudwatch" {
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
resource "aws_iam_instance_profile" "ec2_nat_ssm_cloudwatch_instance_profile" {
  name_prefix = "${var.name_prefix}-ec2-nat-ssm-cloudwatch-"
  role        = aws_iam_role.ec2_nat_ssm_cloudwatch.name
}

# Attach cloudwatch Policy
resource "aws_iam_role_policy_attachment" "cloudwatch_nat_logs_policy" {
  role       = aws_iam_role.ec2_nat_ssm_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach SSM Policy
resource "aws_iam_role_policy_attachment" "ssm_nat_policy" {
  role       = aws_iam_role.ec2_nat_ssm_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# add policy to describe in userdata
resource "aws_iam_role_policy" "ec2_describe_network_policy" {
  name = "${var.name_prefix}-describe-network-policy"
  role = aws_iam_role.ec2_nat_ssm_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteTables",
          "ec2:DescribeInternetGateways"
        ]
        Resource = "*"
      }
    ]
  })
}
