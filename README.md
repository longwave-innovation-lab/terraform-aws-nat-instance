# AWS NAT Instance Terraform Module <!-- omit in toc -->

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Module Key Features](#module-key-features)
  - [Security Groups](#security-groups)
- [Usage Example](#usage-example)
  - [Example Variables](#example-variables)
- [Default User Data Script Details (`ec2_conf/userdata.tpl`)](#default-user-data-script-details-ec2_confuserdatatpl)
  - [Step-by-Step Walkthrough](#step-by-step-walkthrough)
    - [Step 1 — Logging Setup](#step-1--logging-setup)
    - [Step 2 — Internet Connectivity Test](#step-2--internet-connectivity-test)
    - [Step 3 — DNS Resolution Test](#step-3--dns-resolution-test)
    - [Step 4 — System Update](#step-4--system-update)
    - [Step 5 — Core Packages Installation](#step-5--core-packages-installation)
    - [Step 6 — SSM Agent Installation and Activation](#step-6--ssm-agent-installation-and-activation)
    - [Step 7 — nftables Verification](#step-7--nftables-verification)
    - [Step 8 — IP Forwarding Configuration](#step-8--ip-forwarding-configuration)
    - [Step 9 — Network Interface Detection](#step-9--network-interface-detection)
    - [Step 10 — AWS Metadata Retrieval and VPC Routing](#step-10--aws-metadata-retrieval-and-vpc-routing)
    - [Step 11 — Persistent Route via systemd Service](#step-11--persistent-route-via-systemd-service)
    - [Step 12 — nftables NAT Configuration](#step-12--nftables-nat-configuration)
    - [Step 13 — nftables Persistence via systemd Service](#step-13--nftables-persistence-via-systemd-service)
    - [Step 14 — CloudWatch Agent Configuration](#step-14--cloudwatch-agent-configuration)
  - [Created Files and Services](#created-files-and-services)
- [Internet Connectivity Check (Lambda-based Monitoring)](#internet-connectivity-check-lambda-based-monitoring)
  - [How It Works](#how-it-works)
  - [Lambda Function (`lambda_function.py`)](#lambda-function-lambda_functionpy)
  - [Configuration](#configuration)
    - [Enable Monitoring (Default: Enabled)](#enable-monitoring-default-enabled)
    - [Disable Monitoring](#disable-monitoring)
    - [Full Configuration Example](#full-configuration-example)
  - [Variables](#variables)
  - [Outputs](#outputs)
  - [Resources Created](#resources-created)
  - [CloudWatch Metrics](#cloudwatch-metrics)
  - [Cost Estimate](#cost-estimate)
  - [Troubleshooting](#troubleshooting)
  - [Email Notifications Format](#email-notifications-format)
    - [Alarm State (Connectivity Lost)](#alarm-state-connectivity-lost)
    - [OK State (Connectivity Restored)](#ok-state-connectivity-restored)
- [Notes and Best Practices](#notes-and-best-practices)
- [Troubleshooting](#troubleshooting-1)
- [Requirements](#requirements)
- [Providers](#providers)
- [Modules](#modules)
- [Resources](#resources)
- [Inputs](#inputs)
- [Outputs](#outputs-1)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

This Terraform module provides a flexible way to deploy **NAT Instances** (EC2 instances acting as NAT gateways) in your AWS Virtual Private Cloud (VPC). The included example (`examples/simple_nat`) shows how to choose between AWS-managed NAT Gateways and custom NAT Instances.

The selection is dynamically controlled via two variables in the example:

| `vpc_natgw_service_type` | `vpc_natgw_distribution` | Behaviour |
|---|---|---|
| `NAT_INSTANCE` | `SINGLE` | Creates a single custom NAT Instance for the entire VPC |
| `NAT_INSTANCE` | `MULTI-AZ` | Creates one NAT Instance per Availability Zone |
| `MANAGED` | `SINGLE` | Creates a single AWS-managed NAT Gateway |
| `MANAGED` | `MULTI-AZ` | Creates one AWS-managed NAT Gateway per AZ |

## Module Key Features

- Flexible deployment options (single-AZ or multi-AZ via `nat_instance_per_az`)
- Automatic AMI selection for both **ARM** (`*g.*` instance types) and **x86** architectures (Amazon Linux 2023)
- Custom AMI support via `ami_id`
- Automatic routing table configuration for private subnets
- Dual network interface design (public + private)
- Full security group management
- nftables-based NAT and firewall configuration
- CloudWatch Agent for disk, memory and swap metrics
- SSM Agent enabled — use the NAT instance as a bastion host or for reverse port forwarding
- Optional SSH key generation with private key stored in AWS Systems Manager Parameter Store
- Optional Lambda-based internet connectivity monitoring with CloudWatch Alarms and SNS notifications
- Configurable disk, CPU credits and user data script

- NAT instances with dual network interfaces:  
  - `eth0`: Public interface in the public subnet  
  - `eth1`: Private interface in the private subnet  
- Source/destination check disabled on private interface  
- Elastic IPs associated with public interfaces  
- Amazon Linux 2023 OS  

### Security Groups

- NAT instances with dual network interfaces:
  - `eth0` (primary): Public interface in the public subnet — receives an Elastic IP
  - `eth1` (attached): Private interface in the private subnet — `source_dest_check = false`
- Amazon Linux 2023 OS (auto-selected based on instance architecture)
- IMDSv2 enforced (`http_tokens = "required"`)
- Burstable CPU credits mode configurable (`standard` or `unlimited`)

2. Private Interface (`eth1`):  
   - Allows all inbound traffic from private subnets  
   - Allows all outbound traffic  

1. **Public Interface** (`eth0`):
   - Egress: allows all outbound traffic
   - Ingress: none (only established/related connections via nftables)

2. **Private Interface** (`eth1`):
   - Ingress: allows all traffic (from private subnets)
   - Egress: allows all outbound traffic

- Permissions for CloudWatch Agent  
- Access to Systems Manager (SSM)  

Creates an IAM role (`iam.tf`) with:

- **CloudWatchAgentServerPolicy** — for CloudWatch Agent metrics
- **AmazonSSMManagedInstanceCore** — for Systems Manager (SSM) access
- Custom inline policy for `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, `ec2:DescribeRouteTables`, `ec2:DescribeInternetGateways` — used by the user data script to retrieve VPC CIDR

## Usage Example

The `examples/simple_nat/` directory contains a complete working example:

```hcl
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

  # Internet Connectivity Check (Lambda-based monitoring)
  enable_internet_check                = true
  internet_check_schedule_expression   = "rate(5 minutes)"
  internet_check_log_retention_days    = 7
  internet_check_evaluation_periods    = 2
  internet_check_period                = 300
  internet_check_threshold             = 1
}
```

### Example Variables

| Variable | Description | Default |
|---|---|---|
| `vpc_natgw_service_type` | `MANAGED` (AWS NAT Gateway) or `NAT_INSTANCE` (EC2-based) | `NAT_INSTANCE` |
| `vpc_natgw_distribution` | `SINGLE` or `MULTI-AZ` | `MULTI-AZ` |
| `instance_type` | EC2 instance type for NAT instances | `t4g.nano` |
| `aws_region` | AWS Region | — |
| `profile_name` | AWS CLI profile name | — |

## Default User Data Script Details (`ec2_conf/userdata.tpl`)

The script [`ec2_conf/userdata.tpl`](./ec2_conf/userdata.tpl) is a bash script loaded via `file()` and passed as `user_data_base64` to the EC2 instance. It configures the instance as a fully functional NAT gateway using **nftables**. You can override it with a custom script via the `user_data_script` variable.

> **Note:** All output is logged to `/var/log/user-data.log` and to the system console via `logger`.

### Step-by-Step Walkthrough

---

#### Step 1 — Logging Setup

```bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
```

Redirects all stdout and stderr to:

- `/var/log/user-data.log` — persistent log file on disk
- `logger` — system journal (viewable via `journalctl -t user-data`)
- `/dev/console` — EC2 serial console

A helper function `log_status()` is defined to prefix every message with a timestamp.

---

#### Step 2 — Internet Connectivity Test

```bash
ping -c 10 8.8.8.8   # Google DNS
ping -c 10 1.1.1.1   # Cloudflare DNS (fallback)
```

- Sends 10 ICMP pings to `8.8.8.8`; requires at least **3 successful replies**
- If `8.8.8.8` fails, falls back to `1.1.1.1`
- **2 attempts** with a 60-second wait between them
- If both attempts fail → the script **exits with error** (`exit 1`) to prevent incomplete configuration

**Why:** The instance needs internet access to download packages. This step ensures the public interface and Internet Gateway are working before proceeding.

---

#### Step 3 — DNS Resolution Test

```bash
ping -c 2 google.com
ping -c 2 cloudflare.com   # fallback
```

- Verifies DNS resolution works by pinging `google.com`
- Falls back to `cloudflare.com` if the first fails
- **2 attempts** with a 60-second wait between them
- Exits with error if DNS resolution fails on both attempts

**Why:** Package installation requires DNS. This catches misconfigured DHCP options or VPC DNS settings.

---

#### Step 4 — System Update

```bash
dnf update -y
```

- Runs a full system update using `dnf` (Amazon Linux 2023 package manager)
- **2 attempts** with a 30-second wait between them
- Exits with error if both attempts fail

---

#### Step 5 — Core Packages Installation

```bash
dnf install -y traceroute tcpdump amazon-cloudwatch-agent logrotate rsyslog nftables
```

Installs the following packages:

| Package | Purpose |
|---|---|
| `traceroute` | Network path diagnostics |
| `tcpdump` | Packet capture for troubleshooting |
| `amazon-cloudwatch-agent` | CloudWatch metrics (disk, memory, swap) |
| `logrotate` | Log rotation management |
| `rsyslog` | System logging daemon |
| `nftables` | Firewall framework — replaces iptables, used for NAT masquerading |

- **2 attempts** with a 30-second wait between them

---

#### Step 6 — SSM Agent Installation and Activation

```bash
dnf install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
```

- Installs AWS Systems Manager Agent
- Enables it at boot and starts it immediately
- **2 attempts** for installation

**Why:** SSM allows remote shell access to the instance without SSH, useful for troubleshooting and management.

---

#### Step 7 — nftables Verification

```bash
command -v nft
```

- Verifies that the `nft` command is available after installation
- Exits with error if not found

---

#### Step 8 — IP Forwarding Configuration

```bash
echo "net.ipv4.ip_forward=1" | tee /etc/sysctl.d/99-ip-forward.conf
sysctl --system
```

- Enables IPv4 packet forwarding at the kernel level — **essential for NAT functionality**
- Writes the setting to `/etc/sysctl.d/99-ip-forward.conf` for persistence across reboots
- Applies the setting immediately with `sysctl --system`

---

#### Step 9 — Network Interface Detection

The script automatically identifies the two network interfaces by their role:

1. **Waits up to 60 seconds** (12 attempts × 5 seconds) for both interfaces to appear in `/sys/class/net`
2. **PUBLIC_INTERFACE**: identified as the interface with the **default route at the lowest metric** — this is the primary ENI attached to the public subnet

   ```bash
   ip route show default | sort by metric | head -1
   ```

3. **PRIVATE_INTERFACE**: the remaining interface (excluding `lo`, `docker`, and the public interface)
4. **Validation**: exits with error if either interface cannot be detected or doesn't exist

**Why:** Interface names can vary (`ens5`/`ens6`, `eth0`/`eth1`) depending on the instance type. This detection method is robust and doesn't rely on naming conventions.

---

#### Step 10 — AWS Metadata Retrieval and VPC Routing

```bash
TOKEN=$(curl --request PUT "http://169.254.169.254/latest/api/token" ...)
REGION=$(curl ... /latest/meta-data/placement/region)
VPC_ID=$(curl ... /latest/meta-data/network/interfaces/macs/.../vpc-id)
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock')
```

1. Obtains an **IMDSv2 token** (required because `http_tokens = "required"`)
2. Retrieves the **region** and **VPC ID** from instance metadata
3. Uses the **AWS CLI** to get the VPC CIDR block
4. Adds a **static route** for VPC traffic via the private interface gateway:

   ```bash
   ip route add $VPC_CIDR via $PRIVATE_GATEWAY dev $PRIVATE_INTERFACE
   ```

**Why:** Without this route, return traffic for VPC-internal destinations would go out the public interface instead of the private one.

---

#### Step 11 — Persistent Route via systemd Service

Creates `/etc/systemd/system/custom-routes.service`:

```ini
[Unit]
Description=Add custom routes
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '... ip route add $VPC_CIDR via $PRIVATE_GATEWAY dev $PRIVATE_INTERFACE ...'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

- A `oneshot` systemd service that re-adds the VPC route after every reboot
- Enabled and started immediately

**Why:** Routes added with `ip route add` are lost on reboot. This service ensures persistence.

---

#### Step 12 — nftables NAT Configuration

Creates `/etc/nftables/nat-instance.nft` with the following rule structure:

```
table inet nat_instance {
    chain input       { ... }   ← filter hook input
    chain forward     { ... }   ← filter hook forward
    chain output      { ... }   ← filter hook output
    chain postrouting { ... }   ← nat hook postrouting
}
```

**INPUT chain** (policy: `drop`):

| Rule | Description |
|---|---|
| `iif "lo" accept` | Accept all loopback traffic |
| `iif $PRIVATE_INTERFACE accept` | Accept all traffic from the private interface |
| `iif $PUBLIC_INTERFACE ct state established,related accept` | Accept only return traffic on the public interface |
| `iif $PRIVATE_INTERFACE icmp type { echo-request, echo-reply } accept` | Accept ICMP ping from private interface |

**FORWARD chain** (policy: `drop`):

| Rule | Description |
|---|---|
| `iif $PRIVATE_INTERFACE oif $PUBLIC_INTERFACE accept` | Allow forwarding from private → public (outbound NAT) |
| `iif $PUBLIC_INTERFACE oif $PRIVATE_INTERFACE ct state established,related accept` | Allow return traffic from public → private |

**OUTPUT chain** (policy: `accept`):

| Rule | Description |
|---|---|
| `oif $PUBLIC_INTERFACE accept` | Allow all outbound traffic on the public interface |

**POSTROUTING chain** (NAT):

| Rule | Description |
|---|---|
| `oif $PUBLIC_INTERFACE masquerade` | Apply source NAT (masquerade) to all traffic leaving the public interface |

The script:

1. Writes the configuration with placeholders
2. Replaces `PUBLIC_IFACE_PLACEHOLDER` and `PRIVATE_IFACE_PLACEHOLDER` with the detected interface names via `sed`
3. Loads the rules with `nft -f`
4. Verifies the rules are active
5. Copies the configuration to `/etc/sysconfig/nftables.conf` for persistence

---

#### Step 13 — nftables Persistence via systemd Service

Creates `/etc/systemd/system/nftables-nat.service`:

```ini
[Unit]
Description=nftables NAT instance firewall
Before=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/bash -c 'grep -qP "PRIVATE_INTERFACE = \".+\"" /etc/nftables/nat-instance.nft || exit 1'
ExecStart=/usr/sbin/nft -f /etc/nftables/nat-instance.nft
ExecReload=/usr/sbin/nft -f /etc/nftables/nat-instance.nft
ExecStop=/usr/sbin/nft flush ruleset
```

- **Pre-check**: verifies that the PRIVATE_INTERFACE placeholder was correctly replaced before loading rules
- Loads nftables rules at boot, before network comes up
- Supports `reload` and `stop` operations
- Enabled and started immediately; exits with error if the service fails

---

#### Step 14 — CloudWatch Agent Configuration

```bash
INSTANCE_ID=$(curl ... /latest/meta-data/instance-id)
INSTANCETYPE=$(curl ... /latest/meta-data/instance-type)
```

Writes the CloudWatch Agent configuration to `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`:

| Metric | Namespace | Interval |
|---|---|---|
| `disk_used_percent` | `EC2/NATinstance` | 60s |
| `memory_used_percent` | `EC2/NATinstance` | 60s |
| `swap_used_percent` | `EC2/NATinstance` | 60s |

- Dimensions: `InstanceId`, `InstanceType`
- Runs as `root`
- Fetches the configuration and restarts the agent

**Why:** Standard EC2 metrics don't include disk, memory or swap usage. The CloudWatch Agent provides these custom metrics.

---

### Created Files and Services

**Configuration Files:**

| File | Purpose |
|---|---|
| `/etc/sysctl.d/99-ip-forward.conf` | IP forwarding persistence |
| `/etc/nftables/nat-instance.nft` | nftables NAT rules |
| `/etc/sysconfig/nftables.conf` | nftables persistent copy |
| `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json` | CloudWatch Agent config |

**Systemd Services:**

| Service | Purpose |
|---|---|
| `custom-routes.service` | Maintain static VPC routes across reboots |
| `nftables-nat.service` | Load nftables rules at boot |
| `amazon-ssm-agent.service` | SSM remote access |
| `amazon-cloudwatch-agent.service` | CloudWatch metrics |

**Log Files:**

| File | Purpose |
|---|---|
| `/var/log/user-data.log` | Script execution logs |

## Internet Connectivity Check (Lambda-based Monitoring)

This module includes an optional Lambda-based monitoring feature that verifies internet connectivity from private subnets through NAT instances. Defined in `lambda_internet_check.tf`.

### How It Works

1. **Lambda Functions**: One Lambda function is created per private subnet, deployed inside the VPC
2. **Dual HTTPS Check**: Each Lambda performs HTTPS checks to configurable endpoints (default: `https://1.1.1.1` and `https://dns.google/resolve?name=google.com`)
3. **Smart Status Logic**:
   - ✅ **Reachable**: If at least one endpoint responds successfully (HTTP 200)
   - ❌ **Unreachable**: Only if all checks fail
4. **CloudWatch Metrics**: Results are sent as custom metrics to CloudWatch namespace `Lambda/InternetConnectivity`
5. **Alarms**: CloudWatch Alarms monitor metrics and send SNS notifications on failures
6. **Scheduling**: Lambda functions run periodically via EventBridge (default: every 5 minutes)

### Lambda Function (`lambda_function.py`)

The Python function:

1. Reads the list of URLs to check from the `CHECK_URLS` environment variable
2. Performs an HTTP GET request to each URL with a **2-second timeout**
3. Considers a check successful if the response status is `200`
4. Publishes a CloudWatch metric:
   - `1` if **at least one** URL responded successfully
   - `0` if **all** checks failed
5. Returns a JSON response with the check results

### Configuration

#### Enable Monitoring (Default: Enabled)

```hcl
module "nat_instance" {
  source = "path/to/module"
  # ... other configurations ...
  enable_internet_check = true
}
```

#### Disable Monitoring

```hcl
module "nat_instance" {
  source = "path/to/module"
  # ... other configurations ...
  enable_internet_check = false
}
```

#### Full Configuration Example

```hcl
module "nat_instance" {
  source = "path/to/module"
  # ... other configurations ...

  enable_internet_check                = true
  internet_check_alert_emails          = ["alerts@example.com", "team@example.com"]
  internet_check_schedule_expression   = "rate(5 minutes)"
  internet_check_schedule_minutes      = 5
  internet_check_log_retention_days    = 7
  internet_check_evaluation_periods    = 2
  internet_check_period                = 300
  internet_check_threshold             = 1
  internet_check_urls                  = ["https://1.1.1.1", "https://dns.google/resolve?name=google.com"]
}
```

### Variables

| Variable | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `enable_internet_check` | Enable Lambda-based internet connectivity check | `bool` | `true` | no |
| `internet_check_alert_emails` | List of email addresses for alerts | `list(string)` | `["innovation_rd@longwave.it"]` | no |
| `internet_check_schedule_expression` | CloudWatch Event schedule expression | `string` | `"rate(5 minutes)"` | no |
| `internet_check_schedule_minutes` | Schedule interval in minutes (for description only) | `number` | `5` | no |
| `internet_check_log_retention_days` | CloudWatch log retention in days | `number` | `7` | no |
| `internet_check_evaluation_periods` | Number of periods to evaluate for alarm | `number` | `2` | no |
| `internet_check_period` | Period in seconds for alarm metric | `number` | `300` | no |
| `internet_check_threshold` | Threshold for alarm (number of successful checks) | `number` | `1` | no |
| `internet_check_urls` | List of HTTPS URLs to check | `list(string)` | `["https://1.1.1.1", "https://dns.google/resolve?name=google.com"]` | no |

### Outputs

| Output | Description |
|---|---|
| `internet_check_enabled` | Whether monitoring is enabled |
| `internet_check_lambda_functions` | Map of Lambda function names |
| `internet_check_sns_topic_arn` | ARN of SNS topic for alerts |
| `internet_check_alarm_names` | Map of CloudWatch alarm names |

### Resources Created

When `enable_internet_check = true`:

| Resource | Count | Description |
|---|---|---|
| Lambda Functions | 1 per private subnet | Deployed inside VPC, Python 3.13 |
| IAM Role & Policy | 1 | Lambda execution, CloudWatch, VPC ENI management |
| Security Group | 1 | Allows all outbound traffic |
| CloudWatch Log Groups | 1 per Lambda | Configurable retention |
| EventBridge Rule | 1 | Scheduling |
| EventBridge Targets | 1 per Lambda | Links rule to functions |
| Lambda Permissions | 1 per Lambda | Allows EventBridge invocation |
| SNS Topic | 1 | Alarm notifications |
| SNS Subscriptions | 1 per email | Optional email subscriptions |
| CloudWatch Alarms | 1 per private subnet | Monitors connectivity metric |

### CloudWatch Metrics

Metrics are published to namespace `Lambda/InternetConnectivity`:

- **Metric Name**: `InternetConnectivityStatus`
- **Dimensions**: `VpcId`, `SubnetId`
- **Values**: `1` (reachable) or `0` (unreachable)

### Cost Estimate

With default settings (checks every 5 minutes):

- **Lambda Invocations**: ~8,640/month per subnet
- **Lambda Duration**: ~2 seconds per invocation
- **CloudWatch Metrics**: Custom metrics
- **CloudWatch Logs**: Based on configured retention

**Estimated monthly cost per subnet**: < $1 USD

### Troubleshooting

**Lambda cannot connect to internet:**

1. Verify route tables point to NAT instances correctly
2. Check NAT instances are running and configured properly
3. Verify Lambda security group allows outbound traffic

**No email notifications:**

1. Ensure `internet_check_alert_emails` is configured
2. Confirm SNS subscription via email (check spam folder)

**Alarms in INSUFFICIENT_DATA state:**

- Normal during first few minutes after deployment
- Alarms will transition to OK or ALARM after Lambda sends first metrics

### Email Notifications Format

When you configure `internet_check_alert_emails`, you'll receive SNS email notifications:

#### Alarm State (Connectivity Lost)

**Subject:**

```text
ALARM: "<name-prefix>-internet-check-alarm-<subnet-id>" in <Region>
```

**Body Example:**

```text
You are receiving this email because your Amazon CloudWatch Alarm
"my-project-internet-check-alarm-subnet-abc123" in the EU (Ireland)
region has entered the ALARM state, because "Threshold Crossed: 2
datapoints [0.0 (04/03/26 13:10:00), 0.0 (04/03/26 13:15:00)] were
less than the threshold (1.0)."

Alarm Details:
- Name:          my-project-internet-check-alarm-subnet-abc123
- Description:   Internet connectivity check failed in subnet subnet-abc123
- State Change:  OK -> ALARM
- Timestamp:     Tuesday 04 March, 2026 13:16:45 UTC

Monitored Metric:
- Namespace:     Lambda/InternetConnectivity
- MetricName:    InternetConnectivityStatus
- Dimensions:    [VpcId = vpc-xyz789, SubnetId = subnet-abc123]
- Period:        300 seconds
- Statistic:     SampleCount
```

#### OK State (Connectivity Restored)

**Subject:**

```text
OK: "<name-prefix>-internet-check-alarm-<subnet-id>" in <Region>
```

**Body Example:**

```text
You are receiving this email because your Amazon CloudWatch Alarm
"my-project-internet-check-alarm-subnet-abc123" in the EU (Ireland)
region has returned to the OK state, because "Threshold Crossed: 2
datapoints [1.0 (04/03/26 13:20:00), 1.0 (04/03/26 13:25:00)] were
not less than the threshold (1.0)."

Alarm Details:
- Name:          my-project-internet-check-alarm-subnet-abc123
- Description:   Internet connectivity check failed in subnet subnet-abc123
- State Change:  ALARM -> OK
- Timestamp:     Tuesday 04 March, 2026 13:26:12 UTC
```

**Important Notes:**

- **First Email**: After deployment, you'll receive a subscription confirmation email from SNS that you must confirm
- **Bidirectional Notifications**: You'll receive emails both when alarms trigger (ALARM) and when they resolve (OK)
- **Evaluation Periods**: With default settings (`evaluation_periods = 2`), alarms trigger only after 2 consecutive failed checks (~10 minutes)

## Notes and Best Practices

1. **High Availability**
   - For production environments, enable `nat_instance_per_az = true` or use the managed NAT Gateway service
   - Enable internet connectivity check (`enable_internet_check = true`) for proactive monitoring

2. **CloudWatch Configuration**
   - The CloudWatch Agent configuration is saved in `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`
   - Custom metrics are published to the `EC2/NATinstance` namespace

3. **Internet Connectivity Monitoring**
   - Lambda functions check configurable HTTPS endpoints (default: Cloudflare 1.1.1.1 and Google DNS API)
   - Internet is considered reachable if at least one endpoint responds successfully
   - Customize check frequency via `internet_check_schedule_expression`

4. **Custom User Data**
   - You can provide a custom user data script via the `user_data_script` variable
   - The default script uses nftables for NAT — ensure any custom script also configures IP forwarding and masquerading

## Troubleshooting

1. **Ping from NAT instance using private interface**

   ```sh
   ping -I <PRIVATE_INTERFACE> -c 4 8.8.8.8
   ```

2. **Check routing table**

   ```sh
   ip route show
   ```

3. **Check if IP forwarding is enabled**

  ```sh
  ip route show
  ```

   If the value is `0`, reactivate it with:

  ```sh
  sysctl net.ipv4.ip_forward
  ```

   If the value is 0, reactivate it with:

  ```sh
  echo 1 > /proc/sys/net/ipv4/ip_forward
  ```

   > **WARNING**: verify that `/etc/sysctl.d/99-ip-forward.conf` contains only `net.ipv4.ip_forward=1`

4. **Check active nftables rules**

   ```sh
   nft list ruleset
   ```

5. **Check NAT-specific rules**

   ```sh
   nft list table inet nat_instance
   ```

6. **Reset nftables counters**

   ```sh
   nft reset counters
   ```

7. **Monitor traffic in real-time with tcpdump**

   To verify if ICMP packets (ping) reach the NAT instance:

   ```sh
   tcpdump -i <PRIVATE_INTERFACE> icmp
   ```

   To see if traffic is passing correctly between interfaces:

   ```sh
   tcpdump -i <PUBLIC_INTERFACE> icmp
   ```

   Monitor all traffic on a specific interface:

   ```sh
   tcpdump -i <PRIVATE_INTERFACE>
   ```

8. **Check user data execution logs**

   ```sh
   cat /var/log/user-data.log
   ```

9. **Check nftables-nat service status**

   ```sh
   systemctl status nftables-nat.service
   ```

10. **Check custom-routes service status**

    ```sh
    systemctl status custom-routes.service
    ```

11. **To see which connections are currently established through the NAT instance**

    ```sh
    conntrack -L
    ```

    or

    ```sh
    ss -tnp
    ```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | 2.7.1 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.35.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.2.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.lambda_schedule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.lambda_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.internet_check_log_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.internet_check](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_eip.nat_eip](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_iam_instance_profile.ec2_nat_ssm_cloudwatch_instance_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.ec2_nat_ssm_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.lambda_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ec2_describe_network_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.lambda_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cloudwatch_nat_logs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ssm_nat_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.nat_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_key_pair.rsa_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [aws_lambda_function.internet_check](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.allow_eventbridge](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_network_interface.natgw_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface) | resource |
| [aws_network_interface_attachment.nat_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface_attachment) | resource |
| [aws_route.private_subs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_security_group.lambda_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.natgw_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.natgw_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_sns_topic.lambda_alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_subscription.lambda_alerts_email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_ssm_parameter.nat_instance_ssh_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [tls_private_key.pk_nat](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [archive_file.lambda_zip](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_ami.latest_ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Random name prefix for resources | `string` | n/a | yes |
| <a name="input_private_route_table_ids"></a> [private\_route\_table\_ids](#input\_private\_route\_table\_ids) | List of private route table IDs | `list(string)` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of private subnet IDs | `list(string)` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | List of public subnet IDs | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC | `string` | n/a | yes |
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI ID for NAT instances. If null, uses latest Amazon Linux 2023. To find AMI: aws ec2 describe-images --owners amazon --filters 'Name=name,Values=al2023-ami-2023.*-kernel-*-arm64' 'Name=virtualization-type,Values=hvm' --query 'Images[*].[ImageId,Name,CreationDate]' --output table --region <your-region> | `string` | `null` | no |
| <a name="input_create_ssh_keys"></a> [create\_ssh\_keys](#input\_create\_ssh\_keys) | Create ssh keys for the NAT instance/s | `bool` | `false` | no |
| <a name="input_credits_mode"></a> [credits\_mode](#input\_credits\_mode) | Credits mode for NAT instances. Can be `standard` or `unlimited` | `string` | `"unlimited"` | no |
| <a name="input_disk_configuration"></a> [disk\_configuration](#input\_disk\_configuration) | Disk configuration for NAT instances | <pre>object({<br/>    delete_on_termination = optional(bool),<br/>    encrypted             = optional(bool),<br/>    iops                  = optional(number),<br/>    kms_key_id            = optional(string),<br/>    tags                  = optional(map(string)),<br/>    throughput            = optional(number),<br/>    size                  = optional(number),<br/>    type                  = optional(string)<br/>  })</pre> | <pre>{<br/>  "delete_on_termination": true,<br/>  "encrypted": true,<br/>  "size": 30,<br/>  "type": "gp3"<br/>}</pre> | no |
| <a name="input_enable_internet_check"></a> [enable\_internet\_check](#input\_enable\_internet\_check) | Enable Lambda-based internet connectivity check for private subnets | `bool` | `true` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for NAT instances | `string` | `"t4g.nano"` | no |
| <a name="input_internet_check_alert_emails"></a> [internet\_check\_alert\_emails](#input\_internet\_check\_alert\_emails) | List of email addresses for internet connectivity check alerts. Leave empty to skip email subscriptions | `list(string)` | <pre>[<br/>  "innovation_rd@longwave.it"<br/>]</pre> | no |
| <a name="input_internet_check_evaluation_periods"></a> [internet\_check\_evaluation\_periods](#input\_internet\_check\_evaluation\_periods) | Number of periods to evaluate for the internet check alarm | `number` | `2` | no |
| <a name="input_internet_check_log_retention_days"></a> [internet\_check\_log\_retention\_days](#input\_internet\_check\_log\_retention\_days) | CloudWatch log retention in days for internet check Lambda functions | `number` | `7` | no |
| <a name="input_internet_check_period"></a> [internet\_check\_period](#input\_internet\_check\_period) | Period in seconds for the internet check alarm metric | `number` | `300` | no |
| <a name="input_internet_check_schedule_expression"></a> [internet\_check\_schedule\_expression](#input\_internet\_check\_schedule\_expression) | CloudWatch Event schedule expression for internet check (e.g., 'rate(5 minutes)') | `string` | `"rate(5 minutes)"` | no |
| <a name="input_internet_check_schedule_minutes"></a> [internet\_check\_schedule\_minutes](#input\_internet\_check\_schedule\_minutes) | Schedule interval in minutes for internet check (used only for description) | `number` | `5` | no |
| <a name="input_internet_check_threshold"></a> [internet\_check\_threshold](#input\_internet\_check\_threshold) | Threshold for the internet check alarm (number of successful checks) | `number` | `1` | no |
| <a name="input_internet_check_urls"></a> [internet\_check\_urls](#input\_internet\_check\_urls) | List of HTTPS URLs to check for internet connectivity | `list(string)` | <pre>[<br/>  "https://1.1.1.1",<br/>  "https://dns.google/resolve?name=google.com"<br/>]</pre> | no |
| <a name="input_nat_instance_per_az"></a> [nat\_instance\_per\_az](#input\_nat\_instance\_per\_az) | Whether to create a NAT instance per AZ or a single NAT instance for all AZs | `bool` | `false` | no |
| <a name="input_user_data_script"></a> [user\_data\_script](#input\_user\_data\_script) | Path to the custom user data script. By default use /ec2\_conf/userdata.tpl | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_internet_check_alarm_names"></a> [internet\_check\_alarm\_names](#output\_internet\_check\_alarm\_names) | Map of CloudWatch alarm names for internet connectivity checks |
| <a name="output_internet_check_enabled"></a> [internet\_check\_enabled](#output\_internet\_check\_enabled) | Whether internet connectivity check is enabled |
| <a name="output_internet_check_lambda_functions"></a> [internet\_check\_lambda\_functions](#output\_internet\_check\_lambda\_functions) | Map of Lambda function names for internet connectivity checks |
| <a name="output_internet_check_sns_topic_arn"></a> [internet\_check\_sns\_topic\_arn](#output\_internet\_check\_sns\_topic\_arn) | ARN of the SNS topic for internet connectivity alerts |
| <a name="output_nat_instance_details"></a> [nat\_instance\_details](#output\_nat\_instance\_details) | Details of NAT instances including ID and Public IP |
| <a name="output_nat_instance_ids"></a> [nat\_instance\_ids](#output\_nat\_instance\_ids) | IDs of the NAT EC2 instances |
| <a name="output_nat_public_ips"></a> [nat\_public\_ips](#output\_nat\_public\_ips) | Public IPs of the NAT instances |
<!-- END_TF_DOCS -->
