# Accessing Hidden Android Settings (USB Eject Method)

> [!NOTE]
> This method allows you to access genuine Android TV Settings on a fully locked Jio STB directly from the TV UI **without** touching your home router, without unplugging delicate fiber cables, and without needing pre-existing ADB access.

---

## 1. Background
Jio OS replaces the standard Android TV Settings app with a carrier-branded portal (`com.rjil.jiostbsetting`) that strips Developer Options, USB Debugging toggles, and IP configuration.

However, the stock Android TV Settings package (`com.android.tv.settings`) remains present on the system partition. When a USB flash drive is unmounted from Jio's "My Music" or "JioMedia" app, Android displays a storage notification that links directly into the system's underlying storage management intent, unlocking the full stock Settings app.

---

## 2. Step-by-Step Procedure

### Prerequisites:
* Any standard USB flash drive (any format: FAT32, NTFS, exFAT).
* Your Jio Bluetooth remote control.
* Your laptop/PC running the `JioSTB-sideload` environment.

---

### Step 1: Open the Storage Notification
1. Insert the USB drive into either USB port on the Jio STB.
2. On the TV home screen, open the **My Music** (or **JioMedia / My Files**) app.
3. In the left-hand navigation menu, select **Settings**.
4. Highlight your connected USB drive and select **Eject USB**.
5. When the ejection confirmation appears, select **Internal Shared Storage**.

---

### Step 2: Navigate to Stock Android Settings
1. Inside the Internal Storage menu, scroll down and select **Apps**.
2. Scroll to the bottom of the app list and click **See all apps**.
3. Scroll down until you see the system **Settings** app (with the gear icon).
4. Click **Settings** -> Select **Open**.
5. You are now inside the genuine stock **Android TV Settings**!

---

### Step 3: Configure Static DNS Redirection
1. In Stock Settings, navigate to **Network & Internet**.
2. Select your currently connected network:
   * **If using Ethernet:** Click **Ethernet** -> **IP settings**.
   * **If using Wi-Fi:** Click your connected Wi-Fi network -> **IP settings**.
3. Switch from **DHCP** to **Static**.
4. Confirm your device IP, Gateway, and Subnet Prefix (24).
5. When prompted for **DNS 1**:
   * Enter your PC's IP address (e.g., `192.168.42.1` for Direct Ethernet, or your laptop's local LAN IP `192.168.29.X` if running AdGuard/Technitium).
6. Set **DNS 2** to `0.0.0.0` (or leave blank).
7. Save the configuration.

---

## 3. Triggering Local TR-069 Check-in
1. Once Static DNS points to your PC, ensure your local ACS server is running:
   ```bash
   ./jiostb acs start
   ```
2. Cold power-cycle the STB (unplug wall adapter from wall outlet, wait 5 seconds, reconnect).
3. The STB will boot, resolve `acs.oss.jio.com` via your PC, and complete the TR-069 handshake, opening ADB port `5555`.
