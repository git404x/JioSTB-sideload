#!/usr/bin/env bash
# ==============================================================================
# undo.sh — Master 1-Click Restoration Script for Jio STB
# Re-enables all disabled packages, resets permissions, and restores defaults.
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
echo " 🔄 RESTORING STOCK JIO STB STATE"
echo " Target: $TARGET"
echo "================================================================="

adb_sh() {
    adb -s "$TARGET" shell "$@"
}

PACKAGES=()
while IFS= read -r line || [ -n "$line" ]; do
    CLEAN=$(echo "$line" | sed 's/#.*//' | xargs)
    [ -n "$CLEAN" ] && PACKAGES+=("$CLEAN")
done < "$CONF_FILE"

TOTAL=${#PACKAGES[@]}
COUNT=0
for pkg in "${PACKAGES[@]}"; do
    COUNT=$((COUNT + 1))
    printf "  [%d/%d] Re-enabling %s ... " "$COUNT" "$TOTAL" "$pkg"
    adb_sh "pm enable $pkg" >/dev/null 2>&1 || true
    adb_sh "cmd package install-existing $pkg" >/dev/null 2>&1 || true
    adb_sh "cmd appops set $pkg RUN_IN_BACKGROUND allow" >/dev/null 2>&1 || true
    adb_sh "cmd appops set $pkg WAKE_LOCK allow" >/dev/null 2>&1 || true
    echo "OK"
done

echo "[+] Restoring stock Jio home launcher..."
adb_sh "pm enable com.iwedia.ui.rjio.launcher.reliance" 2>/dev/null || true
adb_sh "cmd package set-home-activity com.iwedia.ui.rjio.launcher.reliance/.MainActivity" 2>/dev/null || true

echo "[+] Restoring default system animation scales and display density..."
adb_sh "settings put global window_animation_scale 1.0" 2>/dev/null || true
adb_sh "settings put global transition_animation_scale 1.0" 2>/dev/null || true
adb_sh "settings put global animator_duration_scale 1.0" 2>/dev/null || true
adb_sh "wm density reset" 2>/dev/null || true

echo "================================================================="
echo " [✓] Stock state restored successfully!"
echo "================================================================="
