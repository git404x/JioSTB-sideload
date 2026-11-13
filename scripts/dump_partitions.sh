#!/usr/bin/env bash
# ==============================================================================
# dump_partitions.sh — Extract Full Stock Boot & Recovery Partitions & Root Exec
#
# Ported and enhanced from ilikechocopies/sideload-jiostb pull_boot.sh
# Supports:
#   - JMSC models via sdknativeservice / rootshell2.jar (UID 0 Binder backdoor)
#   - JHS models via GenieACS / tr069native UID 0 on-boot command hook
#   - Slot detection (_a, _b, or single slot)
#   - Arbitrary root command execution (--cmd "id")
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$REPO_ROOT/backups"
RESOURCES_DIR="$REPO_ROOT/resources"
NBI_URL="${NBI_URL:-http://127.0.0.1:7557}"

TARGET="${1:-${STB_IP:-192.168.29.170}:${STB_PORT:-5555}}"
MODEL="${2:-${STB_MODEL:-jhs}}"
ROOT_CMD=""
SLOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cmd)
            ROOT_CMD="$2"; shift 2 ;;
        --slot)
            SLOT="$2"; shift 2 ;;
        *)
            if [[ "$1" == *:* ]] || [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                TARGET="$1"
                [[ "$TARGET" != *:* ]] && TARGET="${TARGET}:5555"
            elif [ "$1" = "jhs" ] || [ "$1" = "jmsc" ]; then
                MODEL="$1"
            fi
            shift ;;
    esac
done

mkdir -p "$BACKUP_DIR"

echo "================================================================="
echo " 🛡️ ROOT EXECUTION & STOCK PARTITION EXTRACTOR"
echo " Target: $TARGET"
echo " Model:  $MODEL"
echo " Output: $BACKUP_DIR"
echo "================================================================="

adb_sh() {
    adb -s "$TARGET" shell "$@"
}

# --- Detect Active Slot ---
if [ -z "$SLOT" ]; then
    DETECTED_SLOT=$(adb_sh "getprop ro.boot.slot_suffix" 2>/dev/null | tr -d '[:space:]' || true)
    if [ -n "$DETECTED_SLOT" ]; then
        SLOT="$DETECTED_SLOT"
    fi
fi

# ==============================================================================
# Model Specific Execution Engine
# ==============================================================================

if [ "$MODEL" = "jmsc" ]; then
    # JMSC Model — Uses sdknativeservice UID 0 backdoor via rootshell2.jar
    JAR_LOCAL="$RESOURCES_DIR/rootshell2.jar"
    JAR_REMOTE="/data/local/tmp/rootshell2.jar"

    if [ ! -f "$JAR_LOCAL" ]; then
        echo "[!] rootshell2.jar not found in $RESOURCES_DIR" >&2
        exit 1
    fi

    # Check if sdknativeservice is running
    if ! adb_sh "service check com.jio.sdk.sdknativeservice" 2>/dev/null | grep -q "found"; then
        echo "[*] sdknativeservice not running. Attempting to enable com.jio.sdk..."
        adb_sh "pm enable com.jio.sdk" >/dev/null 2>&1 || true
        sleep 1
    fi

    echo "[+] Pushing rootshell2.jar to $TARGET ..."
    adb -s "$TARGET" push "$JAR_LOCAL" "$JAR_REMOTE" >/dev/null

    jmsc_root_exec() {
        adb_sh "CLASSPATH=$JAR_REMOTE /system/bin/app_process / RootShell2 -c \"$1\"" 2>&1
    }

    if [ -n "$ROOT_CMD" ]; then
        echo "[*] Running root command via sdknativeservice:"
        jmsc_root_exec "$ROOT_CMD"
        exit 0
    fi

    PART_BOOT="boot${SLOT}"
    DEV_BOOT="/dev/block/by-name/${PART_BOOT}"
    # Fallback to direct /dev/block/boot
    if ! jmsc_root_exec "ls -l $DEV_BOOT" | grep -q "$DEV_BOOT"; then
        DEV_BOOT="/dev/block/boot${SLOT}"
    fi

    echo "[*] Extracting $DEV_BOOT as UID 0..."
    jmsc_root_exec "dd if=$DEV_BOOT of=/data/local/tmp/boot.img bs=4096 && chmod 666 /data/local/tmp/boot.img"
    adb -s "$TARGET" pull /data/local/tmp/boot.img "$BACKUP_DIR/boot_stock.img"

    # Also extract recovery if present
    DEV_REC="/dev/block/by-name/recovery${SLOT}"
    if jmsc_root_exec "ls -l $DEV_REC" | grep -q "$DEV_REC"; then
        echo "[*] Extracting $DEV_REC..."
        jmsc_root_exec "dd if=$DEV_REC of=/data/local/tmp/recovery.img bs=4096 && chmod 666 /data/local/tmp/recovery.img"
        adb -s "$TARGET" pull /data/local/tmp/recovery.img "$BACKUP_DIR/recovery_stock.img" 2>/dev/null || true
    fi

    echo "  [✓] Partitions saved successfully in $BACKUP_DIR:"
    ls -lh "$BACKUP_DIR/"

    echo ""
    echo "Magisk Patching Instructions:"
    echo "  1. Push to STB: adb -s $TARGET push $BACKUP_DIR/boot_stock.img /sdcard/boot_stock.img"
    echo "  2. Patch with Magisk on TV"
    echo "  3. Fastboot flash: fastboot flash ${PART_BOOT} magisk_patched.img"
    exit 0

else
    # JHS Model — Uses TR-069 tr069native daemon on-boot execution hook
    if [ -n "$ROOT_CMD" ]; then
        CMD="$ROOT_CMD"
    else
        CMD="dd if=/dev/block/boot of=/data/local/tmp/boot.img bs=4096 && chmod 666 /data/local/tmp/boot.img && dd if=/dev/block/recovery of=/data/local/tmp/recovery.img bs=4096 && chmod 666 /data/local/tmp/recovery.img"
    fi

    # Check if partitions were already written to /data/local/tmp
    if [ -z "$ROOT_CMD" ] && adb_sh "test -f /data/local/tmp/boot.img && echo exists" | grep -q "exists"; then
        echo "[+] Found /data/local/tmp/boot.img on device! Pulling..."
        adb -s "$TARGET" pull /data/local/tmp/boot.img "$BACKUP_DIR/boot_stock.img"
        adb -s "$TARGET" pull /data/local/tmp/recovery.img "$BACKUP_DIR/recovery_stock.img" 2>/dev/null || true
        echo "  [✓] Partitions saved in $BACKUP_DIR:"
        ls -lh "$BACKUP_DIR/"
        exit 0
    fi

    echo "[*] JHS model detected. Queuing TR-069 tr069native root task via GenieACS..."
    DEVICES_JSON=$(curl -s "$NBI_URL/devices/?projection=_id,_lastInform" 2>/dev/null || echo "[]")
    DEVICE_ID=$(python3 -c "import sys,json; devs=[d['_id'] for d in json.loads(sys.argv[1]) if 'TEST' not in d.get('_id','')]; print(devs[0] if devs else '')" "$DEVICES_JSON")

    if [ -z "$DEVICE_ID" ]; then
        echo "[!] No device registered in GenieACS yet."
        echo "    Start ACS via: ./stb acs start jhs"
        echo "    Then cold power-cycle the STB."
        exit 1
    fi

    enc() {
        python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
    }
    ENCODED_ID=$(enc "$DEVICE_ID")

    curl -s -X POST "$NBI_URL/devices/$ENCODED_ID/tasks?connection_request" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"setParameterValues\",\"parameterValues\":[[\"Device.JioSTB.Debugging.CommandLine.Enable\",1,\"xsd:unsignedInt\"],[\"Device.JioSTB.Debugging.CommandLine.OnBootExecuteCmd\",\"$CMD\",\"xsd:string\"],[\"Device.JioSTB.Debugging.CommandLine.ValidityDate\",\"2037-12-31T23:59:59.000Z\",\"xsd:dateTime\"],[\"Device.JioSTB.Debugging.CommandLine.SaveToFile\",1,\"xsd:unsignedInt\"]]}" >/dev/null

    echo "  [✓] Root command queued in GenieACS for $DEVICE_ID!"
    echo "      Command: $CMD"
    echo ""
    echo "  Action required:"
    echo "    1. Reboot the STB once to store the parameter in persistent DB."
    echo "    2. Reboot the STB second time to execute the command as root (UID 0) on boot."
    echo "    3. Run: ./stb dump to pull the generated image files."
fi
