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

# variable "ami_owner" {
#   description = "id owner ami"
#   type        = string
# }

# variable "instance_arch" {
#   description = "architettura ec2"
#   type        = string
# }