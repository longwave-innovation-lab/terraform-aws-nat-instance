#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

log_status() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_status "Starting userdata script execution"

# System update and package installation
dnf update -y
dnf install -y iptables-services traceroute tcpdump amazon-cloudwatch-agent logrotate rsyslog
dnf install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent



# Disable firewalld (Amazon Linux 2023 equivalent of nftables)
systemctl disable firewalld
systemctl stop firewalld

# Enable IP Forwarding
echo "net.ipv4.ip_forward=1" | tee /etc/sysctl.d/99-ip-forward.conf
chmod 644 /etc/sysctl.d/99-ip-forward.conf
sysctl --system

# Ottiene la lista delle interfacce di rete (escludendo lo e docker)
INTERFACES=($(ls /sys/class/net | grep -v "lo\|docker"))
# Salva la prima interfaccia nella variabile PUBLIC_INTERFACE
PUBLIC_INTERFACE=${INTERFACES[0]}
# Salva la seconda interfaccia nella variabile PRIVATE_INTERFACE
PRIVATE_INTERFACE=${INTERFACES[1]}
# Verifica se le interfacce esistono e stampa i risultati
if [ ! -z "$PUBLIC_INTERFACE" ]; then
    echo "Prima interfaccia: $PUBLIC_INTERFACE"
else
    echo "Nessuna prima interfaccia trovata"
fi

if [ ! -z "$PRIVATE_INTERFACE" ]; then
    echo "Seconda interfaccia: $PRIVATE_INTERFACE"
else
    echo "Nessuna seconda interfaccia trovata"
fi


# # Permetti traffico in ingresso sull'interfaccia privata
# sudo iptables -A INPUT -i $PRIVATE_INTERFACE -j ACCEPT
# sudo iptables -A INPUT -i $PRIVATE_INTERFACE -p icmp --icmp-type echo-request -j ACCEPT
# sudo iptables -A INPUT -i $PRIVATE_INTERFACE -p icmp --icmp-type echo-reply  -j ACCEPT

# # LOG per traffico bloccato in ingresso su PUBLIC *PRIMA* della regola DROP
# sudo iptables -A INPUT -i $PUBLIC_INTERFACE -j LOG --log-prefix "IPTables-Dropped-PUB-IN: " --log-level 7

# sudo iptables -I FORWARD 1 -i $PRIVATE_INTERFACE -o $PUBLIC_INTERFACE -j LOG --log-prefix "IPTables-PRIV-to-PUB: " --log-level 7
# sudo iptables -A FORWARD -i $PRIVATE_INTERFACE -o $PUBLIC_INTERFACE -j ACCEPT

# # Permetti traffico in uscita sull'interfaccia pubblica
# sudo iptables -A OUTPUT -o $PUBLIC_INTERFACE -j ACCEPT

# # Permetti traffico in ingresso sull'interfaccia pubblica solo per connessioni stabilite e correlate
# sudo iptables -A INPUT -i $PUBLIC_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
# sudo iptables -A FORWARD -i $PUBLIC_INTERFACE -o $PRIVATE_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

# # Configurazione NAT (Masquerading)
# sudo iptables -t nat -A POSTROUTING -o $PUBLIC_INTERFACE -j MASQUERADE

# # Logging del traffico dalla privata alla pubblica
# sudo iptables -A FORWARD -i $PRIVATE_INTERFACE -o $PUBLIC_INTERFACE -j LOG --log-prefix "IPTables-PRIV-to-PUB: " --log-level 4 

# # Logging del traffico bloccato in ingresso solo sull'interfaccia privata
# sudo iptables -A INPUT -i $PRIVATE_INTERFACE -j LOG --log-prefix "IPTables-Dropped-IN: " --log-level 4 

# # Logging del traffico bloccato in forward dall'interfaccia privata
# sudo iptables -A FORWARD -i $PRIVATE_INTERFACE -j LOG --log-prefix "IPTables-Dropped-FWD: " --log-level 4

# # Blocca l'accesso da pubblica (queste regole vanno alla fine)
# sudo iptables -A INPUT -i $PUBLIC_INTERFACE -j DROP
# sudo iptables -I FORWARD 2 -j LOG --log-prefix "IPTables-Dropped-FWD: " --log-level 7
# sudo iptables -A FORWARD -j DROP



# Permetti traffico in ingresso sull'interfaccia privata
sudo iptables -A INPUT -i $PRIVATE_INTERFACE -j ACCEPT
sudo iptables -A INPUT -i $PRIVATE_INTERFACE -p icmp --icmp-type echo-request -j ACCEPT
sudo iptables -A INPUT -i $PRIVATE_INTERFACE -p icmp --icmp-type echo-reply  -j ACCEPT

# Logga il traffico che passa dall'interfaccia privata a quella pubblica
sudo iptables -I FORWARD 1 -i $PRIVATE_INTERFACE -o $PUBLIC_INTERFACE -j LOG --log-prefix "IPTables-PRIV-to-PUB: " --log-level 4
sudo iptables -A FORWARD -i $PRIVATE_INTERFACE -o $PUBLIC_INTERFACE -j ACCEPT

# Logga il traffico che non passa tra la privata e la pubblica
# sudo iptables -A FORWARD -i $PRIVATE_INTERFACE ! -o $PUBLIC_INTERFACE -j LOG --log-prefix "IPTables-NOT-PRIV-to-PUB: " --log-level 4

# Permetti traffico in uscita sull'interfaccia pubblica
sudo iptables -A OUTPUT -o $PUBLIC_INTERFACE -j ACCEPT

# Permetti traffico in ingresso sull'interfaccia pubblica solo per connessioni stabilite e correlate
sudo iptables -A INPUT -i $PUBLIC_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i $PUBLIC_INTERFACE -o $PRIVATE_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

# Configurazione NAT (Masquerading) per consentire l'uscita dei pacchetti sulla pubblica
sudo iptables -t nat -A POSTROUTING -o $PUBLIC_INTERFACE -j MASQUERADE

# Logging del traffico bloccato in ingresso sull'interfaccia privata
sudo iptables -A INPUT -i $PRIVATE_INTERFACE -j LOG --log-prefix "IPTables-Dropped-PRIVATE-IN: " --log-level 4

# Logging del traffico bloccato in forward dall'interfaccia privata
sudo iptables -A FORWARD -i $PRIVATE_INTERFACE -j LOG --log-prefix "IPTables-Dropped-PRIVATE-FWD: " --log-level 4

# Blocca il traffico in ingresso sulla pubblica (dopo aver loggato solo quello rilevante)
sudo iptables -A INPUT -i $PUBLIC_INTERFACE -j DROP

# Blocca tutto il traffico in forward non permesso
sudo iptables -A FORWARD -j DROP

# Save iptables rules
service iptables save

# Assicurati che il servizio iptables sia abilitato all'avvio
systemctl enable iptables
systemctl start iptables

# Salva le regole in modo persistente
/usr/libexec/iptables/iptables.init save

# Verifica che le regole siano state salvate
if [ -f "/etc/sysconfig/iptables" ]; then
    log_status "iptables rules saved successfully"
else
    log_status "ERROR: Failed to save iptables rules"
fi

# Crea uno script di init personalizzato per ricaricare le regole
cat <<'EOF' > /etc/systemd/system/iptables-restore.service
[Unit]
Description=Restore iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/sysconfig/iptables
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Abilita il nuovo servizio
systemctl daemon-reload
systemctl enable iptables-restore.service

# Verifica che tutto sia configurato correttamente
log_status "Checking iptables service status:"
systemctl status iptables
log_status "Checking iptables-restore service status:"
systemctl status iptables-restore



#creo il file iptables log
touch /var/log/iptables.log
chmod 640 /var/log/iptables.log
chown syslog:adm /var/log/iptables.log

# Configura rsyslog per il logging di iptables
cat <<EOF > /etc/rsyslog.d/10-iptables.conf
:msg,contains,"IPTables-" /var/log/iptables.log
& stop
EOF

systemctl restart rsyslog


# Configura logrotate per mantenere solo 2 ore di log
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

# Configura CloudWatch Agent
TOKEN=$(curl --request PUT "http://169.254.169.254/latest/api/token" --header "X-aws-ec2-metadata-token-ttl-seconds: 3600")
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id --header "X-aws-ec2-metadata-token: $TOKEN")
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region --header "X-aws-ec2-metadata-token: $TOKEN")
INSTANCETYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type  --header "X-aws-ec2-metadata-token: $TOKEN")
INSTANCEID=$INSTANCE_ID

tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null <<EOL
{
  "agent": {
    "run_as_user": "root",
    "omit_hostname":true,
    "metrics_collection_interval":60,
    "debug":false
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/iptables.log",
            "log_group_name": "/aws/ec2/natgw/logs",
            "log_stream_name": "$INSTANCE_ID",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics":{
      "namespace":"Custom/EC2",
      "metrics_collected":{
         "disk":{
            "measurement":[
              {
                  "name": "used_percent",
                  "rename": "disk_used_percent",
                  "unit": "Percent"
               }
            ],
            "drop_device": true,
            "append_dimensions":{
                        "InstanceId":"${INSTANCEID}",
                        "InstanceType":"${INSTANCETYPE}"
            },
            "metrics_collection_interval":60,
            "resources":[
               "/"
            ]
         },
         "mem":{
            "measurement":[
            {
               "name": "used_percent",
               "rename": "memory_used_percent",
               "unit": "Percent"
            }
            ],
	    "append_dimensions":{
                        "InstanceId":"${INSTANCEID}",
                        "InstanceType":"${INSTANCETYPE}"
            },
            "metrics_collection_interval":60
         },
         "swap":{
            "measurement":[
               {
               "name": "used_percent",
               "rename": "swap_used_percent",
               "unit": "Percent"
               }
            ],
	    "append_dimensions":{
                        "InstanceId":"${INSTANCEID}",
                        "InstanceType":"${INSTANCETYPE}"
            },
            "metrics_collection_interval":60
         }
      }
   }
}
EOL

# Avvia l'agente CloudWatch
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

systemctl restart amazon-cloudwatch-agent


log_status "Userdata script execution completed"


# Controllare il traffico NAT in tempo reale Puoi monitorare i pacchetti NAT con questo comando:
# watch -n 1 iptables -t nat -L -v -n

# vedere le regole incl nat
# iptables -t nat -L -v -n
