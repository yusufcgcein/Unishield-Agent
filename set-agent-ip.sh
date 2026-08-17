#!/bin/bash
# ============================================================
#  Unishield 360 Agent - Change Manager IP (Linux/macOS)
#
#  Use this on an ALREADY-INSTALLED agent to point it at a
#  different manager/collector, without reinstalling.
#
#  Usage:
#    sudo ./set-agent-ip.sh <MANAGER_IP> [PORT]
#
#  Examples:
#    sudo ./set-agent-ip.sh 100.110.74.122
#    sudo ./set-agent-ip.sh 203.0.113.10 1514
# ============================================================
set -e

if [ -z "$1" ]; then
    echo "Usage: sudo $0 <MANAGER_IP> [PORT]"
    exit 1
fi

NEW_IP="$1"
NEW_PORT="${2:-1514}"
CONF="/var/ossec/etc/ossec.conf"

echo "Unishield 360 Agent - setting manager to $NEW_IP:$NEW_PORT"

# Validate IP format
echo "$NEW_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || \
    { echo "ERROR: '$NEW_IP' is not a valid IP address"; exit 1; }

# Stop agent
echo "[1/3] Stopping agent..."
/var/ossec/bin/wazuh-control stop 2>/dev/null || true

# Update <address> in ossec.conf
echo "[2/3] Updating $CONF ..."
sed -i "s|<address>[^<]*</address>|<address>${NEW_IP}</address>|" "$CONF"
sed -i "s|<port>[0-9]*</port>|<port>${NEW_PORT}</port>|" "$CONF"

# Show the client block
grep -A4 '<client>' "$CONF" | head -6

# Start agent (auto re-enrolls if needed)
echo "[3/3] Starting agent..."
/var/ossec/bin/wazuh-control start

echo ""
echo "DONE. Agent now reports to $NEW_IP:$NEW_PORT"
echo "Verify: sudo /var/ossec/bin/wazuh-control status"
echo "        cat /var/ossec/etc/client.keys"
