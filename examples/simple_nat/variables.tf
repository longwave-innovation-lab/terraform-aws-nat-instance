#######################################
# VARIABILI PER VPC 
#######################################

# se lo imposto a 0 uso le istanze nat
# se lo imoposto a 1 uso il servizio NAT GARTEWAY con un solo nat gateway per VPC
# se lo imposto a 2 uso il servizio NAT GARTEWAY con 1 nat gateway per ogni AZ 

variable "vpc_natgw" {
  default     = 0
  description = "imposto a 0 uso le istanze nat, imoposto a 1 uso il servizio NAT GARTEWAY, imposto a 2 uso il servizio NAT GARTEWAY con 1 nat gateway per ogni AZ "
  type        = number
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
}

variable "profile_name" {
  description = "Nome del profilo di aws"
  type        = string
}

# Variabile per il tipo di istanza
variable "instance_type" {
  type        = string
  description = "il tipo di ec2 da attivare come istanza nat"
  default     = "t4g.nano"
}

variable "ami_id" {
  type        = string
  description = "id della ami, attenzione a selezionare AMI in base alla piattaforma ARM o x86"
  default     = "ami-0adb87b81434a4f85"
}


variable "vpc_natgw_distribution" {
  description = "Distribution of NAT Gateway instances across the NAT Gateway subnets. Valid values are: SINGLE, MULTI-AZ"
  type        = string
  default     = "SINGLE"
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