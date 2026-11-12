# JioSTB-sideload

> **Zero-Bloat, Pure-FOSS Exploitation, Management & Debloating Toolchain for Jio Set-Top Boxes**  
> Target Silicon: Amlogic S905X / `franklin` (Android 11) | Architecture: `armeabi-v7a` (32-bit userland)

---

## ⚡ Overview

`JioSTB-sideload` is a modular, declarative framework designed to unlock, secure, debloat, and manage Jio Set-Top Boxes (JHSB200 / JMSC models) without physical hardware tampering, UART soldering, or ISP fiber disconnections.

It leverages cryptographic certificate forgery (Sectigo/eMudhra & RILROOTCA), TR-069 CWMP session hijacking, and network redirection techniques to force persistent USB debugging (`adbd`) on boot, followed by a surgical 54-package debloat, replacement with audited FOSS TV alternatives, and ultra-low-latency Vulkan-accelerated remote display.

```
+-----------------------------------------------------------------------------------+
|                               REDIRECTION VECTORS                                |
|  [Option A] USB Eject Trick (AdGuard / LAN Router DNS rewrite - Zero Cabling)     |
|  [Option B] Isolated Direct Ethernet (PC eth <-> STB eth via dnsmasq)             |
|  [Option C] Software Wi-Fi AP (JioSTB-Unlock via host Wi-Fi NIC)                  |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
                     acs.oss.jio.com -> Host Workstation IP
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|                        PASS_FRONT TR-069 TLS REVERSE PROXY                        |
|   JMSC: Port 8443 (eMudhra CA)         │   JHS: Port 9443 (RILROOTCA CA)         |
|   - Strips mTLS requirements           │   - AES-128-CBC Network Check Bypass    |
|   - Session cookie affinity            │   - Forwards to GenieACS CWMP Engine    |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|                             GENIEACS v1.2.13.2 ENGINE                             |
|   Queues TR-069 Parameter:                                                        |
|   Device.ManagementServer.X_JIO_COM_USBDebugging = 1 (Expires: 2037-12-31)        |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|                            POST-EXPLOITATION PIPELINE                             |
|   1. Sideload FOSS TV Applications (LeanKeyboard, Projectivy, SmartTube, etc.)   |
|   2. Surgical Debloat (Disables 54 tracking/telemetry/carrier bloatware pkgs)     |
|   3. AppOps Hardening (Cuts RUN_IN_BACKGROUND and WAKE_LOCK on remaining apps)   |
|   4. Low-Latency Remote Display (Scrcpy Vulkan + Amlogic hardware AVC encoder)    |
+-----------------------------------------------------------------------------------+
```

---

## 💎 Key Features

- **100% Pure FOSS Policy:** Zero binary `.apk`, `.exe`, or `.dll` blobs committed to Git. All packages are dynamically fetched from audited upstream GitLab/GitHub/F-Droid releases via `scripts/fetch_foss_apks.sh`.
- **Reproducible Nix Toolchain:** Ships with `flake.nix` and `shell.nix` for instant sandbox activation (`direnv allow` or `nix develop`).
- **Zero-WAN Tampering:** Supports the non-destructive **USB Eject Static DNS trick**, completely removing the need to unplug the fiber optic cable or touch ISP equipment.
- **Surgical Debloating:** Disables 54 verified carrier bloat packages while maintaining 100% HDMI-CEC, Bluetooth voice remote, Widevine L1 DRM, and stock recovery stability.
- **Master 1-Click Rollback:** Instant restoration of all disabled packages, default launcher, display density, and animation speeds via `scripts/undo.sh`.
- **Vulkan Remote Display:** Pre-configured `scrcpy` profile utilizing Amlogic silicon hardware encoder (`OMX.amlogic.video.encoder.avc`) and UHID input emulation for instantaneous TV navigation from a PC.

---

## 🛠️ Hardware & Architecture Compatibility

| Feature | JHS Models (e.g. JHSB200, JHSB100) | JMSC Models (e.g. JMSC200) |
| :--- | :--- | :--- |
| **SoC / Silicon** | Amlogic S905X / `franklin` | Amlogic S905X / `amlogic` |
| **Android Version**| Android 11 (API 30) | Android 9 / 11 |
| **ABI Architecture**| 32-bit `armeabi-v7a` userland | 32-bit `armeabi-v7a` |
| **TR-069 Port** | Port **9443** (RILROOTCA CA) | Port **8443** (Sectigo/eMudhra CA) |
| **Network Check** | Encrypted AES-128-CBC `/network/check`| Unencrypted `/common/v1/network/check` |
| **Root Mechanism** | Early-boot `/system/bin/tr069native` UID 0 hook | Binder IPC `com.jio.sdk.sdknativeservice` |

---

## 🚀 Quickstart Guide

### 1. Enter the Environment
If using Nix:
```bash
nix develop
# or: direnv allow
```
If using standard Linux packages, ensure `android-tools`, `scrcpy`, `podman`, `podman-compose`, `dnsmasq`, and `python3` (with `pycryptodome` and `requests`) are installed.

Verify dependencies:
```bash
./jiostb check
```

---

### 2. Configure Network Redirection
Copy and adjust environment configuration if needed:
```bash
cp config/network.env.example config/network.env
```

Select your preferred redirection method:
- **Method 1 (Recommended - USB Eject Trick):** Follow [docs/USB_EJECT_DNS_METHOD.md](docs/USB_EJECT_DNS_METHOD.md) to set a static DNS pointing `acs.oss.jio.com` to your PC's LAN IP via AdGuard Home or local DNS.
- **Method 2 (Direct Ethernet Link):**
  ```bash
  sudo ./jiostb net eth
  ```
- **Method 3 (Software Wi-Fi AP):**
  ```bash
  sudo ./jiostb net wifi
  ```

---

### 3. Launch TR-069 Reverse Proxy & ACS
In a terminal, start the backend for your model type (`jhs` or `jmsc`):
```bash
./jiostb acs jhs
```
Cold power-cycle the STB (unplug wall adapter, wait 5 seconds, reconnect). The STB will query `acs.oss.jio.com`, undergo TLS handshake, check in via TR-069 Inform, and receive the persistent ADB authorization command.

---

### 4. Sideload FOSS Applications
Fetch the audited open-source TV application suite:
```bash
./jiostb fetch
```
Install and configure the applications on the STB:
```bash
./jiostb install 192.168.29.170
```
*Configures LeanKeyboard as default IME, sets UI density to 280 DPI, and grants native package installer permissions.*

---

### 5. Debloat Carrier Tracking & Bloatware
Execute surgical package deactivation:
```bash
./jiostb debloat 192.168.29.170
```
*Disables 54 telemetry, analytics, and advertising packages, and strips background execution/wakelock privileges via AppOps.*

---

### 6. Launch Remote Display (Optional)
Launch Vulkan-accelerated low-latency mirroring:
```bash
./jiostb scrcpy 192.168.29.170
```

---

## 📁 Repository Structure

```
JioSTB-sideload/
├── jiostb                          # Unified CLI entrypoint
├── flake.nix                       # Declarative Nix Flake
├── shell.nix                       # Pure Nix-shell fallback
├── config/
│   ├── network.env.example         # Interface, subnet, and port configuration
│   ├── packages_safe_to_disable.txt# Manifest of 54 debloatable carrier packages
│   ├── packages_critical_keep.txt  # HAL, DRM, Bluetooth, and core system manifest
│   └── packages_streaming_apps.txt # Official OTT streaming applications manifest
├── certs/
│   ├── acs.crt / acs.key           # Forged eMudhra & Sectigo server certificate & private key
│   ├── forged_chain.pem            # JMSC full certificate authority chain
│   └── rilrootca.pem               # JHS RILROOTCA authority certificate
├── services/
│   ├── docker-compose.yml          # GenieACS 1.2.13.2 + MongoDB 7.0 container definitions
│   ├── setup_acs.sh                # Container supervisor & TR-069 task provisioning
│   ├── tls/
│   │   └── pass_front.py           # Multi-port TR-069 TLS reverse proxy & bypass engine
│   └── network/
│       ├── setup_ethernet.sh       # Isolated direct-cable setup with dnsmasq
│       ├── setup_wifi_ap.sh        # Isolated software AP setup
│       └── dnsmasq.conf.template   # Dynamic DNS spoofing template
├── scripts/
│   ├── fetch_foss_apks.sh          # Dynamic multi-arch FOSS APK fetcher
│   ├── install_foss_apps.sh        # Sideloading engine & IME configurator
│   ├── debloat.sh                  # Surgical package disabling & AppOps lockdown
│   ├── undo.sh                     # 1-Click master factory restoration script
│   ├── dump_partitions.sh          # Boot/recovery partition extractor
│   └── launch_scrcpy.sh            # Hardware-accelerated Vulkan Scrcpy launcher
└── docs/
    ├── EXPLOIT_ARCHITECTURE.md     # In-depth reverse engineering documentation
    ├── USB_EJECT_DNS_METHOD.md     # Guide for setting static DNS via USB ejection
    ├── DEBLOAT_AND_SAFETY_REFERENCE.md # Package audit and safety classification
    └── TROUBLESHOOTING.md          # Diagnostic runbook for common failure modes
```

---

## 🔄 Emergency Rollback & Restoration

If you ever need to restore the STB to its factory state (e.g. for warranty claims or troubleshooting):
```bash
./jiostb restore 192.168.29.170
```
This re-enables all 54 stock carrier packages, restores the Jio Home launcher as default, resets UI density to 320 DPI, and restores default window transition animations.

---

## 📜 Documentation Index
- [Exploit Architecture & Cryptographic Analysis](docs/EXPLOIT_ARCHITECTURE.md)
- [Zero-WAN USB Eject DNS Setup](docs/USB_EJECT_DNS_METHOD.md)
- [Debloat Safety Matrix & Package Audit](docs/DEBLOAT_AND_SAFETY_REFERENCE.md)
- [Troubleshooting & Diagnostics Guide](docs/TROUBLESHOOTING.md)

---

## ⚖️ License
Released under the [MIT License](LICENSE). Built for educational research and device ownership autonomy.
