variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "List of private route table IDs"
  type        = list(string)
}

variable "name_prefix" {
  description = "Random name prefix for resources"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for NAT instances. If null, uses latest Amazon Linux 2023. To find AMI: aws ec2 describe-images --owners amazon --filters 'Name=name,Values=al2023-ami-2023.*-kernel-*-arm64' 'Name=virtualization-type,Values=hvm' --query 'Images[*].[ImageId,Name,CreationDate]' --output table --region <your-region>"
  type        = string
  default     = null
}

variable "nat_instance_per_az" {
  description = "Whether to create a NAT instance per AZ or a single NAT instance for all AZs"
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "EC2 instance type for NAT instances"
  type        = string
  default     = "t4g.nano"
}

variable "create_ssh_keys" {
  type        = bool
  default     = false
  description = "Create ssh keys for the NAT instance/s"
}

variable "user_data_script" {
  description = "Path to the custom user data script. By default use /ec2_conf/userdata.tpl"
  type        = string
  default     = ""
}

variable "disk_configuration" {
  type = object({
    delete_on_termination = optional(bool),
    encrypted             = optional(bool),
    iops                  = optional(number),
    kms_key_id            = optional(string),
    tags                  = optional(map(string)),
    throughput            = optional(number),
    size                  = optional(number),
    type                  = optional(string)
  })
  default = {
    delete_on_termination = true,
    type                  = "gp3",
    encrypted             = true,
    size                  = 30 #snapshot ami required min 30GB of storage.
  }
  description = "Disk configuration for NAT instances"
}

variable "credits_mode" {
  type        = string
  default     = "unlimited"
  description = "Credits mode for NAT instances. Can be `standard` or `unlimited`"
}

# ============================================================================
# Lambda Internet Connectivity Check Variables
# ============================================================================

variable "enable_internet_check" {
  description = "Enable Lambda-based internet connectivity check for private subnets"
  type        = bool
  default     = true
}

variable "internet_check_alert_emails" {
  description = "List of email addresses for internet connectivity check alerts. Leave empty to skip email subscriptions"
  type        = list(string)
  default     = ["innovation_rd@longwave.it"]
}

variable "internet_check_schedule_expression" {
  description = "CloudWatch Event schedule expression for internet check (e.g., 'rate(5 minutes)')"
  type        = string
  default     = "rate(5 minutes)"
}

variable "internet_check_schedule_minutes" {
  description = "Schedule interval in minutes for internet check (used only for description)"
  type        = number
  default     = 5
}

variable "internet_check_log_retention_days" {
  description = "CloudWatch log retention in days for internet check Lambda functions"
  type        = number
  default     = 7
}

variable "internet_check_evaluation_periods" {
  description = "Number of periods to evaluate for the internet check alarm"
  type        = number
  default     = 2
}

variable "internet_check_period" {
  description = "Period in seconds for the internet check alarm metric"
  type        = number
  default     = 300
}

variable "internet_check_threshold" {
  description = "Threshold for the internet check alarm (number of successful checks)"
  type        = number
  default     = 1
}

variable "internet_check_urls" {
  description = "List of HTTPS URLs to check for internet connectivity"
  type        = list(string)
  default     = ["https://1.1.1.1", "https://dns.google/resolve?name=google.com"]
}
