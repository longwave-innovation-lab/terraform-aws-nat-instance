# Simple example

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_random"></a> [random](#provider\_random) | 3.7.2 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_nat_gateway"></a> [nat\_gateway](#module\_nat\_gateway) | ../../ | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | 6.0.1 |

## Resources

| Name | Type |
|------|------|
| [random_string.random_id](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS Region | `string` | n/a | yes |
| <a name="input_profile_name"></a> [profile\_name](#input\_profile\_name) | Nome del profilo di aws | `string` | n/a | yes |
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | id della ami, attenzione a selezionare AMI in base alla piattaforma ARM o x86 | `string` | `"ami-0adb87b81434a4f85"` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | il tipo di ec2 da attivare come istanza nat | `string` | `"t4g.nano"` | no |
| <a name="input_vpc_natgw"></a> [vpc\_natgw](#input\_vpc\_natgw) | imposto a 0 uso le istanze nat, imoposto a 1 uso il servizio NAT GARTEWAY, imposto a 2 uso il servizio NAT GARTEWAY con 1 nat gateway per ogni AZ | `number` | `0` | no |
| <a name="input_vpc_natgw_distribution"></a> [vpc\_natgw\_distribution](#input\_vpc\_natgw\_distribution) | Distribution of NAT Gateway instances across the NAT Gateway subnets. Valid values are: SINGLE, MULTI-AZ | `string` | `"SINGLE"` | no |
| <a name="input_vpc_natgw_service_type"></a> [vpc\_natgw\_service\_type](#input\_vpc\_natgw\_service\_type) | Type of NAT Gateway service to use. Valid values are: MANAGED (AWS NAT Gateway) or NAT\_INSTANCE (Amazon Linux NAT Instance) | `string` | `"NAT_INSTANCE"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_nat_instances"></a> [nat\_instances](#output\_nat\_instances) | Details of NAT instances |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | Id VPC |
<!-- END_TF_DOCS -->