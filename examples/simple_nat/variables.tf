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
