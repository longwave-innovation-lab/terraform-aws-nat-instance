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
  description = "id of ami"
  type        = string
  default     = ""
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
  description = "Path to the custom user data script. By default the Nat Instance/s use [this userdata](https://github.com/Longwave-innovation/terraform-aws-nat-instance/blob/main/ec2_conf/default_userdata.sh)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type        = string
  default     = 7
  description = "Log retention in days"
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for NAT instances"
  type        = bool
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
    size                  = 30
  }
  description = "Disk configuration for NAT instances"
}

variable "credits_mode" {
  type        = string
  default     = "unlimited"
  description = "Credits mode for NAT instances. Can be `standard` or `unlimited`"
}

# variable "ami_owner" {
#   description = "id owner ami"
#   type        = string
# }

# variable "instance_arch" {
#   description = "architettura ec2"
#   type        = string
# }