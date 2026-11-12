# Jio STB Package Debloat & Safety Architecture

## 1. Package Disabling vs Uninstallation

On Android TV carrier ROMs, system apps reside on read-only system partitions (`/system/priv-app/`, `/product/app/`, `/vendor/app/`):

* **Standard Android Settings Uninstall:** Only uninstalls user-space updates from `/data/app/`. On reboot, Android PackageManager re-indexes the base APK from `/system/` and reactivates it.
* **`pm uninstall -k --user 0 <pkg>`:** Uninstalls the package for the primary user. Can occasionally cause system package dependency failures on OTA updates.
* **`pm disable-user --user 0 <pkg>` (RECOMMENDED & ENFORCED):** Freezes the application components for User 0. The app cannot launch, cannot register broadcast receivers, and cannot execute background services. It is 100% reversible anytime via `pm enable <pkg>`.

---

## 2. Low-Level Execution Restrictions (AppOps)

Disabling a package via PackageManager prevents it from starting, but system daemons and alarms can still attempt to invoke wake locks. To ensure zero CPU wakeups:

```bash
# Cut off background execution
cmd appops set <pkg> RUN_IN_BACKGROUND ignore

# Cut off wake locks (prevents CPU keep-awake)
cmd appops set <pkg> WAKE_LOCK ignore
```

---

## 3. Package Classification Matrix

### Category A: Primary Debloat Targets (54 Packages)
* **TR-069 & Remote Takeover:** `com.jio.tr069client`, `insight.tr069.client`, `com.rjil.jio.stb.commandreceiver`, `com.communitake.remotecontrolservice`, `com.teamviewer.quicksupport.addon.jio_stb`.
* **Ad Engines:** `com.jio.stbadservice`, `com.jio.stbwidget`, `com.jio.screensaver`, `com.jio.bioscopecontentservice`.
* **Firmware OTA Updaters:** `com.iwedia.httpupdate`, `com.iwedia.updateservice`, `com.iwedia.pvodupdateservice`, `com.iwedia.updatercuotaservice`, `com.jio.httpupdate`, `com.jio.usbupdate`.
* **Voice Assistant / Chatbots:** `com.android.app.jio.voiceassist`, `com.jio.stb.bot`, `com.jio.controlcentre`.
* **User Bloatware:** `com.jiostb.jiogames`, `com.jio.store`, `com.jio.media.jionewsstb`, `com.jio.media.jiobeats`, `com.jio.mymusic.app`, `com.jio.jiocloudpc`, `com.jio.jiocall`, `com.jio.jiopay`, `com.jio.web`, `com.jio.yt`.
* **Useless TV Services:** `com.android.bips`, `com.android.printspooler`, `com.android.bluetoothmidiservice`, `com.android.camera2`, `com.svox.pico`, `com.iwedia.resetservice`.

---

### Category B: Critical Core Stack (NEVER DISABLE)
* **Audio / Video / HDMI Pipeline:** `com.droidlogic`, `com.iwedia.tvinput`, `com.iwedia.displayservice`.
* **Remote Control:** `com.iwedia.bluetoothconnectionservice`, `com.jio.remote.btserver`.
* **Security & DRM:** `com.netflix.partnertoken`, `com.android.keychain`, `com.android.permissioncontroller`.
* **System UI & Settings:** `com.android.systemui`, `com.android.tv.settings`, `com.android.packageinstaller`.
* **Safety Fallback:** `com.iwedia.ui.rjio.launcher.reliance` (kept on disk to prevent black screen on launcher crash).

---

### Category C: Jio Paid Streaming (User Subscriptions)
* `com.jio.media.jiotvplus` (Live TV Channels & Catch-up)
* `com.jio.media.livetv` (CATV tuner core)
* `com.media.jio.sso.stb` (Jio subscription token validator)
