<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_nat_gateway"></a> [nat\_gateway](#module\_nat\_gateway) | ../../ | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | 6.6.0 |

## Resources

| Name | Type |
|------|------|
| [random_string.random_id](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS Region | `string` | n/a | yes |
| <a name="input_profile_name"></a> [profile\_name](#input\_profile\_name) | AWS profile name | `string` | n/a | yes |
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI ID, make sure to select AMI based on ARM or x86 platform | `string` | `"ami-0adb87b81434a4f85"` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type to use as NAT instance | `string` | `"t4g.nano"` | no |
| <a name="input_vpc_natgw"></a> [vpc\_natgw](#input\_vpc\_natgw) | Set to 0 to use nat instances, set to 1 to use NAT GATEWAY service, set to 2 to use NAT GATEWAY service with 1 nat gateway per AZ | `number` | `0` | no |
| <a name="input_vpc_natgw_distribution"></a> [vpc\_natgw\_distribution](#input\_vpc\_natgw\_distribution) | Distribution of NAT Gateway instances across the NAT Gateway subnets. Valid values are: SINGLE, MULTI-AZ | `string` | `"MULTI-AZ"` | no |
| <a name="input_vpc_natgw_service_type"></a> [vpc\_natgw\_service\_type](#input\_vpc\_natgw\_service\_type) | Type of NAT Gateway service to use. Valid values are: MANAGED (AWS NAT Gateway) or NAT\_INSTANCE (Amazon Linux NAT Instance) | `string` | `"NAT_INSTANCE"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_nat_instances"></a> [nat\_instances](#output\_nat\_instances) | Details of NAT instances |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | Id VPC |
<!-- END_TF_DOCS -->