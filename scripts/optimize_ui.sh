#!/usr/bin/env bash
# ==============================================================================
# optimize_ui.sh — Android TV UI & System Performance Tuner
# Configures optimal animation speeds, display density, awake policies,
# and provisioning flags for smooth Android TV performance.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET="${1:-}"
IS_OLED="${2:-}"

resolve_target() {
    if [ -n "$TARGET" ]; then
        if [[ "$TARGET" != *:* ]]; then
            TARGET="${TARGET}:5555"
        fi
        echo "$TARGET"
        return
    fi
    local dev
    dev=$(adb devices | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+\s+device' | head -1 | awk '{print $1}' || true)
    if [ -z "$dev" ]; then
        dev=$(adb devices | grep -E '\s+device$' | head -1 | awk '{print $1}' || true)
    fi
    echo "$dev"
}

ACTIVE_DEV=$(resolve_target)
if [ -z "$ACTIVE_DEV" ]; then
    echo "[!] Error: No authorized ADB device found. Connect via 'adb connect <IP>:5555' first." >&2
    exit 1
fi

adb_cmd() {
    adb -s "$ACTIVE_DEV" "$@"
}

adb_sh() {
    adb -s "$ACTIVE_DEV" shell "$@"
}

echo "================================================================="
echo " ⚡ ANDROID TV UI & SYSTEM OPTIMIZATION"
echo " Target Device: $ACTIVE_DEV"
echo "================================================================="

# 1. Global Provisioning Flags
echo "[1/5] Setting global provisioning and development flags..."
adb_sh "settings put global device_provisioned 1"
adb_sh "settings put global development_settings_enabled 1"
echo "  [✓] device_provisioned=1, development_settings_enabled=1"

# 2. Window Animation Scales (0.5x for snappy UI responsiveness)
echo "[2/5] Tuning window animation and transition durations to 0.5x..."
adb_sh "settings put global window_animation_scale 0.5"
adb_sh "settings put global transition_animation_scale 0.5"
adb_sh "settings put global animator_duration_scale 0.5"
echo "  [✓] Animation scales set to 0.5x"

# 3. Power Management & Wi-Fi Radio Sleep Policies
echo "[3/5] Enforcing continuous AC power state and Wi-Fi active policy..."
adb_sh "settings put global stay_on_while_plugged_in 3"
adb_sh "settings put global wifi_sleep_policy 2"
echo "  [✓] stay_on_while_plugged_in=3 (never sleep on AC)"
echo "  [✓] wifi_sleep_policy=2 (keep Wi-Fi radio on during standby)"

# 4. Display Density Scaling (280 DPI)
echo "[4/5] Adjusting display density for 1080p Android TV interface..."
adb_sh "wm density 280"
echo "  [✓] Display density set to 280 DPI"

# 5. Sleep & Screensaver Policy
echo "[5/5] Configuring sleep and screensaver timeout..."
adb_sh "settings put system screen_off_timeout 300000" # 5 minutes
echo "  [✓] Standby timeout set to 5 minutes (300000 ms)"

if [ "$IS_OLED" = "--oled" ] || [ "$IS_OLED" = "oled" ]; then
    adb_sh "settings put secure screensaver_enabled 1"
    adb_sh "settings put secure screensaver_activate_on_sleep 1"
    echo "  [✓] OLED burn-in protection: Screensaver enforced"
fi

echo "================================================================="
echo " 🎉 SYSTEM & UI OPTIMIZATION COMPLETE!"
echo " Current Settings:"
echo "   Density:    $(adb_sh 'wm density')"
echo "   Animations: Window=$(adb_sh 'settings get global window_animation_scale'), Transition=$(adb_sh 'settings get global transition_animation_scale')"
echo "================================================================="
