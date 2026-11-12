#!/usr/bin/env bash
# ==============================================================================
# setup_wifi_ap.sh — Wi-Fi Hotspot Mode for Jio STB Exploitation
# Creates a local software AP using nmcli/dnsmasq and spoofs acs.oss.jio.com.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$REPO_ROOT/config/network.env" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/config/network.env"
elif [ -f "$REPO_ROOT/config/network.env.example" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/config/network.env.example"
fi

WIFI_IFACE="${WIFI_IFACE:-wlan0}"
SSID="${AP_SSID:-JioSTB-Unlock}"
PASS="${AP_PASSPHRASE:-jiostbdebloat}"
HOST_IP="${AP_HOST_IP:-192.168.50.1}"
DHCP_START="${AP_DHCP_START:-192.168.50.50}"
DHCP_END="${AP_DHCP_END:-192.168.50.100}"
PID_FILE="/tmp/jiostb_ap_dnsmasq.pid"
CONF_FILE="/tmp/jiostb_ap_dnsmasq.conf"

teardown() {
    echo "================================================================="
    echo " 🛑 TEARING DOWN WI-FI HOTSPOT ($SSID)"
    echo "================================================================="
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        kill -0 "$PID" 2>/dev/null && kill "$PID" 2>/dev/null || true
        rm -f "$PID_FILE" "$CONF_FILE"
    fi
    nmcli connection down "$SSID" 2>/dev/null || true
    nmcli connection delete "$SSID" 2>/dev/null || true
    echo "  [✓] Hotspot stopped."
    exit 0
}

if [ "${1:-}" = "--teardown" ] || [ "${1:-}" = "down" ] || [ "${1:-}" = "stop" ]; then
    teardown
fi

if [ "$EUID" -ne 0 ]; then
    echo "[!] Root privileges required. Re-executing with sudo..."
    exec sudo "$0" "$@"
fi

echo "================================================================="
echo " 📡 JIO STB WI-FI ACCESS POINT SETUP"
echo " Interface: $WIFI_IFACE"
echo " SSID:      $SSID"
echo " Password:  $PASS"
echo " Gateway:   $HOST_IP/24"
echo " Spoofed:   acs.oss.jio.com -> $HOST_IP"
echo "================================================================="

# Create hotspot using NetworkManager
if command -v nmcli >/dev/null 2>&1; then
    echo "[1/3] Creating Wi-Fi Hotspot via nmcli..."
    nmcli connection delete "$SSID" 2>/dev/null || true
    nmcli device wifi hotspot ifname "$WIFI_IFACE" con-name "$SSID" ssid "$SSID" password "$PASS"
    nmcli connection modify "$SSID" ipv4.addresses "$HOST_IP/24" ipv4.method manual
    nmcli connection up "$SSID"
    echo "  [✓] Hotspot $SSID is active."
else
    echo "[!] nmcli not detected. Please ensure NetworkManager is available."
    exit 1
fi

echo "[2/3] Starting DNS spoofer for acs.oss.jio.com..."
cat <<EOF > "$CONF_FILE"
interface=$WIFI_IFACE
port=53
address=/acs.oss.jio.com/$HOST_IP
address=/api.jio.com/$HOST_IP
address=/jiostb.cdn.jio.com/$HOST_IP
EOF

dnsmasq -C "$CONF_FILE" -x "$PID_FILE"
echo "  [✓] DNS spoofing running (PID: $(cat "$PID_FILE"))."

echo "================================================================="
echo " 🚀 WI-FI HOTSPOT READY"
echo "================================================================="
echo " Action required:"
echo "  1. On your Jio STB, connect to Wi-Fi SSID: $SSID (Password: $PASS)."
echo "  2. Power cycle the STB. It will query acs.oss.jio.com via $HOST_IP."
echo " To stop this hotspot later: sudo ./services/network/setup_wifi_ap.sh --teardown"
echo "================================================================="
