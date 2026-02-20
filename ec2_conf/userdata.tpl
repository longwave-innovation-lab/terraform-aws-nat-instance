#!/bin/bash
# NAT Instance Userdata - Configura EC2 come NAT Gateway con nftables
sleep 20
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

log_status() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_status "Starting userdata script execution"

# Test connettività internet (8.8.8.8 e 1.1.1.1)
log_status "Testing internet connectivity..."
for attempt in 1 2; do
    log_status "Connectivity test attempt $attempt/2"
    INTERNET_OK=false
    
    log_status "Testing connectivity to 8.8.8.8"
    PING_COUNT=$(ping -c 10 8.8.8.8 | grep "received" | awk '{print $4}')
    if [ "$PING_COUNT" -ge 3 ]; then
        log_status "SUCCESS: 8.8.8.8 responded $PING_COUNT/3 times"
        INTERNET_OK=true
    else
        log_status "FAILED: 8.8.8.8 responded only $PING_COUNT/3 times, trying 1.1.1.1"
        
        log_status "Testing connectivity to 1.1.1.1"
        PING_COUNT=$(ping -c 10 1.1.1.1 | grep "received" | awk '{print $4}')
        if [ "$PING_COUNT" -ge 3 ]; then
            log_status "SUCCESS: 1.1.1.1 responded $PING_COUNT/3 times"
            INTERNET_OK=true
        else
            log_status "FAILED: 1.1.1.1 responded only $PING_COUNT/3 times"
        fi
    fi
    
    if [ "$INTERNET_OK" = true ]; then
        break
    elif [ $attempt -eq 1 ]; then
        log_status "First attempt failed, waiting 60 seconds before retry..."
        sleep 60
    fi
done

if [ "$INTERNET_OK" = false ]; then
    log_status "ERROR: VM cannot reach internet after 2 attempts - both 8.8.8.8 and 1.1.1.1 failed"
    exit 1
fi

# Test risoluzione DNS
log_status "Testing DNS connectivity..."
for attempt in 1 2; do
    log_status "DNS test attempt $attempt/2"
    DNS_OK=false
    
    log_status "Testing DNS resolution for google.com"
    if ping -c 2 google.com > /dev/null 2>&1; then
        log_status "SUCCESS: google.com DNS resolution and connectivity working"
        DNS_OK=true
    else
        log_status "FAILED: google.com DNS resolution failed, trying cloudflare.com"
        
        log_status "Testing DNS resolution for cloudflare.com"
        if ping -c 2 cloudflare.com > /dev/null 2>&1; then
            log_status "SUCCESS: cloudflare.com DNS resolution and connectivity working"
            DNS_OK=true
        else
            log_status "FAILED: cloudflare.com DNS resolution failed"
        fi
    fi
    
    if [ "$DNS_OK" = true ]; then
        break
    elif [ $attempt -eq 1 ]; then
        log_status "First DNS attempt failed, waiting 60 seconds before retry..."
        sleep 60
    fi
done

if [ "$DNS_OK" = false ]; then
    log_status "ERROR: VM cannot resolve DNS after 2 attempts - both google.com and cloudflare.com failed"
    exit 1
fi

log_status "All connectivity tests passed - proceeding with installation"

# Aggiornamento sistema
log_status "Starting system update..."
for attempt in 1 2; do
    log_status "System update attempt $attempt/2"
    if dnf update -y; then
        log_status "SUCCESS: System update completed successfully"
        break
    else
        log_status "FAILED: System update failed on attempt $attempt"
        if [ $attempt -eq 1 ]; then
            log_status "Waiting 30 seconds before retry..."
            sleep 30
        else
            log_status "ERROR: System update failed after 2 attempts"
            exit 1
        fi
    fi
done

# Installazione pacchetti core
log_status "Installing core packages..."
PACKAGES="traceroute tcpdump amazon-cloudwatch-agent logrotate rsyslog nftables"
for attempt in 1 2; do
    log_status "Core packages installation attempt $attempt/2"
    if dnf install -y $PACKAGES; then
        log_status "SUCCESS: Core packages installed successfully: $PACKAGES"
        break
    else
        log_status "FAILED: Core packages installation failed on attempt $attempt"
        log_status "Failed packages: $PACKAGES"
        if [ $attempt -eq 1 ]; then
            log_status "Waiting 30 seconds before retry..."
            sleep 30
        else
            log_status "ERROR: Core packages installation failed after 2 attempts"
            exit 1
        fi
    fi
done

# Installazione SSM Agent
log_status "Installing SSM agent..."
for attempt in 1 2; do
    log_status "SSM agent installation attempt $attempt/2"
    if dnf install -y amazon-ssm-agent; then
        log_status "SUCCESS: SSM agent installed successfully"
        break
    else
        log_status "FAILED: SSM agent installation failed on attempt $attempt"
        log_status "Failed package: amazon-ssm-agent"
        if [ $attempt -eq 1 ]; then
            log_status "Waiting 30 seconds before retry..."
            sleep 30
        else
            log_status "ERROR: SSM agent installation failed after 2 attempts"
            exit 1
        fi
    fi
done

log_status "Configuring SSM agent service..."
if systemctl enable amazon-ssm-agent && systemctl start amazon-ssm-agent; then
    log_status "SUCCESS: SSM agent service enabled and started"
else
    log_status "ERROR: Failed to configure SSM agent service"
    exit 1
fi

log_status "All package installations completed successfully"

log_status "Verifying nftables installation"
if ! command -v nft &> /dev/null; then
    log_status "ERROR: nft command not found after installation"
    exit 1
fi
log_status "SUCCESS: nft command is available"

# Abilita IP Forwarding
log_status "Enable IP Forwarding"
echo "net.ipv4.ip_forward=1" | tee /etc/sysctl.d/99-ip-forward.conf
chmod 644 /etc/sysctl.d/99-ip-forward.conf
sysctl --system

# Identifica interfacce di rete (pubblica e privata)
log_status "Getting all ENI except Docker ones"
INTERFACES=($(ls /sys/class/net | grep -v "lo\|docker"))
PUBLIC_INTERFACE=$${INTERFACES[0]}
PRIVATE_INTERFACE=$${INTERFACES[1]}

if [ ! -z "$PUBLIC_INTERFACE" ]; then
    echo "First interface: $PUBLIC_INTERFACE"
else
    echo "No first interface found"
fi

if [ ! -z "$PRIVATE_INTERFACE" ]; then
    echo "Second interface: $PRIVATE_INTERFACE"
else
    echo "No second interface found"
fi

# Recupera metadata AWS e configura routing
log_status "Getting metadata for VPC..."
TOKEN=$(curl --request PUT "http://169.254.169.254/latest/api/token" --header "X-aws-ec2-metadata-token-ttl-seconds: 3600")
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region --header "X-aws-ec2-metadata-token: $TOKEN")
VPC_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/network/interfaces/macs/$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/mac)/vpc-id)

echo "Recovering CIDR for VPC: $VPC_ID"
log_status "Recovering CIDR for VPC: $VPC_ID"
VPC_CIDR=$(aws ec2 describe-vpcs --region $REGION --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock' --output text)
PRIVATE_GATEWAY=$(ip route show dev $PRIVATE_INTERFACE | grep -E "^default|^0.0.0.0" | awk '{print $3}' | head -1)
if [ -n "$PRIVATE_GATEWAY" ]; then
    ip route add $VPC_CIDR via $PRIVATE_GATEWAY dev $PRIVATE_INTERFACE 2>/dev/null || true
fi

# Crea servizio systemd per route persistenti
log_status "Creating static route"
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

log_status "Restarting systemd for the new service"
systemctl daemon-reexec
systemctl daemon-reload

log_status "Enabling new service on startup"
systemctl enable custom-routes.service

log_status "Launching immediately the service"
systemctl start custom-routes.service || log_status "WARNING: custom-routes service failed, but continuing"

# Configura nftables per funzionalità NAT
log_status "Creating nftables configuration directories"
mkdir -p /etc/nftables
mkdir -p /etc/sysconfig

log_status "Configuring nftables rules for NAT functionality"
cat > /etc/nftables/nat-instance.nft <<EOF
#!/usr/sbin/nft -f
flush ruleset
define PUBLIC_INTERFACE = "$PUBLIC_INTERFACE"
define PRIVATE_INTERFACE = "$PRIVATE_INTERFACE"

table inet nat_instance {
    chain input {
        type filter hook input priority filter; policy drop;
        iif "lo" accept
        iif \$PRIVATE_INTERFACE accept
        iif \$PUBLIC_INTERFACE ct state established,related accept
        iif \$PRIVATE_INTERFACE icmp type { echo-request, echo-reply } accept
%{ if enable_cloudwatch_logs ~}
        iif \$PRIVATE_INTERFACE log prefix "NFTables-Dropped-PRIVATE-IN: " level info
%{ endif ~}
    }
    
    chain forward {
        type filter hook forward priority filter; policy drop;
%{ if enable_cloudwatch_logs ~}
        iif \$PRIVATE_INTERFACE oif \$PUBLIC_INTERFACE log prefix "NFTables-PRIV-to-PUB: " level info
%{ endif ~}
        iif \$PRIVATE_INTERFACE oif \$PUBLIC_INTERFACE accept
        iif \$PUBLIC_INTERFACE oif \$PRIVATE_INTERFACE ct state established,related accept
%{ if enable_cloudwatch_logs ~}
        log prefix "NFTables-Dropped-FORWARD: " level info
%{ endif ~}
    }
    
    chain output {
        type filter hook output priority filter; policy accept;
        oif \$PUBLIC_INTERFACE accept
    }
    
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oif \$PUBLIC_INTERFACE masquerade
    }
}
EOF

log_status "Setting executable permissions on nftables configuration"
chmod +x /etc/nftables/nat-instance.nft

log_status "Loading nftables NAT configuration"
if /usr/sbin/nft -f /etc/nftables/nat-instance.nft; then
    log_status "SUCCESS: nftables rules loaded successfully"
else
    log_status "ERROR: Failed to load nftables rules"
    exit 1
fi

log_status "Verifying nftables rules are active"
if /usr/sbin/nft list ruleset | grep -q "nat_instance"; then
    log_status "SUCCESS: NAT instance rules are active"
else
    log_status "ERROR: NAT instance rules not found in active ruleset"
    exit 1
fi

log_status "Configuring nftables persistence"
cp /etc/nftables/nat-instance.nft /etc/sysconfig/nftables.conf

# Crea servizio systemd per nftables
log_status "Creating nftables systemd service"
cat > /etc/systemd/system/nftables-nat.service <<NFTEOF
[Unit]
Description=nftables NAT instance firewall
Before=network-pre.target
Wants=network-pre.target
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/nftables/nat-instance.nft
ExecReload=/usr/sbin/nft -f /etc/nftables/nat-instance.nft
ExecStop=/usr/sbin/nft flush ruleset
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
NFTEOF

log_status "Enabling and starting nftables-nat service"
systemctl daemon-reload
systemctl enable nftables-nat.service
systemctl start nftables-nat.service

if systemctl is-active --quiet nftables-nat.service; then
    log_status "SUCCESS: nftables-nat service is running"
else
    log_status "ERROR: nftables-nat service failed to start"
    systemctl status nftables-nat.service
    exit 1
fi

# Configura CloudWatch Agent
%{ if enable_cloudwatch_logs ~}
touch /var/log/iptables.log
chmod 640 /var/log/iptables.log
chown syslog:adm /var/log/iptables.log

cat <<EOF > /etc/rsyslog.d/10-nftables.conf
:msg,contains,"NFTables-" /var/log/iptables.log
& stop
EOF

systemctl restart rsyslog

tee /etc/logrotate.d/nat-traffic > /dev/null <<EOL
/var/log/iptables.log {
    hourly
    rotate 1
    size 10M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOL

echo "0 * * * * root /usr/sbin/logrotate /etc/logrotate.conf" | tee -a /etc/crontab

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
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/iptables.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "$INSTANCE_ID",
            "timezone": "UTC"
          }
        ]
      }
    }
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
%{ else ~}
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
%{ endif ~}

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

systemctl restart amazon-cloudwatch-agent

log_status "Userdata script execution completed"
