#!/bin/bash
# NAT Instance Userdata - Configure EC2 as NAT Gateway with nftables
# Step 1 — Logging Setup
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
log_status() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_status "Starting userdata script execution"
# Step 2 — Internet Connectivity Test
log_status "[Step 2] Testing internet connectivity..."
for attempt in 1 2; do
    INTERNET_OK=false
    log_status "[Step 2] Testing connectivity to 8.8.8.8"
    PING_COUNT=$(ping -c 10 8.8.8.8 | grep "received" | awk '{print $4}')
    if [ "$PING_COUNT" -ge 3 ]; then
        log_status "[Step 2] SUCCESS: 8.8.8.8 responded $PING_COUNT/3 times"
        INTERNET_OK=true
    else
        log_status "[Step 2] FAILED: 8.8.8.8 responded only $PING_COUNT/3 times, trying 1.1.1.1"
        log_status "[Step 2] Testing connectivity to 1.1.1.1"
        PING_COUNT=$(ping -c 10 1.1.1.1 | grep "received" | awk '{print $4}')
        if [ "$PING_COUNT" -ge 3 ]; then
            log_status "[Step 2] SUCCESS: 1.1.1.1 responded $PING_COUNT/3 times"
            INTERNET_OK=true
        else
            log_status "[Step 2] FAILED: 1.1.1.1 responded only $PING_COUNT/3 times"
        fi
    fi
    if [ "$INTERNET_OK" = true ]; then
        break
    elif [ $attempt -eq 1 ]; then
        log_status "[Step 2] First attempt failed, waiting 60 seconds before retry..."
        sleep 60
    fi
done
if [ "$INTERNET_OK" = false ]; then
    log_status "[Step 2] ERROR: VM cannot reach internet after 2 attempts - both 8.8.8.8 and 1.1.1.1 failed"
    exit 1
fi
# Step 3 — DNS Resolution Test
log_status "[Step 3] Testing DNS connectivity..."
for attempt in 1 2; do
    DNS_OK=false
    log_status "[Step 3] Testing DNS resolution for google.com"
    if ping -c 2 google.com > /dev/null 2>&1; then
        log_status "[Step 3] SUCCESS: google.com DNS resolution and connectivity working"
        DNS_OK=true
    else
        log_status "[Step 3] FAILED: google.com DNS resolution failed, trying cloudflare.com"
        log_status "[Step 3] Testing DNS resolution for cloudflare.com"
        if ping -c 2 cloudflare.com > /dev/null 2>&1; then
            log_status "[Step 3] SUCCESS: cloudflare.com DNS resolution and connectivity working"
            DNS_OK=true
        else
            log_status "[Step 3] FAILED: cloudflare.com DNS resolution failed"
        fi
    fi
    if [ "$DNS_OK" = true ]; then
        break
    elif [ $attempt -eq 1 ]; then
        log_status "[Step 3] First DNS attempt failed, waiting 60 seconds before retry..."
        sleep 60
    fi
done
if [ "$DNS_OK" = false ]; then
    log_status "[Step 3] ERROR: VM cannot resolve DNS after 2 attempts - both google.com and cloudflare.com failed"
    exit 1
fi
log_status "All connectivity tests passed - proceeding with installation"
# Step 4 — System Update
log_status "[Step 4] Starting system update..."
for attempt in 1 2; do
    log_status "[Step 4] System update attempt $attempt/2"
    if dnf update -y; then
        log_status "[Step 4] SUCCESS: System update completed successfully"
        break
    else
        log_status "[Step 4] FAILED: System update failed on attempt $attempt"
        if [ $attempt -eq 1 ]; then
            log_status "[Step 4] Waiting 30 seconds before retry..."
            sleep 30
        else
            log_status "[Step 4] ERROR: System update failed after 2 attempts"
            exit 1
        fi
    fi
done
# Step 5 — Core Packages Installation
log_status "[Step 5] Installing core packages..."
PACKAGES="traceroute tcpdump amazon-cloudwatch-agent logrotate rsyslog nftables"
for attempt in 1 2; do
    log_status "[Step 5] Core packages installation attempt $attempt/2"
    if dnf install -y $PACKAGES; then
        log_status "[Step 5] SUCCESS: Core packages installed successfully: $PACKAGES"
        break
    else
        log_status "[Step 5] FAILED: Core packages installation failed on attempt $attempt"
        log_status "[Step 5] Failed packages: $PACKAGES"
        if [ $attempt -eq 1 ]; then
            log_status "[Step 5] Waiting 30 seconds before retry..."
            sleep 30
        else
            log_status "[Step 5] ERROR: Core packages installation failed after 2 attempts"
            exit 1
        fi
    fi
done
# Step 6 — SSM Agent Installation and Activation
log_status "[Step 6] Installing SSM agent..."
for attempt in 1 2; do
    log_status "[Step 6] SSM agent installation attempt $attempt/2"
    if dnf install -y amazon-ssm-agent; then
        log_status "[Step 6] SUCCESS: SSM agent installed successfully"
        break
    else
        log_status "[Step 6] FAILED: SSM agent installation failed on attempt $attempt"
        log_status "[Step 6] Failed package: amazon-ssm-agent"
        if [ $attempt -eq 1 ]; then
            log_status "[Step 6] Waiting 30 seconds before retry..."
            sleep 30
        else
            log_status "[Step 6] ERROR: SSM agent installation failed after 2 attempts"
            exit 1
        fi
    fi
done
log_status "[Step 6] Configuring SSM agent service..."
if systemctl enable amazon-ssm-agent && systemctl start amazon-ssm-agent; then
    log_status "[Step 6] SUCCESS: SSM agent service enabled and started"
else
    log_status "[Step 6] ERROR: Failed to configure SSM agent service"
    exit 1
fi
log_status "All package installations completed successfully"
# Step 7 — nftables Verification
log_status "[Step 7] Verifying nftables installation"
if ! command -v nft &> /dev/null; then
    log_status "[Step 7] ERROR: nft command not found after installation"
    exit 1
fi
log_status "[Step 7] SUCCESS: nft command is available"
# Step 8 — IP Forwarding Configuration
log_status "[Step 8] Enable IP Forwarding"
echo "net.ipv4.ip_forward=1" | tee /etc/sysctl.d/99-ip-forward.conf
chmod 644 /etc/sysctl.d/99-ip-forward.conf
sysctl --system
# Step 9 — Network Interface Detection
log_status "[Step 9] Detecting network interfaces by role..."
# Wait for both interfaces to be up (max 60s)
for i in $(seq 1 12); do
    IFACE_COUNT=$(ls /sys/class/net | grep -v "lo\|docker" | wc -l)
    if [ "$IFACE_COUNT" -ge 2 ]; then
        log_status "[Step 9] SUCCESS: Found $IFACE_COUNT interfaces"
        break
    fi
    log_status "[Step 9] Waiting for interfaces... attempt $i/12 (found $IFACE_COUNT)"
    sleep 5
done
if [ "$IFACE_COUNT" -lt 2 ]; then
    log_status "[Step 9] ERROR: Less than 2 interfaces found after 60s"
    exit 1
fi
# The public interface is the one with the default route at lowest metric
PUBLIC_INTERFACE=$(ip route show default \
    | awk '/^default/{
        for(i=1;i<=NF;i++) {
            if($i=="metric") metric=$(i+1)
            if($i=="dev") iface=$(i+1)
        }
        print metric, iface
    }' \
    | sort -k1 -n \
    | awk '{print $2}' \
    | head -1)
# The private interface is the other one (not loopback, not docker, not public)
PRIVATE_INTERFACE=$(ls /sys/class/net \
    | grep -v "lo\|docker" \
    | grep -v "^${PUBLIC_INTERFACE}$" \
    | head -1)
# Validation
if [ -z "$PUBLIC_INTERFACE" ]; then
    log_status "[Step 9] ERROR: Could not detect PUBLIC_INTERFACE"
    exit 1
fi
if [ -z "$PRIVATE_INTERFACE" ]; then
    log_status "[Step 9] ERROR: Could not detect PRIVATE_INTERFACE"
    exit 1
fi
log_status "[Step 9] PUBLIC_INTERFACE  = $PUBLIC_INTERFACE"
log_status "[Step 9] PRIVATE_INTERFACE = $PRIVATE_INTERFACE"
# Verify that both interfaces actually exist
for IFACE in "$PUBLIC_INTERFACE" "$PRIVATE_INTERFACE"; do
    if [ ! -d "/sys/class/net/$IFACE" ]; then
        log_status "[Step 9] ERROR: Interface $IFACE does not exist"
        exit 1
    fi
done
log_status "[Step 9] SUCCESS: Interface detection completed"
# Wait for DHCP to complete on the private interface (eth1).
# The interface can appear in /sys/class/net subito dopo il hot-attach
# ma impiegare qualche secondo in più per ottenere IP e route via DHCP.
log_status "[Step 9] Waiting for DHCP on $PRIVATE_INTERFACE..."
for i in $(seq 1 12); do
    if ip addr show "$PRIVATE_INTERFACE" | grep -q "inet "; then
        PRIVATE_IP=$(ip addr show "$PRIVATE_INTERFACE" | grep "inet " | awk '{print $2}')
        log_status "[Step 9] SUCCESS: $PRIVATE_INTERFACE has IP $PRIVATE_IP"
        break
    fi
    log_status "[Step 9] Waiting for DHCP on $PRIVATE_INTERFACE... attempt $i/12"
    sleep 5
done
if ! ip addr show "$PRIVATE_INTERFACE" | grep -q "inet "; then
    log_status "[Step 9] ERROR: $PRIVATE_INTERFACE has no IP after 60s - DHCP failed or interface not ready"
    exit 1
fi
# Step 10 — AWS Metadata Retrieval and VPC Routing
log_status "[Step 10] Getting metadata for VPC..."
TOKEN=$(curl --request PUT "http://169.254.169.254/latest/api/token" --header "X-aws-ec2-metadata-token-ttl-seconds: 3600")
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region --header "X-aws-ec2-metadata-token: $TOKEN")
VPC_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/network/interfaces/macs/$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/mac)/vpc-id)
echo "[Step 10] Recovering CIDR for VPC: $VPC_ID"
log_status "[Step 10] Recovering CIDR for VPC: $VPC_ID"
VPC_CIDR=$(aws ec2 describe-vpcs --region $REGION --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock' --output text)
PRIVATE_GATEWAY=$(ip route show dev $PRIVATE_INTERFACE | grep -E "^default|^0.0.0.0" | awk '{print $3}' | head -1)
if [ -n "$PRIVATE_GATEWAY" ]; then
    ip route add $VPC_CIDR via $PRIVATE_GATEWAY dev $PRIVATE_INTERFACE 2>/dev/null || true
fi
# Step 11 — Persistent Route via systemd Service
log_status "[Step 11] Creating static route"
cat <<EOF > /etc/systemd/system/custom-routes.service
[Unit]
Description=Add custom routes
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'PRIVATE_GATEWAY=\$(ip route show dev $PRIVATE_INTERFACE | grep -E "^default|^0.0.0.0" | awk "{print \$3}" | head -1); if [ -n "\$PRIVATE_GATEWAY" ]; then ip route add $VPC_CIDR via \$PRIVATE_GATEWAY dev $PRIVATE_INTERFACE 2>/dev/null || true; fi'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
log_status "[Step 11] Restarting systemd for the new service"
systemctl daemon-reexec
systemctl daemon-reload
log_status "[Step 11] Enabling new service on startup"
systemctl enable custom-routes.service
log_status "[Step 11] Launching immediately the service"
systemctl start custom-routes.service || log_status "[Step 11] WARNING: custom-routes service failed, but continuing"
# Step 12 — nftables NAT Configuration
log_status "[Step 12] Creating nftables configuration directories"
mkdir -p /etc/nftables /etc/sysconfig
log_status "[Step 12] Configuring nftables rules for NAT functionality"
cat > /etc/nftables/nat-instance.nft <<'NFTEOF'
#!/usr/sbin/nft -f
flush ruleset
define PUBLIC_INTERFACE = "PUBLIC_IFACE_PLACEHOLDER"
define PRIVATE_INTERFACE = "PRIVATE_IFACE_PLACEHOLDER"
table inet nat_instance {
    chain input {
        type filter hook input priority filter; policy drop;
        iif "lo" accept
        iif $PRIVATE_INTERFACE accept
        iif $PUBLIC_INTERFACE ct state established,related accept
        iif $PRIVATE_INTERFACE icmp type { echo-request, echo-reply } accept
    }
    chain forward {
        type filter hook forward priority filter; policy drop;
        iif $PRIVATE_INTERFACE oif $PUBLIC_INTERFACE accept
        iif $PUBLIC_INTERFACE oif $PRIVATE_INTERFACE ct state established,related accept
    }
    chain output {
        type filter hook output priority filter; policy accept;
        oif $PUBLIC_INTERFACE accept
    }
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oif $PUBLIC_INTERFACE masquerade
    }
}
NFTEOF
# Replace placeholders with actual values
sed -i "s/PUBLIC_IFACE_PLACEHOLDER/$PUBLIC_INTERFACE/g" /etc/nftables/nat-instance.nft
sed -i "s/PRIVATE_IFACE_PLACEHOLDER/$PRIVATE_INTERFACE/g" /etc/nftables/nat-instance.nft
log_status "[Step 12] Setting executable permissions on nftables configuration"
chmod +x /etc/nftables/nat-instance.nft
log_status "[Step 12] Loading nftables NAT configuration"
if /usr/sbin/nft -f /etc/nftables/nat-instance.nft; then
    log_status "[Step 12] SUCCESS: nftables rules loaded successfully"
else
    log_status "[Step 12] ERROR: Failed to load nftables rules"
    exit 1
fi
log_status "[Step 12] Verifying nftables rules are active"
if /usr/sbin/nft list ruleset | grep -q "nat_instance"; then
    log_status "[Step 12] SUCCESS: NAT instance rules are active"
else
    log_status "[Step 12] ERROR: NAT instance rules not found in active ruleset"
    exit 1
fi
log_status "[Step 12] Configuring nftables persistence"
cp /etc/nftables/nat-instance.nft /etc/sysconfig/nftables.conf
# Step 13 — nftables Persistence via systemd Service
log_status "[Step 13] Creating nftables systemd service"
cat > /etc/systemd/system/nftables-nat.service <<NFTEOF
[Unit]
Description=nftables NAT instance firewall
Before=network-pre.target
Wants=network-pre.target
After=local-fs.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/bash -c 'grep -qP "PRIVATE_INTERFACE = \".+\"" /etc/nftables/nat-instance.nft || (echo "ERROR: PRIVATE_INTERFACE is empty in nft file"; exit 1)'
ExecStart=/usr/sbin/nft -f /etc/nftables/nat-instance.nft
ExecReload=/usr/sbin/nft -f /etc/nftables/nat-instance.nft
ExecStop=/usr/sbin/nft flush ruleset
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
NFTEOF
log_status "[Step 13] Enabling and starting nftables-nat service"
systemctl daemon-reload
systemctl enable nftables-nat.service
systemctl start nftables-nat.service
if systemctl is-active --quiet nftables-nat.service; then
    log_status "[Step 13] SUCCESS: nftables-nat service is running"
else
    log_status "[Step 13] ERROR: nftables-nat service failed to start"
    systemctl status nftables-nat.service
    exit 1
fi
# Step 14 — CloudWatch Agent Configuration
log_status "[Step 14] Configuring CloudWatch Agent"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id --header "X-aws-ec2-metadata-token: $TOKEN")
INSTANCETYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type --header "X-aws-ec2-metadata-token: $TOKEN")
tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null <<EOL
{
  "agent": {
    "run_as_user": "root",
    "omit_hostname": true,
    "metrics_collection_interval": 60,
    "debug": false
  },
  "metrics": {
    "namespace": "EC2/NATinstance",
    "metrics_collected": {
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "disk_used_percent",
            "unit": "Percent"
          }
        ],
        "drop_device": true,
        "append_dimensions": {
          "InstanceId": "$INSTANCE_ID",
          "InstanceType": "$INSTANCETYPE"
        },
        "metrics_collection_interval": 60,
        "resources": [
          "/"
        ]
      },
      "mem": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "memory_used_percent",
            "unit": "Percent"
          }
        ],
        "append_dimensions": {
          "InstanceId": "$INSTANCE_ID",
          "InstanceType": "$INSTANCETYPE"
        },
        "metrics_collection_interval": 60
      },
      "swap": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "swap_used_percent",
            "unit": "Percent"
          }
        ],
        "append_dimensions": {
          "InstanceId": "$INSTANCE_ID",
          "InstanceType": "$INSTANCETYPE"
        },
        "metrics_collection_interval": 60
      }
    }
  }
}
EOL
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
systemctl restart amazon-cloudwatch-agent
log_status "Userdata script execution completed"
