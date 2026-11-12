#!/usr/bin/env bash
# ==============================================================================
# install_foss_apps.sh — Sideload FOSS Stack & Configure TV Defaults
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOWNLOADS_DIR="$REPO_ROOT/downloads"

if [ -f "$REPO_ROOT/config/network.env" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/config/network.env"
fi

TARGET="${1:-${STB_IP:-192.168.29.170}:${STB_PORT:-5555}}"
PREFERRED_LAUNCHER="${2:-projectivy}" # 'projectivy' or 'flauncher'

echo "================================================================="
echo " 🚀 INSTALLING FOSS APPLICATION STACK"
echo " Target:   $TARGET"
echo " Launcher: $PREFERRED_LAUNCHER"
echo "================================================================="

adb_sh() {
    adb -s "$TARGET" shell "$@"
}

# 1. Install APKs from downloads directory
APKS=(
    "leankeyboard.apk"
    "projectivy.apk"
    "flauncher.apk"
    "smarttube.apk"
    "tvbro.apk"
    "justplayer.apk"
    "droidify.apk"
    "aurorastore.apk"
    "keymapper.apk"
)

for apk in "${APKS[@]}"; do
    FILE="$DOWNLOADS_DIR/$apk"
    if [ -f "$FILE" ]; then
        echo -n "[+] Installing $apk ... "
        if adb -s "$TARGET" install -r -g "$FILE" >/dev/null 2>&1; then
            echo "OK"
        else
            echo "FAILED"
        fi
    else
        echo "[!] $apk not found in $DOWNLOADS_DIR (run ./scripts/fetch_foss_apks.sh first)"
    fi
done

# 2. Configure LeanKeyboard (Apache 2.0 D-Pad Input)
echo "[+] Configuring LeanKeyboard as system default IME..."
adb_sh "ime enable org.liskovsoft.androidtv.rukeyboard/com.liskovsoft.leankeyboard.ime.LeanbackImeService" 2>/dev/null || true
adb_sh "ime set org.liskovsoft.androidtv.rukeyboard/com.liskovsoft.leankeyboard.ime.LeanbackImeService" 2>/dev/null || true
adb_sh "pm disable-user --user 0 com.jio.keyboard.swarachakra" 2>/dev/null || true

# 3. Configure Native Package Installer permissions for F-Droid and Aurora Store
echo "[+] Enabling Native Package Installer permissions..."
adb_sh "appops set com.aurora.store REQUEST_INSTALL_PACKAGES allow" 2>/dev/null || true
adb_sh "appops set com.looker.droidify REQUEST_INSTALL_PACKAGES allow" 2>/dev/null || true

# 4. Set Preferred Home Screen Launcher
echo "[+] Setting default home launcher to: $PREFERRED_LAUNCHER..."
if [ "$PREFERRED_LAUNCHER" = "projectivy" ]; then
    adb_sh "appops set com.spocky.projengmenu GET_USAGE_STATS allow" 2>/dev/null || true
    adb_sh "settings put secure enabled_accessibility_services 'com.iwedia.ledmanager/com.iwedia.ledmanager.KeyEventMonitorService:com.spocky.projengmenu/.services.ProjectivyAccessibilityService'" 2>/dev/null || true
    adb_sh "settings put secure accessibility_enabled 1" 2>/dev/null || true
    adb_sh "cmd package set-home-activity com.spocky.projengmenu/.ui.home.MainActivity" 2>/dev/null || true
    adb_sh "am start -n com.spocky.projengmenu/.ui.home.MainActivity" 2>/dev/null || true
else
    adb_sh "cmd package set-home-activity me.efesser.flauncher/.MainActivity" 2>/dev/null || true
    adb_sh "am start -n me.efesser.flauncher/.MainActivity" 2>/dev/null || true
fi

# 5. Optimize Display Density to Prevent Screen Overflow
echo "[+] Setting display override density to 280 DPI (prevents horizontal clipping)..."
adb_sh "wm density 280" 2>/dev/null || true

# 6. Animation Speed & Timeout Tuning
adb_sh "settings put global window_animation_scale 0.5" 2>/dev/null || true
adb_sh "settings put global transition_animation_scale 0.5" 2>/dev/null || true
adb_sh "settings put global animator_duration_scale 0.5" 2>/dev/null || true

echo "================================================================="
echo " [✓] FOSS Stack Installed & Configured Successfully!"
echo "================================================================="
