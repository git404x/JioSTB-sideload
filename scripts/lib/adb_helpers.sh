#!/usr/bin/env bash
# ==============================================================================
# adb_helpers.sh — Shared ADB package-removal and permission helpers
# Ported from ilikechocopies/sideload-jiostb
# ==============================================================================

pkg_installed_for_user() {
    local target="$1"
    local pkg="$2"
    adb -s "$target" shell "pm list packages $pkg" 2>/dev/null | tr -d '\r' | grep -Fx "package:$pkg" >/dev/null 2>&1
}

pkg_present_on_device() {
    local target="$1"
    local pkg="$2"
    adb -s "$target" shell "pm list packages -u $pkg" 2>/dev/null | tr -d '\r' | grep -Fx "package:$pkg" >/dev/null 2>&1
}

# Completely delete a package; fall back to disabling & restricting if protected
remove_or_disable_pkg() {
    local target="$1"
    local pkg="$2"
    local verbose="${3:-false}"

    if ! pkg_installed_for_user "$target" "$pkg" && ! pkg_present_on_device "$target" "$pkg"; then
        [ "$verbose" = true ] && echo "  [-] $pkg — not present on device (skipped)"
        return 0
    fi

    adb -s "$target" shell "am force-stop $pkg" >/dev/null 2>&1 || true
    adb -s "$target" shell "pm clear $pkg" >/dev/null 2>&1 || true

    # Attempt standard uninstall
    adb -s "$target" shell "pm uninstall $pkg" >/dev/null 2>&1 || true

    # If still installed for user 0 (system APK), attempt uninstall for user 0
    if pkg_installed_for_user "$target" "$pkg"; then
        adb -s "$target" shell "pm uninstall --user 0 $pkg" >/dev/null 2>&1 || true
    fi

    if ! pkg_installed_for_user "$target" "$pkg"; then
        echo "  [✓] $pkg — uninstalled for user 0"
        return 0
    fi

    # Protected system app — disable and strip background execution
    adb -s "$target" shell "cmd appops set $pkg RUN_IN_BACKGROUND ignore" >/dev/null 2>&1 || true
    adb -s "$target" shell "cmd appops set $pkg RUN_ANY_IN_BACKGROUND ignore" >/dev/null 2>&1 || true
    adb -s "$target" shell "cmd appops set $pkg WAKE_LOCK ignore" >/dev/null 2>&1 || true

    local dis_out
    dis_out=$(adb -s "$target" shell "pm disable-user --user 0 $pkg" 2>&1 | tr -d '\r' || true)
    if echo "$dis_out" | grep -qiE "disabled|new state" || \
       adb -s "$target" shell "pm list packages -d $pkg" 2>/dev/null | tr -d '\r' | grep -Fx "package:$pkg" >/dev/null 2>&1; then
        echo "  [✓] $pkg — disabled (protected system package)"
    else
        adb -s "$target" shell "pm suspend --user 0 $pkg" >/dev/null 2>&1 || true
        adb -s "$target" shell "pm hide $pkg" >/dev/null 2>&1 || true
        echo "  [!] $pkg — suspended & hidden"
    fi
}

# Grant all runtime permissions, AppOps, and battery exemptions to Shevery / Shizuku
grant_shevery_permissions() {
    local target="$1"
    local pkg="$2"

    for perm in \
        android.permission.WRITE_SECURE_SETTINGS \
        android.permission.PACKAGE_USAGE_STATS \
        android.permission.DUMP \
        android.permission.POST_NOTIFICATIONS \
        android.permission.NEARBY_WIFI_DEVICES \
        android.permission.ACCESS_LOCAL_NETWORK \
        android.permission.ACCESS_FINE_LOCATION \
        android.permission.ACCESS_COARSE_LOCATION \
        android.permission.INTERACT_ACROSS_USERS_FULL
    do
        adb -s "$target" shell "pm grant $pkg $perm" >/dev/null 2>&1 || true
    done

    for op in \
        GET_USAGE_STATS \
        WRITE_SETTINGS \
        REQUEST_INSTALL_PACKAGES \
        SYSTEM_ALERT_WINDOW \
        ACCESS_RESTRICTED_SETTINGS \
        RUN_IN_BACKGROUND \
        RUN_ANY_IN_BACKGROUND \
        START_FOREGROUND \
        POST_NOTIFICATION \
        SYSTEM_EXEMPT_FROM_SUSPENSION \
        SYSTEM_EXEMPT_FROM_HIBERNATION
    do
        adb -s "$target" shell "cmd appops set $pkg $op allow" >/dev/null 2>&1 || true
    done

    adb -s "$target" shell "dumpsys deviceidle whitelist +$pkg" >/dev/null 2>&1 || true
    adb -s "$target" shell "cmd deviceidle whitelist +$pkg" >/dev/null 2>&1 || true
    adb -s "$target" shell "am set-standby-bucket $pkg active" >/dev/null 2>&1 || true
    echo "  [✓] $pkg — full permissions, AppOps, and battery whitelist granted"
}
