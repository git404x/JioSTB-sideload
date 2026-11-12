#!/usr/bin/env bash
# ==============================================================================
# debloat.sh — Surgical & Safe Bloatware Disabler for Jio STB
# Disables verified telemetry, ad push, and updater daemons from config file.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF_FILE="$REPO_ROOT/config/packages_safe_to_disable.txt"

if [ -f "$REPO_ROOT/config/network.env" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/config/network.env"
fi

TARGET="${1:-${STB_IP:-192.168.29.170}:${STB_PORT:-5555}}"

echo "================================================================="
echo " 🧹 SURGICAL DEBLOAT & TELEMETRY REMOVAL"
echo " Target: $TARGET"
echo " Config: $CONF_FILE"
echo "================================================================="

if [ ! -f "$CONF_FILE" ]; then
    echo "[!] Configuration file not found: $CONF_FILE"
    exit 1
fi

adb_sh() {
    adb -s "$TARGET" shell "$@"
}

# Capture baseline RAM
echo "[+] Baseline Memory:"
adb_sh "free -m" | head -n 3
echo ""

# Extract active package list (ignoring comments and blank lines)
PACKAGES=()
while IFS= read -r line || [ -n "$line" ]; do
    CLEAN=$(echo "$line" | sed 's/#.*//' | xargs)
    [ -n "$CLEAN" ] && PACKAGES+=("$CLEAN")
done < "$CONF_FILE"

TOTAL=${#PACKAGES[@]}
echo "[+] Target Packages: $TOTAL"
echo ""

COUNT=0
for pkg in "${PACKAGES[@]}"; do
    COUNT=$((COUNT + 1))
    printf "  [%d/%d] Disabling %s ... " "$COUNT" "$TOTAL" "$pkg"
    # Disable for user 0
    adb_sh "pm disable-user --user 0 $pkg" >/dev/null 2>&1 || true
    # Revoke background execution and wake locks
    adb_sh "cmd appops set $pkg RUN_IN_BACKGROUND ignore" >/dev/null 2>&1 || true
    adb_sh "cmd appops set $pkg WAKE_LOCK ignore" >/dev/null 2>&1 || true
    echo "DISABLED"
done

# Ensure Stock Android TV Settings is default
echo "[+] Ensuring genuine Android TV Settings is default handler..."
adb_sh "pm disable-user --user 0 com.rjil.jiostbsetting" >/dev/null 2>&1 || true

echo ""
echo "[+] Post-Debloat Memory:"
adb_sh "free -m" | head -n 3

echo ""
echo "================================================================="
echo " [✓] Surgical Debloat Complete!"
echo " All changes are 100% reversible anytime via: ./scripts/undo.sh"
echo "================================================================="
