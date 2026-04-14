#!/bin/bash
# Step 1 — Logging Setup
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
log_status() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_status "Starting userdata script execution"
# Step 2 — Internet Connectivity Test
log_status "[Step 2] Testing internet connectivity..."
for attempt in 1 2; do
    INTERNET_OK=false
    for host in 8.8.8.8 1.1.1.1; do
        PING_COUNT=$(ping -c 10 $host | grep "received" | awk '{print $4}')
        if [ "$PING_COUNT" -ge 3 ]; then
            log_status "[Step 2] SUCCESS: $host responded $PING_COUNT/10"
            INTERNET_OK=true
            break
        fi
        log_status "[Step 2] FAILED: $host responded only $PING_COUNT/10"
    done
    if [ "$INTERNET_OK" = true ]; then break; fi
    if [ $attempt -eq 1 ]; then
        log_status "[Step 2] Waiting 60s before retry..."
        sleep 60
    fi
done
if [ "$INTERNET_OK" = false ]; then
    log_status "[Step 2] ERROR: no internet after 2 attempts"
    exit 1
fi
# Step 3 — DNS Resolution Test
log_status "[Step 3] Testing DNS connectivity..."
for attempt in 1 2; do
    DNS_OK=false
    for host in google.com cloudflare.com; do
        if ping -c 2 $host > /dev/null 2>&1; then
            log_status "[Step 3] SUCCESS: $host resolved"
            DNS_OK=true
            break
        fi
        log_status "[Step 3] FAILED: $host DNS resolution failed"
    done
    if [ "$DNS_OK" = true ]; then break; fi
    if [ $attempt -eq 1 ]; then
        log_status "[Step 3] Waiting 60s before retry..."
        sleep 60
    fi
done
if [ "$DNS_OK" = false ]; then
    log_status "[Step 3] ERROR: DNS failed after 2 attempts"
    exit 1
fi
log_status "Connectivity tests passed - proceeding"
# Step 4 — System Update
log_status "[Step 4] Starting system update..."
for attempt in 1 2; do
    if dnf update -y; then
        log_status "[Step 4] SUCCESS: system update completed"
        break
    fi
    log_status "[Step 4] FAILED: system update attempt $attempt"
    if [ $attempt -eq 1 ]; then sleep 30; else exit 1; fi
done
# Step 5 — Core Packages Installation
PACKAGES="traceroute tcpdump amazon-cloudwatch-agent logrotate rsyslog nftables"
log_status "[Step 5] Installing: $PACKAGES"
for attempt in 1 2; do
    if dnf install -y $PACKAGES; then
        log_status "[Step 5] SUCCESS: packages installed"
        break
    fi
    log_status "[Step 5] FAILED: packages installation attempt $attempt"
    if [ $attempt -eq 1 ]; then sleep 30; else exit 1; fi
done
# Step 6 — SSM Agent Installation and Activation
log_status "[Step 6] Installing SSM agent..."
for attempt in 1 2; do
    if dnf install -y amazon-ssm-agent; then
        log_status "[Step 6] SUCCESS: SSM agent installed"
        break
    fi
    log_status "[Step 6] FAILED: SSM agent installation attempt $attempt"
    if [ $attempt -eq 1 ]; then sleep 30; else exit 1; fi
done
if systemctl enable amazon-ssm-agent && systemctl start amazon-ssm-agent; then
    log_status "[Step 6] SUCCESS: SSM agent enabled and started"
else
    log_status "[Step 6] ERROR: SSM agent service failed"
    exit 1
fi
# Step 7 — nftables Verification
if ! command -v nft &> /dev/null; then
    log_status "[Step 7] ERROR: nft command not found"
    exit 1
fi
log_status "[Step 7] SUCCESS: nft available"
# Step 8 — IP Forwarding Configuration
log_status "[Step 8] Enable IP Forwarding"
echo "net.ipv4.ip_forward=1" | tee /etc/sysctl.d/99-ip-forward.conf
chmod 644 /etc/sysctl.d/99-ip-forward.conf
sysctl --system
# Step 9 — Network Interface Detection
log_status "[Step 9] Detecting network interfaces..."
for i in $(seq 1 12); do
    IFACE_COUNT=$(ls /sys/class/net | grep -v "lo\|docker" | wc -l)
    if [ "$IFACE_COUNT" -ge 2 ]; then
        log_status "[Step 9] Found $IFACE_COUNT interfaces"
        break
    fi
    log_status "[Step 9] Waiting for interfaces... $i/12 (found $IFACE_COUNT)"
    sleep 5
done
if [ "$IFACE_COUNT" -lt 2 ]; then
    log_status "[Step 9] ERROR: less than 2 interfaces after 60s"
    exit 1
fi
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
PRIVATE_INTERFACE=$(ls /sys/class/net \
    | grep -v "lo\|docker" \
    | grep -v "^${PUBLIC_INTERFACE}$" \
    | head -1)
if [ -z "$PUBLIC_INTERFACE" ]; then
    log_status "[Step 9] ERROR: could not detect PUBLIC_INTERFACE"
    exit 1
fi
if [ -z "$PRIVATE_INTERFACE" ]; then
    log_status "[Step 9] ERROR: could not detect PRIVATE_INTERFACE"
    exit 1
fi
for IFACE in "$PUBLIC_INTERFACE" "$PRIVATE_INTERFACE"; do
    if [ ! -d "/sys/class/net/$IFACE" ]; then
        log_status "[Step 9] ERROR: interface $IFACE does not exist"
        exit 1
    fi
done
log_status "[Step 9] PUBLIC_INTERFACE=$PUBLIC_INTERFACE PRIVATE_INTERFACE=$PRIVATE_INTERFACE"
# Wait for DHCP on private interface: the interface appears in /sys/class/net
# right after hot-attach but DHCP may not have completed yet.
log_status "[Step 9] Waiting for DHCP on $PRIVATE_INTERFACE..."
for i in $(seq 1 12); do
    if ip addr show "$PRIVATE_INTERFACE" | grep -q "inet "; then
        PRIVATE_IP=$(ip addr show "$PRIVATE_INTERFACE" | grep "inet " | awk '{print $2}')
        log_status "[Step 9] SUCCESS: $PRIVATE_INTERFACE has IP $PRIVATE_IP"
        break
    fi
    log_status "[Step 9] Waiting for DHCP on $PRIVATE_INTERFACE... $i/12"
    sleep 5
done
if ! ip addr show "$PRIVATE_INTERFACE" | grep -q "inet "; then
    log_status "[Step 9] ERROR: $PRIVATE_INTERFACE has no IP after 60s"
    exit 1
fi
# Step 10 — AWS Metadata Retrieval and VPC Routing
log_status "[Step 10] Getting metadata for VPC..."
TOKEN=$(curl --request PUT "http://169.254.169.254/latest/api/token" --header "X-aws-ec2-metadata-token-ttl-seconds: 3600")
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region --header "X-aws-ec2-metadata-token: $TOKEN")
VPC_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/network/interfaces/macs/$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/mac)/vpc-id)
log_status "[Step 10] VPC_ID=$VPC_ID REGION=$REGION"
VPC_CIDR=$(aws ec2 describe-vpcs --region $REGION --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock' --output text)
PRIVATE_GATEWAY=$(ip route show dev $PRIVATE_INTERFACE | grep -E "^default|^0.0.0.0" | awk '{print $3}' | head -1)
if [ -n "$PRIVATE_GATEWAY" ]; then
    ip route add $VPC_CIDR via $PRIVATE_GATEWAY dev $PRIVATE_INTERFACE 2>/dev/null || true
fi
# Step 11 — Persistent Route via systemd Service
log_status "[Step 11] Creating static route service"
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
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable custom-routes.service
systemctl start custom-routes.service || log_status "[Step 11] WARNING: custom-routes service failed"
# Step 12 — nftables NAT Configuration
log_status "[Step 12] Configuring nftables NAT rules"
mkdir -p /etc/nftables /etc/sysconfig
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
sed -i "s/PUBLIC_IFACE_PLACEHOLDER/$PUBLIC_INTERFACE/g" /etc/nftables/nat-instance.nft
sed -i "s/PRIVATE_IFACE_PLACEHOLDER/$PRIVATE_INTERFACE/g" /etc/nftables/nat-instance.nft
chmod +x /etc/nftables/nat-instance.nft
if /usr/sbin/nft -f /etc/nftables/nat-instance.nft; then
    log_status "[Step 12] SUCCESS: nftables rules loaded"
else
    log_status "[Step 12] ERROR: failed to load nftables rules"
    exit 1
fi
if ! /usr/sbin/nft list ruleset | grep -q "nat_instance"; then
    log_status "[Step 12] ERROR: nat_instance rules not found in ruleset"
    exit 1
fi
cp /etc/nftables/nat-instance.nft /etc/sysconfig/nftables.conf
# Step 13 — nftables Persistence via systemd Service
log_status "[Step 13] Creating nftables-nat systemd service"
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
systemctl daemon-reload
systemctl enable nftables-nat.service
systemctl start nftables-nat.service
if systemctl is-active --quiet nftables-nat.service; then
    log_status "[Step 13] SUCCESS: nftables-nat running"
else
    log_status "[Step 13] ERROR: nftables-nat failed to start"
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
        "measurement": [{"name": "used_percent","rename": "disk_used_percent","unit": "Percent"}],
        "drop_device": true,
        "append_dimensions": {"InstanceId": "$INSTANCE_ID","InstanceType": "$INSTANCETYPE"},
        "metrics_collection_interval": 60,
        "resources": ["/"]
      },
      "mem": {
        "measurement": [{"name": "used_percent","rename": "memory_used_percent","unit": "Percent"}],
        "append_dimensions": {"InstanceId": "$INSTANCE_ID","InstanceType": "$INSTANCETYPE"},
        "metrics_collection_interval": 60
      },
      "swap": {
        "measurement": [{"name": "used_percent","rename": "swap_used_percent","unit": "Percent"}],
        "append_dimensions": {"InstanceId": "$INSTANCE_ID","InstanceType": "$INSTANCETYPE"},
        "metrics_collection_interval": 60
      }
    }
  }
}
EOL
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
systemctl restart amazon-cloudwatch-agent
log_status "Userdata script completed successfully"
