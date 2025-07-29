#!/bin/bash

# Setup slurm master node
#
# This script will setup the slurm master node

# import log prefix
source prefix.sh 


# ---- Install Configuration for DHCP ----

# Set variables
THIS_SERVER_IP="192.168.0.1"
DHCP_RANGE_START="192.168.0.10"
DHCP_RANGE_END="192.168.0.200"
SUBNET="192.168.0.0"
NETMASK="255.255.255.0"
GATEWAY=$THIS_SERVER_IP
DNS=$THIS_SERVER_IP
NETPLAN_CONF="/etc/netplan/50-cloud-init.yaml"

# ----------------------------------------

# ---- Install Configuration for name ----


ZONE_NAME="local"
ZONE_FILE="/etc/bind/zones/db.${ZONE_NAME}"
ZONE_DIR="/etc/bind/zones"

declare -A HOSTS
HOSTS=(
    ["master"]="192.168.0.10"
    ["worker1"]="192.168.0.11"
    ["worker2"]="192.168.0.12"
)

# ----------------------------------------

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root!"
    exit 1
fi

echo -e "$DEBUG Setting up DHCP server."


# Detect available network interfaces
echo -e "$DEBUG Detecting network interfaces..."

# List network interfaces excluding 'lo' (loopback) and non-active ones
interfaces=$(ip -o link show | awk -F': ' '{if ($2 != "lo") print $2}')

# If there are no interfaces, exit
if [ -z "$interfaces" ]; then
    echo -e "$ERROR No network interfaces found!"
    exit 1
fi

# Display interfaces for the user to select
echo -e "$DEBUG Available network interfaces:"
select INTERFACE in $interfaces; do
    if [ -n "$INTERFACE" ]; then
        echo -e "$SUCCESS You have selected: $INTERFACE"
        break
    else
        echo -e "$ERROR Invalid selection. Please try again."
    fi
done

# setup static IP on interface
echo -e "$DEBUG Setting up static IP address on the given ethernet interface"

# Backup the original Netplan file before modifying it
cp $NETPLAN_CONF $NETPLAN_CONF.bak

echo "    $INTERFACE:" >> "$NETPLAN_CONF"
echo "    dhcp4: false" >> "$NETPLAN_CONF"
echo "    addresses:" >> "$NETPLAN_CONF"
echo "        - $THIS_SERVER_IP/24" >> "$NETPLAN_CONF"


# Apply the Netplan configuration
echo -e "$DEBUG Applying Netplan configuration..."
netplan apply || { echo -e "$ERROR Failed to apply Netplan configuration."; exit 1; }

# Check if setting the IP was successfull
if ip addr show $INTERFACE | grep -q "inet $THIS_SERVER_IP"; then
    echo -e "$SUCCESS Set static IP $THIS_SERVER_IP for interface $INTERFACE"
else
    echo -e "$ERROR Could not set static IP $THIS_SERVER_IP for interface $INTERFACE"
    exit 1
fi


# install isc server
echo -e "$DEBUG Installing ISC DHCP Server..."
apt update -y || { echo -e "$ERROR Failed to update package list."; exit 1; }
sudo apt install -y isc-dhcp-server || { echo -e "$ERROR Failed to install ISC DHCP Server."; exit 1; }

# Step 2: Configure DHCP Server
echo -e "$DEBUG Configuring DHCP Server..."
cat > /etc/dhcp/dhcpd.conf <<EOF
# DHCP Server Configuration

subnet $SUBNET netmask $NETMASK {
    range $DHCP_RANGE_START $DHCP_RANGE_END;
    option routers $GATEWAY;
    option subnet-mask $NETMASK;
    option domain-name-servers $DNS;
}
EOF

# Step 3: Specify the interface to use
echo -e "$DEBUG Configuring the DHCP server to use interface $INTERFACE..."
echo "INTERFACESv4=\"$INTERFACE\"" > /etc/default/isc-dhcp-server

# Step 4: Start the DHCP Server
echo -e "$DEBUG Starting the ISC DHCP server..."
systemctl start isc-dhcp-server || { echo -e "$ERROR Failed to start ISC DHCP Server."; exit 1; }

# Step 5: Enable DHCP server to start on boot
echo -e "$DEBUG Enabling ISC DHCP server to start on boot..."
systemctl enable isc-dhcp-server || { echo -e "$ERROR Failed to enable ISC DHCP Server on boot."; exit 1; }

# Step 6: Check the status of the DHCP server
echo -e "$DEBUG Checking the status of the DHCP server..."
systemctl status isc-dhcp-server | grep Active > /dev/null
if [ $? -ne 0 ]; then
    echo -e "$ERROR ISC DHCP Server is not running or there is an issue with the service."
    exit 1
else
    echo -e "$SUCCESS ISC DHCP Server is running and active."
fi

# Step 7: Final message
echo -e "$SUCCESS DHCP Server setup is complete!"
echo -e "$SUCCESS The DHCP server is now running and should assign IP addresses between $DHCP_RANGE_START and $DHCP_RANGE_END."





# === Setup name server ===

echo -e "$DEBUG Setting up name server"

echo -e "$DEBUG Installing bind9 from apt"
sudo apt install -y bind9 bind9utils bind9-doc || { echo -e "$ERROR Failed to install ISC DHCP Server."; exit 1; }
echo -e "$SUCCESS done"


echo -e "$DEBUG Creating zone directory..."
mkdir -p "$ZONE_DIR"

echo -e "$DEBUG Creating zone file: $ZONE_FILE"
cat > "$ZONE_FILE" <<EOF
\$TTL    604800
@       IN      SOA     ns.${ZONE_NAME}. admin.${ZONE_NAME}. (
                            2         ; Serial
                       604800         ; Refresh
                        86400         ; Retry
                      2419200         ; Expire
                       604800 )       ; Negative Cache TTL

; Name servers
@       IN      NS      ns.${ZONE_NAME}.
ns      IN      A       ${DNS}
EOF

# Add host entries
for name in "${!HOSTS[@]}"; do
    echo "${name}    IN      A       ${HOSTS[$name]}" >> "$ZONE_FILE"
done

echo -e "$SUCCESS Zone file created."

echo -e "$DEBUG Updating named.conf.local..."
cat >> /etc/bind/named.conf.local <<EOF

zone "${ZONE_NAME}" {
    type master;
    file "${ZONE_FILE}";
};
EOF

echo -e "$DEBUG Updating named.conf.options..."
sed -i '/^options {/a \ \ \ \ allow-query { any; };' /etc/bind/named.conf.options
sed -i '/^options {/a \ \ \ \ listen-on { any; };' /etc/bind/named.conf.options
sed -i '/forwarders {/a \ \ \ \ \ \ 8.8.8.8;' /etc/bind/named.conf.options || true

echo -e "$DEBUG Checking configuration..."
named-checkconf
named-checkzone "$ZONE_NAME" "$ZONE_FILE"

echo -e "$DEBUG Restarting BIND9..."
systemctl restart bind9

echo -e "$SUCCESS Local DNS server is set up and running."
