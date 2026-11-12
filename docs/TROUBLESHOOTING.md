# Jio STB Troubleshooting & Diagnostics Guide

This reference documents field-tested solutions to known hardware, networking, ADB, and runtime anomalies encountered when exploiting and debloating Jio Set-Top Boxes (Amlogic `franklin` / Android 11).

---

## 1. ADB Connectivity & Daemon Issues

### `adb: more than one device/emulator`
* **Root Cause:** Multiple active or stale ADB targets exist in `adb devices` (e.g. Ethernet direct-link `192.168.42.93:5555` offline alongside Wi-Fi `192.168.29.170:5555`).
* **Fix:** Explicitly disconnect the dead endpoint or specify the target via `-s`:
  ```bash
  adb disconnect 192.168.42.93:5555
  # Or target directly:
  adb -s 192.168.29.170:5555 shell
  ```

### Device Drops Offline After 5–10 Minutes (Sleep / Wi-Fi Disconnect)
* **Root Cause:** AOSP power management puts the Wi-Fi radio into low-power sleep when HDMI turns off or the box is idle.
* **Fix:** Enforce continuous AC awake state and disable Wi-Fi power saving:
  ```bash
  adb shell settings put global stay_on_while_plugged_in 3
  adb shell settings put global wifi_sleep_policy 2
  ```

---

## 2. Display, Resolution & Overscan Anomalies

### Apps Overflow Screen Borders (Cropped UI / Bleed)
* **Root Cause:** Modern TVs (especially Mi TV, Xiaomi TV, TCL) enable legacy HDMI overscan by default, zooming the 1080p input frame by ~5%. Additionally, Android 11 phone/tablet apps expect high UI density.
* **Fix:**
  1. **TV Side (Mandatory):** Go to TV Display Settings -> Picture -> Aspect Ratio. Change from `16:9` to **`Just Scan`**, **`Original`**, or **`Point-to-Point (1:1)`**.
  2. **STB Density Override:** Set the display density to 280 DPI:
     ```bash
     adb shell wm density 280
     ```
  *(Note: `wm overscan` is deprecated and non-functional on Android 11+).*

---

## 3. Application & Package Installation

### `INSTALL_FAILED_NO_MATCHING_ABIS` (-113)
* **Root Cause:** The Jio STB (JHSB200 / franklin) runs a 32-bit `armeabi-v7a` userland on top of its 64-bit Cortex-A53 silicon. Sideloading 64-bit-only (`arm64-v8a`) APKs triggers this failure.
* **Fix:** Always ensure multi-arch or 32-bit builds are targeted. The bundled dynamic fetcher (`scripts/fetch_foss_apks.sh`) automatically pulls the official multi-arch package releases.

### Streaming Apps (JioTV+, JioCinema, Hotstar) Missing from Launcher
* **Root Cause:** Jio deliberately stripped `android.intent.category.LAUNCHER` and `android.intent.category.LEANBACK_LAUNCHER` from `com.jio.media.jiotvplus` and other apps to prevent them from surfacing in non-Jio launchers.
* **Fix:**
  - Launch directly via component intent:
    ```bash
    adb shell monkey -p com.jio.media.jiotvplus -c android.intent.category.DEFAULT 1
    ```
  - Or use **KeyMapper** (`io.github.sds100.keymapper`) to bind a remote button (e.g. Live TV button) to launch the package intent.

### Shizuku `app_process` Crash (`Aborted`)
* **Root Cause:** Shizuku starter binaries mismatch the specific Amlogic 32-bit userland zygote configuration.
* **Fix:** Shizuku is completely unnecessary. Grant native AOSP Session Package Installer permissions via AppOps directly through ADB:
  ```bash
  adb shell appops set com.aurora.store REQUEST_INSTALL_PACKAGES allow
  adb shell appops set com.looker.droidify REQUEST_INSTALL_PACKAGES allow
  ```

---

## 4. Container & TLS Reverse Proxy Failures

### Podman `short-name "mongo:7.0"` or Policy Evaluation Error
* **Root Cause:** Rootless Podman without `/etc/containers/registries.conf` or unqualified image short-names.
* **Fix:** `services/docker-compose.yml` uses fully qualified image references (`docker.io/library/mongo:7.0` and `docker.io/drumsergio/genieacs:1.2.13.2`). Ensure `~/.config/containers/policy.json` exists with `{"default": [{"type": "insecureAccept"]}`.

### Port 3000 Collision with Host AdGuard Home
* **Root Cause:** Default GenieACS Web UI binds to `:3000`, colliding with local AdGuard Home or Gitea instances.
* **Fix:** In `services/docker-compose.yml`, the web interface is remapped to `3008:3000`. Access the UI at `http://localhost:3008`.

---

## 5. Exploitation & Model Architecture

### JHS vs JMSC Model Discrepancy
* **JMSC Models:** Expose `com.jio.sdk.sdknativeservice` (Java Binder IPC / `RootShell2.jar`). Root commands can be sent directly over local socket.
* **JHS Models (JHSB200, JHSB100):** Do **not** contain `sdknativeservice`. Root access is achieved through the native early-boot daemon `/system/bin/tr069native` triggered via CWMP parameters:
  ```xml
  Device.JioSTB.Debugging.CommandLine.Enable = 1
  Device.JioSTB.Debugging.CommandLine.OnBootExecuteCmd = "<command>"
  ```
  *(Requires two reboots: Reboot 1 writes to persistent DB; Reboot 2 executes command as UID 0 before Android zygote initializes).*
