
############################
# 1. VPC
############################

module "vpc" {
  source                = "terraform-aws-modules/vpc/aws"
  version               = "6.0.1"                                 # Verifica l'ultima versione disponibile
  name                  = "VPC-${random_string.random_id.result}" # non deve iniziare con un numero!!!!
  cidr                  = "192.168.0.0/19"
  azs                   = ["${var.aws_region}a", "${var.aws_region}b"] # Sostituisci con le tue zone di disponibilità
  private_subnets       = ["192.168.1.0/24", "192.168.2.0/24"]
  private_subnet_names  = ["${random_string.random_id.result} Private Subnet 1a", "${random_string.random_id.result} Private Subnet 2b"]
  public_subnets        = ["192.168.10.0/24", "192.168.11.0/24"]
  public_subnet_names   = ["${random_string.random_id.result} Public Subnet 1a", "${random_string.random_id.result} Public Subnet 2b"]
  database_subnets      = ["192.168.20.0/24", "192.168.21.0/24"]
  database_subnet_names = ["${random_string.random_id.result} Database Subnet 1a", "${random_string.random_id.result} Database Subnet 2b"]

  create_database_subnet_group = true
  enable_dns_support           = true
  enable_dns_hostnames         = true
  create_igw                   = true
  ## se la variabile vpc_natgw è impostato su "1", allora enable_nat_gateway 
  # e single_nat_gateway saranno impostati su true e one_nat_gateway_per_az su false. 
  # Se vpc_natgw è impostato su "2", allora enable_nat_gateway sarà impostato su true, 
  # single_nat_gateway su false e one_nat_gateway_per_az su true. Altrimenti, tutte 
  #le opzioni saranno impostate su false
  # enable_nat_gateway     = var.vpc_natgw == 0 ? false : true
  # single_nat_gateway     = var.vpc_natgw == 2 ? false : var.vpc_natgw == 1 ? true : false
  # one_nat_gateway_per_az = var.vpc_natgw == 2 ? true : false

  enable_nat_gateway     = var.vpc_natgw_service_type == "MANAGED" ? true : false
  single_nat_gateway     = var.vpc_natgw_distribution == "SINGLE" ? true : false
  one_nat_gateway_per_az = var.vpc_natgw_distribution == "MULTI-AZ" ? true : false

  ## One NAT Gateway per VPC
  # enable_nat_gateway = true
  # single_nat_gateway = true
  # one_nat_gateway_per_az = false
  ## One NAT Gateway per availability zone
  # enable_nat_gateway = true
  # single_nat_gateway = false
  # one_nat_gateway_per_az = true

  # Configura le opzioni del NAT Gateway in 
  # base al valore della variabile vpc_natgw. 
  # Se vpc_natgw è 0, il NAT Gateway non viene abilitato. 
  # Se è impostato su 1, verrà creato un NAT Gateway singolo per l'intera VPC. 
  # Se è impostato su 2, verrà creato un NAT Gateway per ogni zona di disponibilità.
}

module "nat_gateway" {
  count                   = var.vpc_natgw_service_type == "NAT_INSTANCE" ? 1 : 0
  source                  = "../../"
  vpc_id                  = module.vpc.vpc_id
  public_subnet_ids       = module.vpc.public_subnets
  private_subnet_ids      = module.vpc.private_subnets
  private_route_table_ids = module.vpc.private_route_table_ids
  name_prefix             = local.name_prefix
  nat_instance_per_az     = var.vpc_natgw_distribution == "MULTI-AZ" ? true : false
  instance_type           = var.instance_type
  # if ami_id is null set latest
  #ami_id                  = var.ami_id
  enable_cloudwatch_logs  = true
}

