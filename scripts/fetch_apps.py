#!/usr/bin/env python3
"""
fetch_apps.py — Universal, Manifest-Driven FOSS APK Fetcher

Downloads target-architecture APKs dynamically from F-Droid, GitHub Releases,
GitLab Generic Packages, and direct sources based on config/apps.json.
No hardcoded version tags or binary URLs.
"""

import os
import sys
import json
import re
import argparse
import subprocess
import urllib.request
import urllib.error
from pathlib import Path

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"


def http_get(url: str, headers: dict = None) -> tuple[int, bytes, dict]:
    """Perform HTTP GET request with standard headers."""
    req_headers = {"User-Agent": USER_AGENT}
    if headers:
        req_headers.update(headers)
    req = urllib.request.Request(url, headers=req_headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read(), dict(resp.headers)
    except urllib.error.HTTPError as e:
        return e.code, b"", {}
    except Exception as e:
        print(f"    [!] Network error requesting {url}: {e}", file=sys.stderr)
        return 0, b"", {}


def download_file(url: str, dest_path: Path, force: bool = False) -> bool:
    """Download a file with streaming progress and validation."""
    if dest_path.exists() and not force and dest_path.stat().st_size > 1024:
        size_mb = dest_path.stat().st_size / (1024 * 1024)
        print(f"  [✓] Cached: {dest_path.name} ({size_mb:.1f} MB)")
        return True

    dest_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = dest_path.with_suffix(".tmp")

    print(f"  [+] Fetching {dest_path.name} from {url} ...")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            total_size = int(resp.headers.get("Content-Length", 0))
            downloaded = 0
            block_size = 65536

            with open(temp_path, "wb") as f:
                while True:
                    chunk = resp.read(block_size)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total_size > 0:
                        percent = (downloaded / total_size) * 100
                        print(f"\r      Progress: {downloaded / (1024*1024):.1f}/{total_size / (1024*1024):.1f} MB ({percent:.1f}%)", end="", flush=True)
                    else:
                        print(f"\r      Downloaded: {downloaded / (1024*1024):.1f} MB", end="", flush=True)

            print()
            if temp_path.stat().st_size == 0:
                print(f"    [!] Error: Downloaded file is empty", file=sys.stderr)
                if temp_path.exists():
                    temp_path.unlink()
                return False

            temp_path.replace(dest_path)
            size_mb = dest_path.stat().st_size / (1024 * 1024)
            print(f"  [✓] Successfully downloaded {dest_path.name} ({size_mb:.1f} MB)")
            return True

    except Exception as e:
        print(f"\n    [!] Failed to download from {url}: {e}", file=sys.stderr)
        if temp_path.exists():
            temp_path.unlink()
        return False


class FDroidDriver:
    """Driver to resolve latest APK from F-Droid repository."""

    @staticmethod
    def resolve_url(app_def: dict, target_abi: str) -> str:
        pkg = app_def.get("package_id")
        if not pkg and "url" in app_def:
            m = re.search(r"packages/([^/]+)", app_def["url"])
            if m:
                pkg = m.group(1)

        if not pkg:
            raise ValueError(f"F-Droid driver requires 'package_id' or 'url' in app definition: {app_def}")

        page_url = f"https://f-droid.org/en/packages/{pkg}/"
        status, content, _ = http_get(page_url)
        if status == 200:
            html = content.decode("utf-8", errors="ignore")
            # Parse version blocks
            blocks = re.findall(r'<li class="package-version"[\s\S]*?</li>', html)
            for block in blocks:
                # Check architecture nativecode
                native_codes = re.findall(r'<code class="package-nativecode">([^<]+)</code>', block)
                apk_match = re.search(r'href=[\'"]([^\'"]+\.apk)[\'"]', block)
                if apk_match:
                    apk_url = apk_match.group(1)
                    # If target ABI is in native codes, or if no native code (universal/Java)
                    if not native_codes or target_abi in native_codes or "universal" in target_abi:
                        return apk_url

            # Fallback to any APK on the page
            apks = re.findall(r'href=[\'"](https://f-droid\.org/repo/[^\'"]+\.apk)[\'"]', html)
            if apks:
                return apks[0]

        # API fallback
        api_url = f"https://f-droid.org/api/v1/packages/{pkg}"
        status, content, _ = http_get(api_url)
        if status == 200:
            data = json.loads(content.decode("utf-8"))
            version_code = data.get("suggestedVersionCode")
            if version_code:
                return f"https://f-droid.org/repo/{pkg}_{version_code}.apk"

        raise RuntimeError(f"Could not resolve F-Droid release for package: {pkg}")


class GitHubDriver:
    """Driver to resolve latest release from GitHub API."""

    @staticmethod
    def resolve_url(app_def: dict, target_abi: str) -> str:
        repo = app_def.get("repo")
        if not repo:
            raise ValueError(f"GitHub driver requires 'repo' (owner/repo): {app_def}")

        api_url = f"https://api.github.com/repos/{repo}/releases/latest"
        status, content, _ = http_get(api_url)
        if status != 200:
            raise RuntimeError(f"GitHub API error ({status}) fetching latest release for {repo}")

        data = json.loads(content.decode("utf-8"))
        assets = data.get("assets", [])
        if not assets:
            raise RuntimeError(f"No assets found in latest release of {repo}")

        asset_filter = app_def.get("asset_filter")
        matched_assets = []

        for asset in assets:
            name = asset.get("name", "")
            url = asset.get("browser_download_url", "")
            if not name.endswith(".apk"):
                continue

            if asset_filter and not re.search(asset_filter, name, re.IGNORECASE):
                continue

            matched_assets.append((name, url))

        if not matched_assets:
            # Fall back to any APK
            matched_assets = [(a["name"], a["browser_download_url"]) for a in assets if a.get("name", "").endswith(".apk")]

        if not matched_assets:
            raise RuntimeError(f"No suitable APK assets found for {repo}")

        # If ABI-specific filtering is needed
        # Priority: target_abi -> universal/all -> first APK
        for name, url in matched_assets:
            if target_abi in name.lower():
                return url

        # If targeting 32-bit arm, reject arm64-v8a or x86
        if target_abi in ("armeabi-v7a", "arm"):
            for name, url in matched_assets:
                lname = name.lower()
                if "arm64" not in lname and "x86" not in lname:
                    return url

        return matched_assets[0][1]


class GitLabDriver:
    """Driver to resolve latest package file from GitLab Packages API."""

    @staticmethod
    def resolve_url(app_def: dict, target_abi: str) -> str:
        project_id = app_def.get("project_id")
        pkg_name = app_def.get("package_name")
        if not project_id:
            raise ValueError(f"GitLab driver requires 'project_id': {app_def}")

        api_url = f"https://gitlab.com/api/v4/projects/{project_id}/packages?order_by=created_at&sort=desc"
        status, content, _ = http_get(api_url)
        if status != 200:
            raise RuntimeError(f"GitLab API error ({status}) fetching packages for project {project_id}")

        packages = json.loads(content.decode("utf-8"))
        if not packages:
            raise RuntimeError(f"No packages found for GitLab project {project_id}")

        latest_pkg = packages[0]
        pkg_id = latest_pkg.get("id")
        pkg_version = latest_pkg.get("version")
        actual_name = latest_pkg.get("name", pkg_name)

        # Get package files
        files_url = f"https://gitlab.com/api/v4/projects/{project_id}/packages/{pkg_id}/package_files"
        f_status, f_content, _ = http_get(files_url)
        if f_status == 200:
            files = json.loads(f_content.decode("utf-8"))
            for f in files:
                fname = f.get("file_name", "")
                if fname.endswith(".apk"):
                    return f"https://gitlab.com/api/v4/projects/{project_id}/packages/generic/{actual_name}/{pkg_version}/{fname}"

        # Standard generic URL fallback
        return f"https://gitlab.com/api/v4/projects/{project_id}/packages/generic/{actual_name}/{pkg_version}/{actual_name}-{pkg_version}.apk"


class DirectDriver:
    """Driver for direct static URLs."""

    @staticmethod
    def resolve_url(app_def: dict, target_abi: str) -> str:
        url = app_def.get("url")
        if not url:
            raise ValueError(f"Direct driver requires 'url': {app_def}")
        return url


DRIVERS = {
    "fdroid": FDroidDriver,
    "github": GitHubDriver,
    "gitlab": GitLabDriver,
    "direct": DirectDriver,
}


def detect_device_abi(device: str = None) -> str:
    """Query connected ADB device for ro.product.cpu.abi."""
    cmd = ["adb"]
    if device:
        cmd.extend(["-s", device])
    cmd.extend(["shell", "getprop", "ro.product.cpu.abi"])
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
        if res.returncode == 0 and res.stdout.strip():
            abi = res.stdout.strip()
            print(f"[+] Detected active device ABI: {abi}")
            return abi
    except Exception:
        pass
    return "armeabi-v7a"


def main():
    parser = argparse.ArgumentParser(description="Universal FOSS APK Fetcher")
    parser.add_argument("--manifest", default="config/apps.json", help="Path to apps.json manifest")
    parser.add_argument("--output-dir", default="downloads", help="Destination downloads directory")
    parser.add_argument("--app", default=None, help="Filter to specific app ID (e.g. smarttube, projectivy)")
    parser.add_argument("--abi", default=None, help="Target CPU architecture (default: auto or armeabi-v7a)")
    parser.add_argument("--device", default=None, help="Specific ADB device IP/serial to auto-detect ABI from")
    parser.add_argument("--force", action="store_true", help="Force re-download of existing APKs")

    args = parser.parse_args()

    # Determine script root
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent
    manifest_path = (repo_root / args.manifest).resolve()
    output_dir = (repo_root / args.output_dir).resolve()

    if not manifest_path.exists():
        print(f"[!] Manifest not found: {manifest_path}", file=sys.stderr)
        sys.exit(1)

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest_data = json.load(f)

    apps = manifest_data.get("apps", [])
    if not apps:
        print("[!] No applications defined in manifest", file=sys.stderr)
        sys.exit(1)

    target_abi = args.abi or detect_device_abi(args.device)

    print("=================================================================")
    print(" 📥 UNIVERSAL MANIFEST-DRIVEN FOSS APK FETCHER")
    print(f" Manifest:    {manifest_path.name}")
    print(f" Target ABI:  {target_abi}")
    print(f" Destination: {output_dir}")
    print("=================================================================")

    output_dir.mkdir(parents=True, exist_ok=True)
    success_count = 0
    total_count = 0

    for app in apps:
        app_id = app.get("id")
        if args.app and app_id != args.app:
            continue

        total_count += 1
        name = app.get("name", app_id)
        source = app.get("source", "").lower()
        out_filename = app.get("output_filename", f"{app_id}.apk")
        dest_file = output_dir / out_filename
        abi = app.get("target_abi", target_abi)

        print(f"\n[{total_count}] Processing {name} ({app_id}) via [{source}]...")

        driver = DRIVERS.get(source)
        if not driver:
            print(f"  [!] Unknown source driver '{source}' for app {app_id}", file=sys.stderr)
            continue

        try:
            download_url = driver.resolve_url(app, abi)
            if not download_url:
                print(f"  [!] Failed to resolve download URL for {name}", file=sys.stderr)
                continue

            if download_file(download_url, dest_file, force=args.force):
                success_count += 1

        except Exception as e:
            print(f"  [!] Error processing {name}: {e}", file=sys.stderr)

    print("\n=================================================================")
    print(f" 🎉 COMPLETED: {success_count}/{total_count} applications ready!")
    if output_dir.exists():
        size_cmd = subprocess.run(["du", "-sh", str(output_dir)], capture_output=True, text=True)
        size_str = size_cmd.stdout.split()[0] if size_cmd.stdout else "unknown"
        print(f" Total Download Storage: {size_str}")
    print("=================================================================")

    if success_count == 0 and total_count > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
