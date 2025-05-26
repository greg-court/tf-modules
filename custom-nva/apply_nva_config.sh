#!/usr/bin/env bash
set -euo pipefail  # Exit on error and on use of unset vars – keeps the script safe.

################################################################################
# Wait until cloud-init has fully finished (cloud-init drops a sentinel file).
################################################################################
echo "NVA_CONFIG_SCRIPT: Waiting for cloud-init to complete..."
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
  echo "NVA_CONFIG_SCRIPT: Still waiting for cloud-init (/var/lib/cloud/instance/boot-finished)..."
  sleep 10
done
echo "NVA_CONFIG_SCRIPT: cloud-init finished or sentinel file found."
echo "NVA_CONFIG_SCRIPT: Starting NVA configuration application..."

################################################################################
# 1. Generate WireGuard server configuration  (/etc/wireguard/wg0.conf)
################################################################################
echo "NVA_CONFIG_SCRIPT: Writing /etc/wireguard/wg0.conf..."
mkdir -p /etc/wireguard
cat << EOF > /etc/wireguard/wg0.conf
[Interface]
Address     = ${wg_server_address_cidr}
PrivateKey  = ${wg_server_private_key}
ListenPort  = ${wg_listen_port}
# Allow traffic coming *from* the tunnel to reach Azure (trust) or Internet (untrust)
PostUp      = iptables -A FORWARD -i %i -o ${trust_iface_name} -j ACCEPT; iptables -A FORWARD -i %i -o ${untrust_iface_name} -j ACCEPT
PostDown    = iptables -D FORWARD -i %i -o ${trust_iface_name} -j ACCEPT; iptables -D FORWARD -i %i -o ${untrust_iface_name} -j ACCEPT

[Peer]  # on-prem
PublicKey   = ${wg_peer_public_key}
AllowedIPs  = ${wg_peer_combined_allowed_ips}
EOF
chmod 0600 /etc/wireguard/wg0.conf
echo "NVA_CONFIG_SCRIPT: Finished writing /etc/wireguard/wg0.conf."

################################################################################
# 2. Create firewall / forwarding script  (/opt/setup_firewall.sh)
################################################################################
echo "NVA_CONFIG_SCRIPT: Writing /opt/setup_firewall.sh..."
cat << EOF > /opt/setup_firewall.sh
#!/usr/bin/env bash
set -euo pipefail

echo "NVA_FIREWALL_SCRIPT: Starting firewall configuration..."

# ---------------------------------------------------------------------------
# Variable assignment (all injected by Terraform’s templatefile).
# ---------------------------------------------------------------------------
UNTRUST_IFACE="${untrust_iface_name}"
TRUST_IFACE="${trust_iface_name}"
WG_IFACE="wg0"

NVA_TRUST_SUBNET_CIDR="${trust_subnet_cidr}"
WG_SERVER_IP=\$(echo "${wg_server_address_cidr}" | cut -d'/' -f1)
WG_SERVER_TUNNEL_CIDR="${wg_actual_subnet_cidr}"
ONPREM_PEER_TUNNEL_IP="${wg_peer_allowed_ips_cidr}"
ONPREM_RANGES_STR="${routing_ranges_onprem_str}"
AZURE_SPOKE_RANGES_STR="${routing_ranges_azure_str}"

# ---------------------------------------------------------------------------
# 2.1 Enable IPv4 forwarding (kernel live + persist across reboots)
# ---------------------------------------------------------------------------
echo "NVA_FIREWALL_SCRIPT: Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
if ! grep -Fxq "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p

# ---------------------------------------------------------------------------
# 2.2 Flush all existing iptables rules and set sensible defaults
# ---------------------------------------------------------------------------
echo "NVA_FIREWALL_SCRIPT: Flushing existing iptables rules and setting default policies..."
iptables -F
iptables -X
for table in nat mangle; do iptables -t \$table -F; iptables -t \$table -X; done
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  ACCEPT

# ---------------------------------------------------------------------------
# 2.3 INPUT chain — traffic *to* the NVA itself
# ---------------------------------------------------------------------------
echo "NVA_FIREWALL_SCRIPT: Configuring INPUT chain rules..."
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# SSH from Azure side (trust)
echo "NVA_FIREWALL_SCRIPT: Allowing SSH on \$TRUST_IFACE (port 22)"
iptables -A INPUT -i "\$TRUST_IFACE" -p tcp --dport 22 -j ACCEPT

# SSH from a single allowed public IP on untrust
echo "NVA_FIREWALL_SCRIPT: Allowing SSH on \$UNTRUST_IFACE (port 22) from ${on_prem_source_ip}"
iptables -A INPUT -i "\$UNTRUST_IFACE" -p tcp --dport 22 -s "${on_prem_source_ip}" -j ACCEPT

# Ping / SSH to the WireGuard tunnel address (from on-prem ranges)
echo "NVA_FIREWALL_SCRIPT: Allowing ICMP and SSH to WG tunnel IP (\$WG_SERVER_IP) from on-prem"
if [ -n "\$ONPREM_PEER_TUNNEL_IP" ]; then
  iptables -A INPUT -i "\$WG_IFACE" -p icmp -s "\$ONPREM_PEER_TUNNEL_IP" -d "\$WG_SERVER_IP" -j ACCEPT
  iptables -A INPUT -i "\$WG_IFACE" -p tcp  --dport 22 -s "\$ONPREM_PEER_TUNNEL_IP" -d "\$WG_SERVER_IP" -j ACCEPT
fi
if [ -n "\$ONPREM_RANGES_STR" ]; then
  for ONPREM_CIDR in \$ONPREM_RANGES_STR; do
    iptables -A INPUT -i "\$WG_IFACE" -p icmp -s "\$ONPREM_CIDR" -d "\$WG_SERVER_IP" -j ACCEPT
    iptables -A INPUT -i "\$WG_IFACE" -p tcp  --dport 22 -s "\$ONPREM_CIDR" -d "\$WG_SERVER_IP" -j ACCEPT
  done
fi

# Allow WireGuard UDP handshake/keepalive on the untrust NIC
echo "NVA_FIREWALL_SCRIPT: Allowing WireGuard on \$UNTRUST_IFACE (UDP port ${wg_listen_port})"
iptables -A INPUT -i "\$UNTRUST_IFACE" -p udp --dport "${wg_listen_port}" -j ACCEPT

# ---------------------------------------------------------------------------
# 2.4 FORWARD chain — traffic routed *through* the NVA
# ---------------------------------------------------------------------------
echo "NVA_FIREWALL_SCRIPT: Configuring FORWARD chain rules..."
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

# Spoke-to-Spoke (east-west inside Azure)
echo "NVA_FIREWALL_SCRIPT: Allowing Spoke-to-Spoke traffic on \$TRUST_IFACE"
iptables -A FORWARD -i "\$TRUST_IFACE" -o "\$TRUST_IFACE" -j ACCEPT

# Azure → Internet
echo "NVA_FIREWALL_SCRIPT: Allowing Azure ➜ Internet traffic"
if [ -n "\$AZURE_SPOKE_RANGES_STR" ]; then
  for AZURE_CIDR in \$AZURE_SPOKE_RANGES_STR; do
    iptables -A FORWARD -i "\$TRUST_IFACE" -s "\$AZURE_CIDR" -o "\$UNTRUST_IFACE" -j ACCEPT
  done
else
  iptables -A FORWARD -i "\$TRUST_IFACE" -s "\$NVA_TRUST_SUBNET_CIDR" -o "\$UNTRUST_IFACE" -j ACCEPT
fi

# On-prem VPN ↔ Azure spokes
echo "NVA_FIREWALL_SCRIPT: Allowing On-prem ↔ Azure the other way via WG"
if [ -n "\$ONPREM_RANGES_STR" ] && [ -n "\$AZURE_SPOKE_RANGES_STR" ]; then
  for ONPREM_CIDR in \$ONPREM_RANGES_STR; do
    for AZURE_CIDR in \$AZURE_SPOKE_RANGES_STR; do
      iptables -A FORWARD -i "\$WG_IFACE"   -s "\$ONPREM_CIDR" -d "\$AZURE_CIDR" -o "\$TRUST_IFACE" -j ACCEPT
      iptables -A FORWARD -i "\$TRUST_IFACE" -s "\$AZURE_CIDR" -d "\$ONPREM_CIDR" -o "\$WG_IFACE"   -j ACCEPT
    done
  done
fi

# WG clients (and on-prem) → Internet
echo "NVA_FIREWALL_SCRIPT: Allowing WG clients & on-prem ➜ Internet"
iptables -A FORWARD -i "\$WG_IFACE" -s "\$WG_SERVER_TUNNEL_CIDR" -o "\$UNTRUST_IFACE" -j ACCEPT
if [ -n "\$ONPREM_RANGES_STR" ]; then
  for ONPREM_CIDR in \$ONPREM_RANGES_STR; do
    iptables -A FORWARD -i "\$WG_IFACE" -s "\$ONPREM_CIDR" -o "\$UNTRUST_IFACE" -j ACCEPT
  done
fi

# DNS to NVA
iptables -A INPUT -i "$TRUST_IFACE" -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i "$TRUST_IFACE" -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -i "$WG_IFACE"    -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i "$WG_IFACE"    -p tcp --dport 53 -j ACCEPT

# ---------------------------------------------------------------------------
# 2.5 NAT (masquerade) - every egress to the untrust NIC gets SNAT'd
# ---------------------------------------------------------------------------
echo "NVA_FIREWALL_SCRIPT: Configuring NAT rules..."
if [ -n "\$AZURE_SPOKE_RANGES_STR" ]; then
  for AZURE_CIDR in \$AZURE_SPOKE_RANGES_STR; do
    iptables -t nat -A POSTROUTING -s "\$AZURE_CIDR"           -o "\$UNTRUST_IFACE" -j MASQUERADE
  done
else
  iptables -t nat -A POSTROUTING -s "\$NVA_TRUST_SUBNET_CIDR"  -o "\$UNTRUST_IFACE" -j MASQUERADE
fi
iptables -t nat -A POSTROUTING -s "\$WG_SERVER_TUNNEL_CIDR"    -o "\$UNTRUST_IFACE" -j MASQUERADE
if [ -n "\$ONPREM_RANGES_STR" ]; then
  for ONPREM_CIDR in \$ONPREM_RANGES_STR; do
    iptables -t nat -A POSTROUTING -s "\$ONPREM_CIDR"          -o "\$UNTRUST_IFACE" -j MASQUERADE
  done
fi

# ---------------------------------------------------------------------------
# 2.6 Persist iptables rules to survive reboots
# ---------------------------------------------------------------------------
echo "NVA_FIREWALL_SCRIPT: Saving iptables rules..."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
mkdir -p /etc/iptables
iptables-save  > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

echo "NVA_FIREWALL_SCRIPT: Firewall configuration script finished."
EOF
chmod 0755 /opt/setup_firewall.sh
echo "NVA_CONFIG_SCRIPT: Finished writing /opt/setup_firewall.sh."

################################################################################
# 3. Add OS static routes before firing up the firewall script
################################################################################
echo "NVA_CONFIG_SCRIPT: Applying OS routes..."
if [ -n "${routing_ranges_azure_str}" ]; then
  for CIDR_TO_ROUTE in ${routing_ranges_azure_str}; do
    echo "NVA_CONFIG_SCRIPT: Adding OS route for $${CIDR_TO_ROUTE} via ${trust_subnet_gateway_ip} dev ${trust_iface_name}"
    ip route replace "$${CIDR_TO_ROUTE}" via "${trust_subnet_gateway_ip}" dev "${trust_iface_name}" \
      || echo "NVA_CONFIG_SCRIPT: Route operation for $${CIDR_TO_ROUTE} encountered an issue."
  done
else
  echo "NVA_CONFIG_SCRIPT: No Azure routing ranges specified."
fi

################################################################################
# 4. Configure BIND9 DNS (if enabled)
################################################################################
if [ "${enable_bind_server,,}" == "true" ]; then
    echo "NVA_CONFIG_SCRIPT: Configuring BIND9 DNS server..."

    # Write main config files
    if [ -n "${bind_named_conf_options_content:-}" ]; then
        echo "NVA_CONFIG_SCRIPT: Writing /etc/bind/named.conf.options"
        # Ensure /etc/bind exists (it should be created by package install)
        mkdir -p /etc/bind
        echo "${bind_named_conf_options_content}" > /etc/bind/named.conf.options
    else
        echo "NVA_CONFIG_SCRIPT: WARNING - bind_named_conf_options_content is empty."
    fi

    if [ -n "${bind_named_conf_local_content:-}" ]; then
        echo "NVA_CONFIG_SCRIPT: Writing /etc/bind/named.conf.local"
        mkdir -p /etc/bind
        echo "${bind_named_conf_local_content}" > /etc/bind/named.conf.local
    else
        echo "NVA_CONFIG_SCRIPT: WARNING - bind_named_conf_local_content is empty."
    fi

    # Write the primary zone file using the path variable
    if [ -n "${bind_primary_zone_file_content:-}" ] && [ -n "${bind_primary_zone_file_path:-}" ]; then
        PRIMARY_ZONE_DIR=$(dirname "${bind_primary_zone_file_path}")
        echo "NVA_CONFIG_SCRIPT: Ensuring BIND zone directory $PRIMARY_ZONE_DIR exists."
        mkdir -p "$PRIMARY_ZONE_DIR"
        echo "NVA_CONFIG_SCRIPT: Writing primary zone file to ${bind_primary_zone_file_path}"
        echo "${bind_primary_zone_file_content}" > "${bind_primary_zone_file_path}"
    else
        echo "NVA_CONFIG_SCRIPT: WARNING - Primary zone file content or path is empty."
    fi

    echo "NVA_CONFIG_SCRIPT: Setting BIND file/directory permissions..."
    chown -R root:bind /etc/bind
    find /etc/bind -type d -exec chmod 775 {} \; # dirs: rwxrwxr-x
    find /etc/bind -type f -exec chmod 664 {} \; # files: rw-rw-r--

    BIND_WORKING_DIR="/var/cache/bind" # Assuming this is in your named.conf.options
    if [ -d "$BIND_WORKING_DIR" ]; then
        echo "NVA_CONFIG_SCRIPT: Setting permissions for BIND working directory $BIND_WORKING_DIR"
        chown -R bind:bind "$BIND_WORKING_DIR"
        chmod -R 770 "$BIND_WORKING_DIR" # rwxrwx---
    else
        echo "NVA_CONFIG_SCRIPT: WARNING - BIND_WORKING_DIR $BIND_WORKING_DIR not found. Check named.conf.options."
    fi

    echo "NVA_CONFIG_SCRIPT: Validating BIND configuration..."

    if named-checkconf -z /etc/bind/named.conf; then
        echo "NVA_CONFIG_SCRIPT: BIND configuration appears valid."
    else
        echo "NVA_CONFIG_SCRIPT: BIND configuration validation FAILED. Please check BIND logs and NVA logs for details."
        exit 1 # Critical if BIND config is bad
    fi
else
    echo "NVA_CONFIG_SCRIPT: BIND9 DNS server configuration is disabled."
fi

################################################################################
# 5. Execute firewall script + enable services
################################################################################
echo "NVA_CONFIG_SCRIPT: Executing /opt/setup_firewall.sh..."
/opt/setup_firewall.sh

echo "NVA_CONFIG_SCRIPT: Enabling and starting netfilter-persistent..."
systemctl enable netfilter-persistent
systemctl start netfilter-persistent

echo "NVA_CONFIG_SCRIPT: Enabling and starting WireGuard (wg-quick@wg0)..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

if [ "${enable_bind_server,,}" == "true" ]; then
    echo "NVA_CONFIG_SCRIPT: Enabling and restarting BIND9 (bind9 service)..."
    systemctl enable bind9
    systemctl restart bind9 --no-block
fi

echo "NVA_CONFIG_SCRIPT: NVA configuration application finished."