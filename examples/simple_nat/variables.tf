#######################################
# VARIABLES FOR VPC
#######################################

# if set to 0 use nat instances
# if set to 1 use NAT GATEWAY service with a single nat gateway per VPC
# if set to 2 use NAT GATEWAY service with 1 nat gateway per AZ

variable "vpc_natgw" {
  default     = 0
  description = "Set to 0 to use nat instances, set to 1 to use NAT GATEWAY service, set to 2 to use NAT GATEWAY service with 1 nat gateway per AZ"
  type        = number
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
}

variable "profile_name" {
  description = "AWS profile name"
  type        = string
}

# Variable for instance type
variable "instance_type" {
  type        = string
  description = "EC2 instance type to use as NAT instance"
  default     = "t4g.nano"
}

variable "ami_id" {
  type        = string
  description = "AMI ID, make sure to select AMI based on ARM or x86 platform"
  default     = "ami-0adb87b81434a4f85"
}


variable "vpc_natgw_distribution" {
  description = "Distribution of NAT Gateway instances across the NAT Gateway subnets. Valid values are: SINGLE, MULTI-AZ"
  type        = string
  default     = "MULTI-AZ"
  validation {
    condition     = contains(["SINGLE", "MULTI-AZ"], upper(var.vpc_natgw_distribution))
    error_message = "vpc_natgw_distribution must be one of: SINGLE or MULTI-AZ"
  }
}


variable "vpc_natgw_service_type" {
  description = "Type of NAT Gateway service to use. Valid values are: MANAGED (AWS NAT Gateway) or NAT_INSTANCE (Amazon Linux NAT Instance)"
  type        = string
  default     = "NAT_INSTANCE"
  validation {
    condition     = contains(["MANAGED", "NAT_INSTANCE"], upper(var.vpc_natgw_service_type))
    error_message = "vpc_natgw_service_type must be one of: MANAGED or NAT_INSTANCE"
  }
}
