#!/usr/bin/env bash
# ==============================================================================
# dump_partitions.sh — Extract Full Stock Boot & Recovery Partitions
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$REPO_ROOT/backups"
NBI_URL="http://127.0.0.1:7557"

if [ -f "$REPO_ROOT/config/network.env" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/config/network.env"
fi

TARGET="${1:-${STB_IP:-192.168.29.170}:${STB_PORT:-5555}}"
MODEL="${2:-${STB_MODEL:-jhs}}"

mkdir -p "$BACKUP_DIR"

echo "================================================================="
echo " 🛡️ EXTRACTING STOCK PARTITIONS (BOOT & RECOVERY)"
echo " Target: $TARGET"
echo " Model:  $MODEL"
echo " Output: $BACKUP_DIR"
echo "================================================================="

# Check if partitions were already written to /data/local/tmp by early boot hook
if adb -s "$TARGET" shell "ls -l /data/local/tmp/boot.img" >/dev/null 2>&1; then
    echo "[+] Found /data/local/tmp/boot.img on device! Pulling..."
    adb -s "$TARGET" pull /data/local/tmp/boot.img "$BACKUP_DIR/boot_stock.img"
    adb -s "$TARGET" pull /data/local/tmp/recovery.img "$BACKUP_DIR/recovery_stock.img" 2>/dev/null || true
    echo "  [✓] Partitions saved in $BACKUP_DIR:"
    ls -lh "$BACKUP_DIR/"
    exit 0
fi

echo "[*] Direct root permission needed to read /dev/block/boot."
if [ "$MODEL" = "jhs" ]; then
    echo "[*] JHS model detected. Queuing on-boot TR-069 root extraction task..."

    DEVICES_JSON=$(curl -s "$NBI_URL/devices/?projection=_id,_lastInform" 2>/dev/null || echo "[]")
    DEVICE_ID=$(python3 -c "import sys,json; devs=[d['_id'] for d in json.loads(sys.argv[1]) if 'TEST' not in d.get('_id','')]; print(devs[0] if devs else '')" "$DEVICES_JSON")

    if [ -z "$DEVICE_ID" ]; then
        echo "[!] No device registered in GenieACS yet."
        echo "    Please run: ./jiostb acs start && power cycle the STB on direct ethernet."
        exit 1
    fi

    enc() {
        python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
    }
    ENCODED_ID=$(enc "$DEVICE_ID")

    CMD="dd if=/dev/block/boot of=/data/local/tmp/boot.img bs=4096 && chmod 666 /data/local/tmp/boot.img && dd if=/dev/block/recovery of=/data/local/tmp/recovery.img bs=4096 && chmod 666 /data/local/tmp/recovery.img"

    curl -s -X POST "$NBI_URL/devices/$ENCODED_ID/tasks?connection_request" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"setParameterValues\",\"parameterValues\":[[\"Device.JioSTB.Debugging.CommandLine.Enable\",1,\"xsd:unsignedInt\"],[\"Device.JioSTB.Debugging.CommandLine.OnBootExecuteCmd\",\"$CMD\",\"xsd:string\"],[\"Device.JioSTB.Debugging.CommandLine.ValidityDate\",\"2037-12-31T23:59:59.000Z\",\"xsd:dateTime\"],[\"Device.JioSTB.Debugging.CommandLine.SaveToFile\",1,\"xsd:unsignedInt\"]]}" >/dev/null

    echo "  [✓] Root dump command queued in GenieACS for $DEVICE_ID!"
    echo "  Action: Reboot the STB twice to execute as root and write partitions."
    echo "  Then re-run: ./scripts/dump_partitions.sh"
else
    echo "[*] JMSC model detected. Checking for sdknativeservice root Binder..."
    if adb -s "$TARGET" shell "service check com.jio.sdk.sdknativeservice" 2>/dev/null | grep -q "found"; then
        echo "[+] sdknativeservice found! Executing dd via app_process..."
        # Root execution via sdknativeservice
        adb -s "$TARGET" shell "su -c 'dd if=/dev/block/by-name/boot_a of=/data/local/tmp/boot.img bs=4096 && chmod 666 /data/local/tmp/boot.img'" 2>/dev/null || true
        adb -s "$TARGET" pull /data/local/tmp/boot.img "$BACKUP_DIR/boot_stock.img"
    else
        echo "[!] sdknativeservice is not running. Start via: adb shell pm enable com.jio.sdk"
    fi
fi
