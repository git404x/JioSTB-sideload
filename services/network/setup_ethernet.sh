#!/usr/bin/env bash
# ==============================================================================
# setup_ethernet.sh — Direct Isolated Ethernet Link for Jio STB Exploitation
# Sets up static IP, isolated DHCP pool, and DNS hijacking for acs.oss.jio.com.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load configuration
if [ -f "$REPO_ROOT/config/network.env" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/config/network.env"
elif [ -f "$REPO_ROOT/config/network.env.example" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/config/network.env.example"
fi

IFACE="${ETHERNET_IFACE:-enp2s0}"
HOST_IP="${ETHERNET_HOST_IP:-192.168.42.1}"
SUBNET_MASK="${ETHERNET_SUBNET_MASK:-255.255.255.0}"
DHCP_START="${ETHERNET_DHCP_START:-192.168.42.50}"
DHCP_END="${ETHERNET_DHCP_END:-192.168.42.100}"
PID_FILE="/tmp/jiostb_dnsmasq.pid"
CONF_FILE="/tmp/jiostb_dnsmasq.conf"

teardown() {
    echo "================================================================="
    echo " 🛑 TEARING DOWN ISOLATED ETHERNET LINK ($IFACE)"
    echo "================================================================="
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "[+] Stopping dnsmasq (PID: $PID)..."
            kill "$PID" || true
        fi
        rm -f "$PID_FILE" "$CONF_FILE"
    fi

    echo "[+] Flushing IP addresses on $IFACE..."
    ip addr flush dev "$IFACE" 2>/dev/null || true

    echo "[+] Cleaning up iptables rules..."
    iptables -D FORWARD -i "$IFACE" -j DROP 2>/dev/null || true
    iptables -D INPUT -i "$IFACE" -p udp --dport 67 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i "$IFACE" -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i "$IFACE" -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i "$IFACE" -p tcp --dport 8443 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i "$IFACE" -p tcp --dport 9443 -j ACCEPT 2>/dev/null || true

    echo "  [✓] Teardown complete."
    exit 0
}

if [ "${1:-}" = "--teardown" ] || [ "${1:-}" = "down" ] || [ "${1:-}" = "stop" ]; then
    teardown
fi

if [ "$EUID" -ne 0 ]; then
    echo "[!] Root privileges required to configure networking. Re-executing with sudo..."
    exec sudo "$0" "$@"
fi

echo "================================================================="
echo " 🔌 JIO STB DIRECT ETHERNET LINK SETUP"
echo " Interface: $IFACE"
echo " Host IP:   $HOST_IP/24"
echo " DHCP Pool: $DHCP_START - $DHCP_END"
echo " Spoofed:   acs.oss.jio.com -> $HOST_IP"
echo "================================================================="

# Stop any previous instance
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    kill -0 "$PID" 2>/dev/null && kill "$PID" 2>/dev/null || true
    rm -f "$PID_FILE"
fi

echo "[1/4] Configuring $IFACE with static IP $HOST_IP/24..."
ip link set dev "$IFACE" up
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$HOST_IP/24" dev "$IFACE"
echo "  [✓] $IFACE configured."

echo "[2/4] Isolating STB from upstream WAN (forcing local TR-069 check-in)..."
iptables -I FORWARD 1 -i "$IFACE" -j DROP 2>/dev/null || true
iptables -I INPUT 1 -i "$IFACE" -p udp --dport 67 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -i "$IFACE" -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -i "$IFACE" -p udp --dport 53 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -i "$IFACE" -p tcp --dport 8443 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -i "$IFACE" -p tcp --dport 9443 -j ACCEPT 2>/dev/null || true
echo "  [✓] WAN isolation active."

echo "[3/4] Instantiating isolated dnsmasq configuration..."
sed \
    -e "s|__INTERFACE__|$IFACE|g" \
    -e "s|__HOST_IP__|$HOST_IP|g" \
    -e "s|__SUBNET_MASK__|$SUBNET_MASK|g" \
    -e "s|__DHCP_START__|$DHCP_START|g" \
    -e "s|__DHCP_END__|$DHCP_END|g" \
    "$SCRIPT_DIR/dnsmasq.conf.template" > "$CONF_FILE"

echo "[4/4] Starting dnsmasq..."
dnsmasq -C "$CONF_FILE" -x "$PID_FILE"
PID=$(cat "$PID_FILE")
echo "  [✓] dnsmasq running with PID $PID."

echo "================================================================="
echo " 🚀 DIRECT LINK IS LIVE & LISTENING"
echo "================================================================="
echo " Action required:"
echo "  1. Connect an Ethernet cable between your PC ($IFACE) and the Jio STB."
echo "  2. Cold power-cycle the STB (unplug wall power, wait 5s, reconnect)."
echo "  3. The STB will receive an IP and route TR-069 traffic to your local PC."
echo " To stop this setup later: sudo ./services/network/setup_ethernet.sh --teardown"
echo "================================================================="
