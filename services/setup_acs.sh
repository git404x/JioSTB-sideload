#!/usr/bin/env bash
# ==============================================================================
# setup_acs.sh — Start GenieACS & Mongo, launch pass_front.py, queue unlock tasks
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
NBI_URL="http://127.0.0.1:7557"
MODEL="${1:-jhs}" # default to jhs or jmsc

# Ensure Podman container registries and policy exist
mkdir -p "$HOME/.config/containers"
if [ ! -f "$HOME/.config/containers/policy.json" ]; then
    echo '{"default":[{"type":"insecureAcceptAnything"}]}' > "$HOME/.config/containers/policy.json"
fi
if [ ! -f "$HOME/.config/containers/registries.conf" ]; then
    echo 'unqualified-search-registries = ["docker.io", "quay.io"]' > "$HOME/.config/containers/registries.conf"
fi

# Detect container runtime
if command -v podman-compose >/dev/null 2>&1; then
    COMPOSE_CMD="podman-compose -f $COMPOSE_FILE"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose -f $COMPOSE_FILE"
elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose -f $COMPOSE_FILE"
else
    echo "[!] Neither podman-compose nor docker-compose found in environment."
    echo "    Please run inside nix develop: nix develop"
    exit 1
fi

echo "[+] Starting GenieACS backend via: $COMPOSE_CMD up -d"
$COMPOSE_CMD up -d

echo "[+] Waiting for GenieACS NBI (:7557) to become healthy..."
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" "$NBI_URL/devices/" 2>/dev/null | grep -q "200"; then
        echo "[+] GenieACS NBI is healthy!"
        break
    fi
    sleep 1
    printf "."
done
echo ""

# Launch TLS reverse proxy in background if not already active
if pgrep -f "pass_front.py" >/dev/null 2>&1; then
    echo "[+] pass_front.py is already running."
else
    echo "[+] Launching pass_front.py (Model: $MODEL)..."
    python3 "$SCRIPT_DIR/tls/pass_front.py" --model "$MODEL" > "$REPO_ROOT/logs/pass_front.log" 2>&1 &
    PF_PID=$!
    mkdir -p "$REPO_ROOT/logs"
    echo "$PF_PID" > "$REPO_ROOT/logs/pass_front.pid"
    echo "[+] pass_front.py running with PID $PF_PID"
fi

echo ""
echo "================================================================="
echo " TR-069 ACS Ready & Waiting for Jio STB Inform"
echo "================================================================="
echo "Instructions:"
echo " 1. Ensure DNS redirection is active (acs.oss.jio.com -> host LAN IP)."
echo " 2. Cold-power-cycle the STB (unplug wall power, wait 5s, plug in)."
echo " 3. The STB will phone home on boot to :8443 or :9443."
echo ""
echo "Watching for device check-in..."

DEVICE_ID=""
for i in {1..60}; do
    DEVICES_JSON=$(curl -s "$NBI_URL/devices/?projection=_id,_lastInform" 2>/dev/null || echo "[]")
    REAL_DEVS=$(python3 -c "import sys,json; devs=[d['_id'] for d in json.loads(sys.argv[1]) if 'TEST' not in d.get('_id','')]; print(json.dumps(devs))" "$DEVICES_JSON" 2>/dev/null || echo "[]")
    COUNT=$(python3 -c "import sys,json; print(len(json.loads(sys.argv[1])))" "$REAL_DEVS" 2>/dev/null || echo "0")
    if [ "$COUNT" -gt 0 ]; then
        DEVICE_ID=$(python3 -c "import sys,json; print(json.loads(sys.argv[1])[0])" "$REAL_DEVS")
        echo -e "\n[+] Device detected in GenieACS: $DEVICE_ID"
        break
    fi
    sleep 3
    printf "Waiting for STB Inform... (%ds/180s)\r" "$((i * 3))"
done

if [ -z "$DEVICE_ID" ]; then
    echo -e "\n[!] Timed out waiting for device to inform. Check DNS override and ensure STB was power cycled."
    exit 1
fi

echo -e "\n[+] Queuing TR-069 ADB unlock tasks for $DEVICE_ID..."

enc() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}
ENCODED_ID=$(enc "$DEVICE_ID")

# Refresh object tree
curl -s -X POST "$NBI_URL/devices/$ENCODED_ID/tasks?connection_request" \
    -H "Content-Type: application/json" \
    -d '{"name":"refreshObject","objectName":""}' > /dev/null

if [ "$MODEL" = "jhs" ]; then
    # JHS Model family (JHSB200 / JHSC200 / JioOS 2.0)
    curl -s -X POST "$NBI_URL/devices/$ENCODED_ID/tasks?connection_request" \
        -H "Content-Type: application/json" \
        -d '{"name":"setParameterValues","parameterValues":[["Device.JioSTB.USB.USBDebugging",true,"xsd:boolean"],["Device.JioSTB.USB.DebugValidityDate","2037-01-01T00:00:00.000Z","xsd:dateTime"],["Device.JioSTB.FOTA.DowngradeEnable",true,"xsd:boolean"],["Device.JioSTB.FOTA.DowngradeValidityDate","2037-12-31T23:59:59.000Z","xsd:dateTime"]]}' > /dev/null
else
    # JMSC / JMSD Model family
    curl -s -X POST "$NBI_URL/devices/$ENCODED_ID/tasks?connection_request" \
        -H "Content-Type: application/json" \
        -d '{"name":"setParameterValues","parameterValues":[["Device.ManagementServer.USBDebugging",true,"xsd:boolean"],["Device.ManagementServer.USBDebuggingExpires","2037-12-31T23:59:59Z","xsd:dateTime"],["Device.X_000FB0.FOTA.Disable",true,"xsd:boolean"]]}' > /dev/null
fi

echo "  [✓] ADB unlock parameters queued until 2037!"
echo "  [✓] FOTA downgrade/disable queued!"
echo ""
echo "================================================================="
echo " 🎉 UNLOCK SUCCESSFUL"
echo " Port 5555 will open on the STB. Reconnect via:"
echo " adb connect <STB_IP>:5555"
echo "================================================================="
