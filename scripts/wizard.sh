#!/usr/bin/env bash
# ==============================================================================
# wizard.sh — Interactive End-to-End Unlock & Setup Wizard
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[32m'
C_CYAN='\033[36m'
C_YELLOW='\033[33m'
C_RED='\033[31m'

clear || true
cat <<'EOF'
================================================================================
   ___ _____ ____   ____ _____ _     
  / __|_   _| __ ) / ___|_   _| |    
  \__ \ | | |  _ \| |     | | | |    
  |___/ |_| |____/ \____| |_| |___|_ 
  INTERACTIVE JIO STB UNLOCK & PROVISIONING WIZARD
================================================================================
EOF

echo -e "${C_BOLD}Notice:${C_RESET} This wizard guides you through spoofing Jio's TR-069 ACS server"
echo -e "to permanently unlock ADB on your Jio Set-Top Box, install audited FOSS"
echo -e "TV apps, and surgically debloat carrier telemetry."
echo ""

# Step 1: Detect / Ask for Model
echo -e "${C_BOLD}[Step 1/6] Hardware Model Selection${C_RESET}"
echo " 1) JHS Model (JHSB200, JHSB100, Franklin SoC, Android 11) [Default]"
echo " 2) JMSC Model (JMSD200A, JMSC200A, Android 9/11)"
read -r -p "Select your model [1-2, default: 1]: " MODEL_CHOICE
MODEL_CHOICE="${MODEL_CHOICE:-1}"

if [ "$MODEL_CHOICE" = "2" ]; then
    MODEL="jmsc"
    PORT="8443"
else
    MODEL="jhs"
    PORT="9443"
fi
echo -e "  ${C_GREEN}Selected model: $MODEL (TR-069 TLS Port: $PORT)${C_RESET}\n"

# Step 2: Choose Redirection Vector
echo -e "${C_BOLD}[Step 2/6] Network Redirection Method${C_RESET}"
echo " 1) USB Eject Trick (AdGuard / LAN DNS Rewrite — Zero Cabling) [Recommended]"
echo " 2) Isolated Direct Ethernet Cable (PC <-> STB via dnsmasq)"
echo " 3) Isolated Wi-Fi Hotspot (Software AP via host Wi-Fi card)"
read -r -p "Select method [1-3, default: 1]: " NET_CHOICE
NET_CHOICE="${NET_CHOICE:-1}"

# Detect Host Primary LAN IP
HOST_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -1 || echo "192.168.29.X")

if [ "$NET_CHOICE" = "1" ]; then
    echo -e "\n${C_CYAN}--- USB EJECT DNS SETUP INSTRUCTIONS ---${C_RESET}"
    echo " 1. In your AdGuard Home, Pi-hole, or router DNS rewrites, add:"
    echo -e "      ${C_BOLD}acs.oss.jio.com -> $HOST_IP${C_RESET}"
    echo " 2. On the Jio STB, plug in any USB drive."
    echo " 3. Open: My Music -> Settings -> Eject USB -> Internal Storage -> Apps"
    echo "    -> Settings -> Network -> Advanced IP Settings -> Static IP"
    echo -e " 4. Set ${C_BOLD}DNS 1${C_RESET} to your PC's IP (${C_BOLD}$HOST_IP${C_RESET})."
    echo -e " 5. No physical WAN cables need to be disconnected!\n"
    read -r -p "Press Enter once static DNS is configured on the STB..."
elif [ "$NET_CHOICE" = "2" ]; then
    echo -e "\n${C_CYAN}--- DIRECT ETHERNET SETUP ---${C_RESET}"
    echo " Open a separate terminal and run:"
    echo -e "   ${C_BOLD}sudo ./stbctl net ethernet${C_RESET}"
    echo " Plug an Ethernet cable directly between your PC and the Jio STB."
    read -r -p "Press Enter once direct ethernet is running..."
elif [ "$NET_CHOICE" = "3" ]; then
    echo -e "\n${C_CYAN}--- WI-FI ACCESS POINT SETUP ---${C_RESET}"
    echo " Open a separate terminal and run:"
    echo -e "   ${C_BOLD}sudo ./stbctl net ap${C_RESET}"
    echo " Connect your Jio STB to the 'JioSTB-Unlock' Wi-Fi network."
    read -r -p "Press Enter once the hotspot is running..."
fi

# Step 3: Launch ACS Server
echo -e "\n${C_BOLD}[Step 3/6] Starting GenieACS & TLS Reverse Proxy (${MODEL})...${C_RESET}"
"$REPO_ROOT/services/setup_acs.sh" "$MODEL"

# Step 4: Cold Power Cycle Prompt
echo -e "\n${C_BOLD}[Step 4/6] Device Handshake${C_RESET}"
echo -e "${C_YELLOW}ACTION REQUIRED:${C_RESET} Cold-power-cycle your Jio STB now:"
echo " 1. Unplug the wall power adapter from the STB."
echo " 2. Wait 5 seconds."
echo " 3. Plug the power adapter back in."
echo ""
echo "[*] Watching for device check-in and waiting for ADB port 5555..."

read -r -p "Enter STB IP address [default: 192.168.29.170]: " INPUT_IP
STB_IP="${INPUT_IP:-192.168.29.170}"

MAX_TRIES=60
COUNT=0
CONNECTED=0

while [ $COUNT -lt $MAX_TRIES ]; do
    COUNT=$((COUNT + 1))
    if adb connect "${STB_IP}:5555" 2>/dev/null | grep -q "connected"; then
        if adb -s "${STB_IP}:5555" get-state 2>/dev/null | grep -q "device"; then
            CONNECTED=1
            break
        fi
    fi
    echo -n "."
    sleep 3
done
echo ""

if [ $CONNECTED -eq 1 ]; then
    echo -e "${C_GREEN}[✓] STB ADB IS UNLOCKED & CONNECTED (${STB_IP}:5555)!${C_RESET}\n"
else
    echo -e "${C_YELLOW}[!] Could not auto-detect ADB on ${STB_IP}:5555 yet.${C_RESET}"
    echo "    Check if RSA prompt appeared on TV screen and approve it."
    read -r -p "Press Enter to try connecting again or Ctrl+C to exit..."
    adb connect "${STB_IP}:5555" || true
fi

# Step 5: System Inspection
echo -e "${C_BOLD}[Step 5/6] Inspecting STB System & Hardware...${C_RESET}"
"$REPO_ROOT/stbctl" check "${STB_IP}:5555"

# Step 6: Next Actions
echo -e "\n${C_BOLD}[Step 6/6] Sideloading & Debloat Options${C_RESET}"
read -r -p "Download latest FOSS TV apps (SmartTube, Projectivy, LeanKeyboard, etc.)? [Y/n]: " DO_FETCH
DO_FETCH="${DO_FETCH:-Y}"
if [[ "$DO_FETCH" =~ ^[Yy]$ ]]; then
    "$REPO_ROOT/stbctl" fetch
fi

read -r -p "Install FOSS apps and set up LeanKeyboard & 280 DPI density? [Y/n]: " DO_INSTALL
DO_INSTALL="${DO_INSTALL:-Y}"
if [[ "$DO_INSTALL" =~ ^[Yy]$ ]]; then
    "$REPO_ROOT/stbctl" install "${STB_IP}:5555" "projectivy"
fi

read -r -p "Run UI and performance optimization (0.5x animations, keep awake)? [Y/n]: " DO_OPT
DO_OPT="${DO_OPT:-Y}"
if [[ "$DO_OPT" =~ ^[Yy]$ ]]; then
    "$REPO_ROOT/stbctl" optimize-ui "${STB_IP}:5555"
fi

read -r -p "Execute surgical debloat (disable 54 tracking/telemetry carrier packages)? [Y/n]: " DO_DEBLOAT
DO_DEBLOAT="${DO_DEBLOAT:-Y}"
if [[ "$DO_DEBLOAT" =~ ^[Yy]$ ]]; then
    "$REPO_ROOT/stbctl" debloat "${STB_IP}:5555"
fi

echo -e "\n================================================================="
echo -e " 🎉 ${C_GREEN}WIZARD COMPLETED SUCCESSFULLY!${C_RESET}"
echo -e " You can launch remote screen mirroring anytime via:"
echo -e "   ${C_BOLD}./stbctl scrcpy ${STB_IP}${C_RESET}"
echo -e " If you ever need to restore stock state, simply run:"
echo -e "   ${C_BOLD}./stbctl restore ${STB_IP}${C_RESET}"
echo -e "=================================================================\n"
