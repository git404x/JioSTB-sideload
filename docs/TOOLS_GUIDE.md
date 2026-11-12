# Complete Tools Guide & CLI Manual (`stbctl` / `stb`)

The `stbctl` CLI (aliased as `stb`) is the unified command-line orchestrator for exploiting, managing, configuring, and debloating Jio Set-Top Boxes.

---

## Command Quick Reference

| Command | Syntax | Purpose |
| :--- | :--- | :--- |
| **`check`** | `./stb check [device]` | Inspects hardware, firmware, ABI, memory, storage, and ADB authorization state. |
| **`wizard`** | `./stb wizard` | Guided interactive end-to-end unlock, provisioning, and debloating assistant. |
| **`net`** | `./stb net <eth\|wifi\|down>` | Controls isolated direct Ethernet or software Wi-Fi AP redirection environments. |
| **`acs`** | `./stb acs <start\|stop> [model]` | Supervises GenieACS containers and multi-port TLS reverse proxy. |
| **`fetch`** | `./stb fetch [options]` | Dynamically downloads verified FOSS Android TV APKs driven by `config/apps.json`. |
| **`install`** | `./stb install [device] [launcher]` | Sideloads applications, enables LeanKeyboard IME, and sets default launcher. |
| **`optimize-ui`**| `./stb optimize-ui [device] [--oled]`| Configures 0.5x animations, 280 DPI density, awake policies, and OLED protection. |
| **`debloat`** | `./stb debloat [device]` | Disables 54 tracking/telemetry packages and cuts background privileges via AppOps. |
| **`restore`** | `./stb restore [device]` | 1-Click emergency factory reset restoring stock apps, launcher, and animations. |
| **`dump`** | `./stb dump [device] [model]` | Extracts stock `boot.img` and `recovery.img` partition dumps. |
| **`scrcpy`** | `./stb scrcpy [device]` | Launches hardware-accelerated Vulkan remote mirroring with UHID control. |
| **`shell`** | `./stb shell [device]` | Opens an interactive ADB shell into the STB. |
| **`reboot`** | `./stb reboot [device]` | Issues an immediate clean reboot to the STB. |

---

## Detailed Tool Documentation

### 1. `stb check`
Queries the target device and displays essential hardware and runtime properties:
```bash
./stb check
# Or specify a target explicitly:
./stb check 192.168.29.170:5555
```
**Reported Fields:**
- **Model:** Hardware variant (e.g. `JHSB200` or `JMSC200A`).
- **Platform:** Silicon chipset (`franklin` / Amlogic S905X).
- **Firmware:** Complete build ID (e.g. `STB-JHSB200-11.3.46`).
- **Android API:** AOSP version (e.g. `11` / API 30).
- **CPU ABI:** Native instruction set (`armeabi-v7a`).
- **Density:** Physical vs override DPI (e.g. `Physical: 320`, `Override: 280`).
- **Memory & Storage:** Real-time RAM consumption (`free -m`) and `/data` partition availability.

---

### 2. `stb wizard`
An interactive Stage 1 guided setup wizard inspired by the original `sideload-jiostb` pipeline:
```bash
./stb wizard
```
**Wizard Steps:**
1. **Model Selection:** Automatically adapts TLS ports and certificates (`jhs` :9443 vs `jmsc` :8443).
2. **Redirection Choice:** Guides you through either:
   - *Option 1 (Recommended):* Zero-cabling USB Eject static DNS rewrite.
   - *Option 2:* Direct Ethernet cabling.
   - *Option 3:* Software Wi-Fi AP.
3. **ACS Launch:** Automatically launches the backend container and reverse proxy.
4. **Power Cycle:** Instructs when to cold-power-cycle the STB (unplug wall adapter, wait 5s, reconnect).
5. **Handshake & Unlock:** Monitors ADB port 5555 until the STB checks in and accepts the authorization command.
6. **Provisioning:** Prompts to fetch FOSS APKs, install apps, tune UI, and execute surgical debloating.

---

### 3. `stb net`
Controls local network isolation engines:
- **Direct Ethernet Link:**
  ```bash
  sudo ./stb net eth
  ```
  Binds `enp2s0` (or configured interface) to `192.168.42.1/24`, runs an isolated `dnsmasq` DHCP server, blocks upstream gateway access to force TR-069 local recovery, and spoofs `acs.oss.jio.com -> 192.168.42.1`.
- **Software Wi-Fi AP:**
  ```bash
  sudo ./stb net wifi
  ```
  Broadcasts an isolated SSID (`JioSTB-Unlock`) with WPA2 passphrase, routing DNS to the host.
- **Teardown:**
  ```bash
  sudo ./stb net down
  ```
  Kills active `dnsmasq` instances, flushes IP aliases, and restores normal network routing.

---

### 4. `stb acs`
Supervises the TR-069 CWMP management infrastructure:
```bash
# Start backend for JHS models (JHSB200/100, port 9443):
./stb acs start jhs

# Start backend for JMSC models (JMSC200, port 8443):
./stb acs start jmsc

# Stop all backend containers and proxy:
./stb acs stop
```
- Remaps GenieACS Web UI to `http://localhost:3008` to prevent port collisions with host AdGuard Home or local services.
- Executes `services/tls/pass_front.py` to terminate TLS using forged certificates and proxy requests to GenieACS `:7547`.
- Automatically provisions `Device.ManagementServer.X_JIO_COM_USBDebugging = 1` valid until `2037-12-31`.

---

### 5. `stb fetch`
Dynamic, manifest-driven FOSS APK fetcher driven by `config/apps.json`:
```bash
# Fetch all applications defined in manifest:
./stb fetch

# Fetch a single application by ID:
./stb fetch --app smarttube

# Filter by target architecture (default: auto-detected or armeabi-v7a):
./stb fetch --abi armeabi-v7a

# Force re-download of cached packages:
./stb fetch --force
```
**Driver Types Supported in `config/apps.json`:**
- **`fdroid`:** Accepts package URLs (e.g. `https://f-droid.org/en/packages/app.smarttube.fdroid/`) or package IDs. Resolves latest version, matches nativecode ABI (`armeabi-v7a`), and downloads the official APK from `f-droid.org/repo/`.
- **`github`:** Accepts repository paths (`owner/repo`). Queries `releases/latest` API and filters assets for `.apk` matching the target ABI.
- **`gitlab`:** Accepts GitLab generic package projects and downloads multi-arch packages.
- **`direct`:** Direct static URL fallback.

---

### 6. `stb install`
Sideloads downloaded APKs and configures the Android TV runtime:
```bash
./stb install [device] [launcher]

# Example:
./stb install 192.168.29.170 projectivy
# Or install with FLauncher:
./stb install 192.168.29.170 flauncher
```
**Automated Configuration:**
- Sideloads all `.apk` files present in `downloads/`.
- Configures **LeanKeyboard** (`org.liskovsoft.androidtv.rukeyboard`) as the default system IME:
  `ime enable org.liskovsoft.androidtv.rukeyboard/.LeanKeyBoard`
  `ime set org.liskovsoft.androidtv.rukeyboard/.LeanKeyBoard`
- Grants AOSP package installer permissions to FOSS stores (`REQUEST_INSTALL_PACKAGES allow`).
- Configures Projectivy Accessibility Service for seamless Home button redirection.

---

### 7. `stb optimize-ui`
Tunes system animation, display scaling, and power policies:
```bash
./stb optimize-ui [device] [--oled]

# Example:
./stb optimize-ui 192.168.29.170 --oled
```
**Applied Tweaks:**
1. **Provisioning Flags:** `settings put global device_provisioned 1` and `development_settings_enabled 1`.
2. **Animation Scales:** Sets window, transition, and animator durations to `0.5x` for snappy remote responsiveness.
3. **Power Management:** `stay_on_while_plugged_in = 3` and `wifi_sleep_policy = 2` (prevents Wi-Fi radio sleep while idle).
4. **Display Density:** Overrides density to `280 DPI` (`wm density 280`) to eliminate mobile app overscan and clipping.
5. **Screen Timeout:** Sets standby timeout to 5 minutes (`300000 ms`). If `--oled` is specified, enforces ambient daydream screensaver activation to protect against burn-in.

---

### 8. `stb debloat`
Executes surgical package deactivation:
```bash
./stb debloat [device]
```
- Reads package definitions from `config/packages_safe_to_disable.txt`.
- Disables 54 verified tracking, telemetry, ad services, and cloud hooks (`pm disable-user --user 0`).
- Restricts background wakeups and background execution via AppOps (`RUN_IN_BACKGROUND ignore`, `WAKE_LOCK ignore`).
- Preserves 100% of core HAL, DRM, Bluetooth remote pairing, HDMI-CEC, and stock recovery stability.

---

### 9. `stb restore`
Master 1-click emergency factory rollback:
```bash
./stb restore [device]
```
- Re-enables all 54 stock carrier packages.
- Restores stock Jio Home launcher (`com.jio.media.jiohometv`).
- Resets display density to default (`320 DPI`).
- Restores standard 1.0x window animations.

---

### 10. `stb dump`
Extracts raw stock `boot.img` and `recovery.img` partitions:
```bash
./stb dump [device] [model]
```
- Detects A/B vs single-slot layout (`ro.boot.slot_suffix`).
- On **JHS models**, queues an on-boot UID 0 root hook via TR-069 (`/system/bin/tr069native` parameter injection).
- On **JMSC models**, utilizes `com.jio.sdk.sdknativeservice` root Binder IPC.
- Saves verified image files into `backups/`.

---

### 11. `stb scrcpy`
Launches ultra-low latency hardware-accelerated remote mirroring:
```bash
./stb scrcpy [device]
```
- Configures Amlogic hardware encoder: `--encoder='OMX.amlogic.video.encoder.avc'`.
- Uses Vulkan 1.4 video rendering engine.
- Uses UHID keyboard and mouse emulation (`--keyboard=uhid --mouse=uhid`) for zero-lag TV navigation directly from your workstation keyboard.
