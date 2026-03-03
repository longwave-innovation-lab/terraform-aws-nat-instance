# AWS NAT Gateway/Instance Terraform Module <!-- omit in toc -->

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Module Key Features](#module-key-features)
- [Architecture](#architecture)
  - [Configuration](#configuration)
  - [Security Groups](#security-groups)
  - [IAM Configuration](#iam-configuration)
- [Default User Data Script Details](#default-user-data-script-details)
  - [Initialization Steps](#initialization-steps)
    - [1. Connectivity Test and Validation](#1-connectivity-test-and-validation)
    - [2. System Update and Package Installation](#2-system-update-and-package-installation)
    - [3. IP Forwarding Configuration](#3-ip-forwarding-configuration)
    - [4. Network Interface Identification](#4-network-interface-identification)
    - [5. VPC Routing Configuration](#5-vpc-routing-configuration)
    - [6. nftables Configuration for NAT Functionality](#6-nftables-configuration-for-nat-functionality)
    - [7. Logging Configuration (if `enable_cloudwatch_logs = true`)](#7-logging-configuration-if-enable_cloudwatch_logs--true)
    - [8. CloudWatch Agent Configuration](#8-cloudwatch-agent-configuration)
  - [Template Variables](#template-variables)
  - [Created Files and Services](#created-files-and-services)
- [Notes and Best Practices](#notes-and-best-practices)
- [Troubleshooting](#troubleshooting)
- [Requirements](#requirements)
- [Providers](#providers)
- [Modules](#modules)
- [Resources](#resources)
- [Inputs](#inputs)
- [Outputs](#outputs)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

This Terraform module provides a flexible way to manage NAT Instances in your AWS Virtual Private Cloud (VPC). The example shows how to use both NAT Gateways (AWS-managed) and NAT Instances (EC2 instances acting as NAT). You can choose between a single NAT Gateway for the entire VPC, one NAT Gateway per Availability Zone, or using NAT Instances.

The selection is dynamically controlled via the `vpc_natgw` variable:

- `vpc_natgw = 0`: Creates one or more custom NAT Instances.  
- `vpc_natgw = 1`: Creates a single NAT Gateway for the entire VPC.  
- `vpc_natgw = 2`: Creates a NAT Gateway for each Availability Zone (AZ).  

## Module Key Features

- Flexible deployment options (single-AZ or multi-AZ)  
- Automatic routing table configuration  
- Integration with CloudWatch for monitoring and logging  
- Full security group management  
- ARM and x86 architecture support  
- Automatic iptables/nftables configuration and logging to CloudWatch  
- SSM profile enabled on NAT Instance to also use it as a bastion host or for reverse port forwarding  
- Private SSH key saved to AWS Parameter Store and locally  

## Architecture

### Configuration

- NAT instances with dual network interfaces:  
  - `eth0`: Public interface in the public subnet  
  - `eth1`: Private interface in the private subnet  
- Source/destination check disabled on private interface  
- Elastic IPs associated with public interfaces  
- Amazon Linux 2023 OS  

### Security Groups

1. Public Interface (`eth0`):  
   - Allows all outbound traffic  
   - Restricts inbound traffic to established connections  

2. Private Interface (`eth1`):  
   - Allows all inbound traffic from private subnets  
   - Allows all outbound traffic  

### IAM Configuration

Creates an IAM role with:  

- Permissions for CloudWatch Agent  
- Access to Systems Manager (SSM)  

## Default User Data Script Details

The script [`userdata.tpl`](./ec2_conf/userdata.tpl) is a Terraform template using `templatefile` to dynamically configure NAT instances. It receives two variables:

- `enable_cloudwatch_logs`: Enable/disable CloudWatch logging  
- `log_group_name`: CloudWatch log group name (if enabled)  

### Initialization Steps

#### 1. Connectivity Test and Validation

Before installation, the script runs connectivity tests to ensure the instance can reach the Internet:

- **IP connectivity test**: Checks reachability to 8.8.8.8 and 1.1.1.1 (minimum 3 successful pings out of 10)  
- **DNS resolution test**: Checks resolution for google.com and cloudflare.com  
- **Automatic retries**: Up to 2 retries with 60 seconds between attempts  
- **Detailed logging**: All tests logged to `/var/log/user-data.log`  

If tests fail, the script exits with an error to avoid incomplete configuration.  

#### 2. System Update and Package Installation

Installs the following packages with automatic retry:

**Core Packages:**  
- `traceroute`, `tcpdump` – Network diagnostics  
- `amazon-cloudwatch-agent` – CloudWatch metrics and logging  
- `logrotate`, `rsyslog` – Log management  
- `nftables` – Firewall framework (replaces iptables)  

**Additional Packages:**  
- `amazon-ssm-agent` – Enables AWS Systems Manager access  

Retries up to 2 times with 30 seconds delay.

#### 3. IP Forwarding Configuration

Enables permanent IP forwarding for NAT functionality:

```bash
net.ipv4.ip_forward=1
```

Saved in `/etc/sysctl.d/99-ip-forward.conf` for persistence.

#### 4. Network Interface Identification

The script automatically identifies network interfaces (excluding loopback and Docker):

- **PUBLIC_INTERFACE** (`eth0/ens5`): first interface, connected to the public subnet  
- **PRIVATE_INTERFACE** (`eth1/ens6`): second interface, connected to the private subnet  

#### 5. VPC Routing Configuration

Retrieves AWS metadata to configure correct routing:

1. Retrieves VPC ID from Instance Metadata Service (IMDSv2)  
2. Retrieves VPC CIDR block via AWS CLI  
3. Adds a static route for VPC traffic via the private interface  
4. Creates a systemd service (`custom-routes.service`) to make the route persistent  

#### 6. nftables Configuration for NAT Functionality

Configures **nftables** with the following chains:

**INPUT Chain:**  
- Accept all loopback traffic  
- Accept all traffic from private interface  
- Accept only ESTABLISHED/RELATED traffic from public interface  
- Accept ICMP echo-request/reply from private interface  
- Logs and drops all other traffic (if logging enabled)  

**FORWARD Chain:**  
- Forward from private → public interface  
- Forward from public → private only for ESTABLISHED/RELATED connections  
- Logs private→public traffic if logging enabled  
- Drops all other traffic  

**OUTPUT Chain:**  
- Allow all outbound traffic on the public interface  

**POSTROUTING (NAT) Chain:**  
- Applies masquerading to all outbound traffic from the public interface  

Rules are saved to:

- `/etc/nftables/nat-instance.nft` – main configuration  
- `/etc/sysconfig/nftables.conf` – persistent copy  

A systemd service (`nftables-nat.service`) ensures rules are automatically loaded at boot.

#### 7. Logging Configuration (if `enable_cloudwatch_logs = true`)

If enabled:

- **Local log file:** `/var/log/iptables.log`  
- rsyslog filters messages with the prefix `NFTables-`  
- Logrotate rotates hourly (keeps 1 hour, max 10MB)  

**Log prefixes:**  
- `NFTables-PRIV-to-PUB:` – traffic from private → public  
- `NFTables-Dropped-PRIVATE-IN:` – dropped inbound private traffic  
- `NFTables-Dropped-FORWARD:` – dropped forward traffic  

#### 8. CloudWatch Agent Configuration

CloudWatch Agent is configured with custom metrics:

- **Namespace:** `EC2/NATinstance`  
- **Metrics (interval 60s):** `disk_used_percent`, `memory_used_percent`, `swap_used_percent`  
- **Dimensions:** `InstanceId`, `InstanceType`  
- **Log streaming (if enabled):** `/var/log/iptables.log` → CloudWatch log group  

Configuration is saved to:  
`/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`

### Template Variables

| Variable | Type | Description |
|----------|------|-------------|
| `enable_cloudwatch_logs` | bool | Enable nftables CloudWatch logging |
| `log_group_name` | string | CloudWatch log group name (used only if logging enabled) |

### Created Files and Services

**Configuration Files:**  
- `/etc/sysctl.d/99-ip-forward.conf` – IP forwarding  
- `/etc/nftables/nat-instance.nft` – nftables rules  
- `/etc/sysconfig/nftables.conf` – persistent rules  
- `/etc/rsyslog.d/10-nftables.conf` – rsyslog config  
- `/etc/logrotate.d/nat-traffic` – log rotation  
- `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json` – CloudWatch agent  

**Systemd Services:**  
- `custom-routes.service` – maintain static VPC routes  
- `nftables-nat.service` – load nftables rules on boot  
- `amazon-ssm-agent.service` – SSM access  
- `amazon-cloudwatch-agent.service` – metrics/logs  

**Log Files:**  
- `/var/log/user-data.log` – script execution logs  
- `/var/log/iptables.log` – nftables traffic logs (if enabled)  

## Notes and Best Practices

1. High Availability
   - For production environments, consider enabling nat_instance_per_az or nat gateway service
   - Implement appropriate monitoring and alerting

2. Iptables Logs
   - logs inside NAT instances are saved in /var/log/iptables.log

3. Cloudwatch Configuration
   - the cloudwatch agent configuration is saved in /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

## Troubleshooting

1. Ping from NAT instance using private interface

  ```sh
  ping -I ens5 -c 4 8.8.8.8
  ```

2. Check routing table

  ```sh
  ip route show
  ```

3. Check if IP forwarding is enabled

  ```sh
  sysctl net.ipv4.ip_forward
  ```

   If the value is 0, reactivate it with:

  ```sh
  echo 1 > /proc/sys/net/ipv4/ip_forward
  ```

   > **WARNING**: verify that the configuration file contains only
   > <br>**net.ipv4.ip_forward=1**
   > <br>If different (e.g. **net.ipv4.ip_forward=1**) it might cause issues.

4. Check active iptables rules

  ```sh
  iptables -L -v -n
  ```

5. Check active iptables rules for NAT

  ```sh
  iptables -t nat -L -v -n
  ```

6. iptables reset counters visible with the command iptables -L -v -n

  ```sh
  iptables -Z
  ```

7. Monitor traffic in real-time with tcpdump
   <br>To verify if ICMP packets (ping) reach the NAT instance:
   instance:

   ```sh
   tcpdump -i $PRIVATE_INTERFACE icmp
   ```

   To see if traffic is passing correctly between interfaces:

   ```sh
   tcpdump -i $PUBLIC_INTERFACE icmp
   ```

   monitor all traffic on a specific interface

   ```sh
   tcpdump -i $PRIVATE_INTERFACE
   ```

8. Check iptables logs

   ```sh
   tail -f /var/log/iptables.log`
   ```

9. To see which connections are currently established through the NAT instance:

  ```sh
   netstat -nat
   ```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> aws #requirement\_aws | >= 6.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.natgw_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/
cloudwatch_log_group) | resource |
| [aws_eip.nat_eip](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_iam_instance_profile.ec2-nat-ssm-cloudwatch-instance-profile](https://registry.terraform.io/providers/
hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.ec2-nat-ssm-cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/
iam_role) | resource |
| [aws_iam_role_policy.ec2-describe-network-policy](https://registry.terraform.io/providers/hashicorp/aws/latest/
docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cloudwatch-nat-logs-policy2](https://registry.terraform.io/providers/hashicorp/aws
/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ssm-nat-policy2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs
/resources/iam_role_policy_attachment) | resource |
| [aws_instance.nat_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance)
| resource |
| [aws_key_pair.rsa_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) |
resource |
| [aws_network_interface.natgw_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/
network_interface) | resource |
| [aws_network_interface_attachment.nat_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/
resources/network_interface_attachment) | resource |
| [aws_route.private_subs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) |
resource |
| [aws_security_group.natgw_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/
security_group) | resource |
| [aws_security_group.natgw_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/
security_group) | resource |
| [aws_ssm_parameter.nat_instance_ssh_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/
resources/ssm_parameter) | resource |
| [tls_private_key.pk_nat](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key)
| resource |
| [aws_ami.latest_ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data
source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Random name prefix for resources | string
| n/a | yes |
| <a name="input_private_route_table_ids"></a> [private\_route\_table\_ids](#input\_private\_route\_table\_ids) |
List of private route table IDs | list(string) | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of private
subnet IDs | list(string) | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | List of public subnet
IDs | list(string) | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC | string | n/a | yes |
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI ID for NAT instances. If null, uses latest Amazon
Linux 2023. To find AMI: aws ec2 describe-images --owners amazon --filters 'Name=name,Values=al2023-ami-2023.*-
kernel-*-arm64' 'Name=virtualization-type,Values=hvm' --query 'Images[*].[ImageId,Name,CreationDate]' --output table
--region <your-region> | string | null | no |
| <a name="input_create_ssh_keys"></a> [create\_ssh\_keys](#input\_create\_ssh\_keys) | Create ssh keys for the NAT
instance/s | bool | false | no |
| <a name="input_credits_mode"></a> [credits\_mode](#input\_credits\_mode) | Credits mode for NAT instances. Can be
standard or unlimited | string | "unlimited" | no |
| <a name="input_disk_configuration"></a> [disk\_configuration](#input\_disk\_configuration) | Disk configuration
for NAT instances | <pre>object({<br/>    delete_on_termination = optional(bool),<br/>    encrypted             =
optional(bool),<br/>    iops                  = optional(number),<br/>    kms_key_id            = optional(string),<
br/>    tags                  = optional(map(string)),<br/>    throughput            = optional(number),<br/>
size                  = optional(number),<br/>    type                  = optional(string)<br/>  })</pre> | <pre>{<
br/>  "delete_on_termination": true,<br/>  "encrypted": true,<br/>  "size": 30,<br/>  "type": "gp3"<br/>}</pre> | no
|
| <a name="input_enable_cloudwatch_logs"></a> [enable\_cloudwatch\_logs](#input\_enable\_cloudwatch\_logs) | Enable
CloudWatch logging for NAT instances | bool | false | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for NAT instances
| string | "t4g.nano" | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Log retention in
days | string | 7 | no |
| <a name="input_nat_instance_per_az"></a> [nat\_instance\_per\_az](#input\_nat\_instance\_per\_az) | Whether to
create a NAT instance per AZ or a single NAT instance for all AZs | bool | false | no |
| <a name="input_user_data_script"></a> [user\_data\_script](#input\_user\_data\_script) | Path to the custom user
data script. By default use /ec2\_conf/userdata.tpl | string | "" | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_nat_instance_details"></a> [nat\_instance\_details](#output\_nat\_instance\_details) | Details of
NAT instances including ID and Public IP |
| <a name="output_nat_instance_ids"></a> [nat\_instance\_ids](#output\_nat\_instance\_ids) | IDs of the NAT EC2
instances |
| <a name="output_nat_public_ips"></a> [nat\_public\_ips](#output\_nat\_public\_ips) | Public IPs of the NAT
instances |
<!-- END_TF_DOCS -->