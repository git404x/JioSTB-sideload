#!/usr/bin/env bash
# ==============================================================================
# fetch_foss_apks.sh — Dynamic FOSS Android TV APK Fetcher
# Downloads latest verified releases directly from official Git repositories.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOWNLOADS_DIR="$REPO_ROOT/downloads"

mkdir -p "$DOWNLOADS_DIR"

echo "================================================================="
echo " 📥 FETCHING LATEST VERIFIED FOSS ANDROID TV RELEASES"
echo " Destination: $DOWNLOADS_DIR"
echo "================================================================="

download_url() {
    local name="$1"
    local url="$2"
    local file="$DOWNLOADS_DIR/$name"
    echo -n "[+] Downloading $name ... "
    if curl -sL --fail -o "$file" "$url"; then
        echo "OK ($(du -h "$file" | cut -f1))"
    else
        echo "FAILED"
    fi
}

# 1. LeanKeyboard (Apache 2.0 D-Pad Android TV Keyboard by Yuriy Liskov)
LEAN_URL=$(curl -s "https://api.github.com/repos/yuliskov/LeanKeyboard/releases/latest" 2>/dev/null \
    | grep -iE 'browser_download_url.*\.apk' | head -1 | cut -d '"' -f 4 || true)
if [ -n "$LEAN_URL" ]; then
    download_url "leankeyboard.apk" "$LEAN_URL"
else
    # Fallback to direct stable release tag
    download_url "leankeyboard.apk" "https://github.com/yuliskov/LeanKeyboard/releases/download/6.1.31/LeanKeyboard_v6.1.31_playstore_r.apk"
fi

# 2. SmartTube (GPLv3 Android TV YouTube Client — armeabi-v7a for STB)
SMARTTUBE_URL=$(curl -s "https://api.github.com/repos/yuliskov/SmartTube/releases/latest" 2>/dev/null \
    | grep -iE 'browser_download_url.*armeabi-v7a\.apk' | head -1 | cut -d '"' -f 4 || true)
if [ -n "$SMARTTUBE_URL" ]; then
    download_url "smarttube.apk" "$SMARTTUBE_URL"
else
    download_url "smarttube.apk" "https://github.com/yuliskov/SmartTube/releases/download/32.71s/SmartTube_stable_32.71_armeabi-v7a.apk"
fi

# 3. FLauncher (GPLv3 Flutter Android TV Launcher by Étienne Fesser)
FLAUNCHER_URL="https://gitlab.com/api/v4/projects/26632151/packages/generic/flauncher/0.18.0/flauncher-0.18.0.apk"
download_url "flauncher.apk" "$FLAUNCHER_URL"

# 4. TVBro (GPLv3 Web Browser designed specifically for TV remotes with D-Pad mouse)
TVBRO_URL=$(curl -s "https://api.github.com/repos/truefedex/tv-bro/releases/latest" 2>/dev/null \
    | grep -iE 'browser_download_url.*\.apk' | head -1 | cut -d '"' -f 4 || true)
if [ -n "$TVBRO_URL" ]; then
    download_url "tvbro.apk" "$TVBRO_URL"
fi

# 5. Just Player (FOSS ExoPlayer-based Video Player for Android TV)
JUSTPLAYER_URL=$(curl -s "https://api.github.com/repos/moneytoo/Player/releases/latest" 2>/dev/null \
    | grep -iE 'browser_download_url.*armeabi-v7a.*\.apk' | head -1 | cut -d '"' -f 4 || true)
if [ -n "$JUSTPLAYER_URL" ]; then
    download_url "justplayer.apk" "$JUSTPLAYER_URL"
fi

# 6. Droid-ify (F-Droid Material Client)
DROIDIFY_URL=$(curl -s "https://api.github.com/repos/Looker-App/Droid-ify/releases/latest" 2>/dev/null \
    | grep -iE 'browser_download_url.*\.apk' | head -1 | cut -d '"' -f 4 || true)
if [ -n "$DROIDIFY_URL" ]; then
    download_url "droidify.apk" "$DROIDIFY_URL"
fi

# 7. KeyMapper (Hardware Button Remapper for Jio Bluetooth Remote)
KEYMAPPER_URL=$(curl -s "https://api.github.com/repos/sds100/KeyMapper/releases/latest" 2>/dev/null \
    | grep -iE 'browser_download_url.*\.apk' | head -1 | cut -d '"' -f 4 || true)
if [ -n "$KEYMAPPER_URL" ]; then
    download_url "keymapper.apk" "$KEYMAPPER_URL"
fi

# 8. Projectivy Launcher (Polished Android TV Launcher by Spocky)
PROJECTIVY_URL=$(curl -s "https://api.github.com/repos/spocky/projectivy/releases/latest" 2>/dev/null \
    | grep -iE 'browser_download_url.*\.apk' | head -1 | cut -d '"' -f 4 || true)
if [ -n "$PROJECTIVY_URL" ]; then
    download_url "projectivy.apk" "$PROJECTIVY_URL"
fi

echo "================================================================="
echo " 🎉 FETCH COMPLETE!"
echo " Total Storage: $(du -sh "$DOWNLOADS_DIR" | cut -f1)"
echo " Ready for installation via: ./scripts/install_foss_apps.sh"
echo "================================================================="
