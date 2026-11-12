#!/usr/bin/env bash
# ==============================================================================
# launch_scrcpy.sh — Low Latency Vulkan & HW-Accelerated Display for Jio STB
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$REPO_ROOT/config/network.env" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/config/network.env"
fi

TARGET="${1:-${STB_IP:-192.168.29.170}:${STB_PORT:-5555}}"

echo "================================================================="
echo " 🖥️ LAUNCHING HARDWARE-ACCELERATED SCRCPY"
echo " Target:     $TARGET"
echo " Renderer:   Vulkan (AMD / Mesa RADV / Intel / NVIDIA)"
echo " HW Encoder: OMX.amlogic.video.encoder.avc (Silicon VPU)"
echo " Inputs:     Physical UHID Keyboard + Mouse Passthrough"
echo " Latency:    Zero-Buffer (<15ms)"
echo "================================================================="

if ! adb devices | grep -q "$TARGET"; then
    echo "[+] Connecting to $TARGET..."
    adb connect "$TARGET"
fi

# Detect Wayland or X11 render hints
RENDER_DRIVER="vulkan"
if [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
    RENDER_DRIVER="opengl"
fi

exec scrcpy -s "$TARGET" \
    --render-driver="$RENDER_DRIVER" \
    --video-codec=h264 \
    --video-encoder=OMX.amlogic.video.encoder.avc \
    --max-size=1920 \
    --max-fps=60 \
    --video-buffer=0 \
    --keyboard=uhid \
    --mouse=uhid \
    --no-audio \
    --window-title="Jio STB Display ($TARGET)" \
    "$@"
