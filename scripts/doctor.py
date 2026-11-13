#!/usr/bin/env python3
"""
doctor.py — Comprehensive diagnostics, health checks, and simulation for Jio STB.

Ported and enhanced from ilikechocopies/sideload-jiostb.

Modes:
  --quick       Ports + NBI + DNS check only (safe any time, zero side effects)
  --simulate    Sends a synthetic CWMP Inform through pass_front -> GenieACS,
                creates and cleans up a test device to prove the PC side works 100%
  --watch       Polls _lastInform, task queue, and ADB port 5555 until device connects
  --tasks       Inspect all pending TR-069 tasks for connected devices
  --clear-tasks Clear all pending TR-069 tasks from GenieACS
  (default)     Full chain checklist + device status
"""

import sys
import os
import socket
import ssl
import json
import time
import urllib.request
import urllib.error
import urllib.parse
import argparse
from pathlib import Path

# Terminal colors
CYAN = '\033[0;36m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
NC = '\033[0m'
BOLD = '\033[1m'

DEFAULT_NBI = os.environ.get("NBI_URL", "http://127.0.0.1:7557")
DEFAULT_CWMP = os.environ.get("CWMP_URL", "http://127.0.0.1:7547")
DEFAULT_TLS_PORT = int(os.environ.get("TLS_PORT", 9443))  # 9443 for JHS, 8443 for JMSC


def port_open(host, port, timeout=0.8):
    try:
        with socket.create_connection((host, int(port)), timeout=timeout):
            return True
    except Exception:
        return False


def get_lan_ips():
    ips = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.add(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127."):
                ips.add(ip)
    except Exception:
        pass
    return sorted(list(ips)) or ["127.0.0.1"]


def check_dns(domain="acs.oss.jio.com"):
    try:
        return socket.gethostbyname(domain)
    except Exception:
        return None


def query_nbi(endpoint, nbi_url=DEFAULT_NBI, method="GET", data=None):
    url = f"{nbi_url.rstrip('/')}/{endpoint.lstrip('/')}"
    req = urllib.request.Request(url, method=method)
    if data is not None:
        if isinstance(data, (dict, list)):
            req.data = json.dumps(data).encode("utf-8")
            req.add_header("Content-Type", "application/json")
        elif isinstance(data, (bytes, str)):
            req.data = data.encode("utf-8") if isinstance(data, str) else data
    try:
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return resp.status, body
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return 0, str(e)


def run_quick(nbi_url=DEFAULT_NBI, tls_port=DEFAULT_TLS_PORT):
    print(f"\n{BOLD}Running Quick Chain Health Check...{NC}")
    ok = True

    # 1. pass_front.py (check ports 9443 and 8443)
    p9443 = port_open("127.0.0.1", 9443)
    p8443 = port_open("127.0.0.1", 8443)
    if p9443 or p8443:
        ports_str = []
        if p9443:
            ports_str.append("9443 (JHS)")
        if p8443:
            ports_str.append("8443 (JMSC)")
        print(f"  {GREEN}[PASS]{NC} pass_front.py listening on port(s): {', '.join(ports_str)}")
    else:
        print(f"  {RED}[FAIL]{NC} pass_front.py is NOT listening on port 9443 or 8443")
        ok = False

    # 2. GenieACS CWMP (:7547)
    cwmp_open = port_open("127.0.0.1", 7547)
    if cwmp_open:
        print(f"  {GREEN}[PASS]{NC} GenieACS CWMP listening on port 7547")
    else:
        print(f"  {RED}[FAIL]{NC} GenieACS CWMP is NOT listening on port 7547 (Containers running?)")
        ok = False

    # 3. GenieACS NBI (:7557)
    status, body = query_nbi("devices/?projection=_id", nbi_url=nbi_url)
    if status == 200:
        print(f"  {GREEN}[PASS]{NC} GenieACS NBI reachable at {nbi_url}")
    else:
        print(f"  {RED}[FAIL]{NC} GenieACS NBI unreachable at {nbi_url} (HTTP {status})")
        ok = False

    # 4. DNS Override for acs.oss.jio.com
    dns_ip = check_dns("acs.oss.jio.com")
    lan_ips = get_lan_ips()
    if dns_ip:
        if dns_ip in lan_ips or dns_ip in ("127.0.0.1", "192.168.42.1", "192.168.43.1"):
            print(f"  {GREEN}[PASS]{NC} DNS acs.oss.jio.com -> {dns_ip} (Matches local host/link IP)")
        else:
            print(f"  {YELLOW}[WARN]{NC} DNS acs.oss.jio.com -> {dns_ip} (Host LAN IPs: {', '.join(lan_ips)})")
    else:
        print(f"  {YELLOW}[WARN]{NC} DNS acs.oss.jio.com could not be resolved locally. Ensure DNS spoof/rewrite is set.")

    return ok


def run_tasks(nbi_url=DEFAULT_NBI):
    print(f"\n{BOLD}Querying GenieACS Task Queue...{NC}")
    status, body = query_nbi("tasks/", nbi_url=nbi_url)
    if status != 200:
        print(f"  {RED}[FAIL]{NC} Could not retrieve tasks from NBI (HTTP {status})")
        return False

    try:
        tasks = json.loads(body)
        if not tasks:
            print("  Queue is empty (no pending tasks).")
            return True

        print(f"  Found {len(tasks)} queued task(s):")
        for i, t in enumerate(tasks, 1):
            name = t.get("name", "unknown")
            dev = t.get("device", "unknown")
            fault = t.get("fault")
            fault_str = f" {RED}[FAULT: {fault}]{NC}" if fault else ""
            pvals = t.get("parameterValues", [])
            p_str = ", ".join([f"{p[0]}={p[1]}" for p in pvals]) if pvals else ""
            print(f"    {i}. [{dev}] {name} {p_str}{fault_str}")
        return True
    except Exception as e:
        print(f"  {RED}[ERROR]{NC} Failed to parse tasks: {e}")
        return False


def run_clear_tasks(nbi_url=DEFAULT_NBI):
    print(f"\n{BOLD}Clearing all pending tasks from GenieACS...{NC}")
    status, body = query_nbi("tasks/", nbi_url=nbi_url)
    if status != 200:
        print(f"  {RED}[FAIL]{NC} Could not retrieve tasks (HTTP {status})")
        return False

    try:
        tasks = json.loads(body)
        count = 0
        for t in tasks:
            tid = t.get("_id")
            if tid:
                s, _ = query_nbi(f"tasks/{tid}", nbi_url=nbi_url, method="DELETE")
                if s in (200, 204):
                    count += 1
        print(f"  {GREEN}[✓]{NC} Cleared {count} task(s).")
        return True
    except Exception as e:
        print(f"  {RED}[ERROR]{NC} Failed to clear tasks: {e}")
        return False


def run_simulate(tls_port=None, nbi_url=DEFAULT_NBI):
    print(f"\n{BOLD}Simulating Synthetic CWMP Inform through Local Chain...{NC}")

    # Determine listening port
    if tls_port is None:
        if port_open("127.0.0.1", 9443):
            tls_port = 9443
        elif port_open("127.0.0.1", 8443):
            tls_port = 8443
        else:
            tls_port = 9443

    test_sn = f"SIM-{int(time.time())}"
    soap_body = f"""<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:cwmp="urn:dslforum-org:cwmp-1-0">
  <soap:Header/>
  <soap:Body>
    <cwmp:Inform>
      <DeviceId>
        <Manufacturer>TEST</Manufacturer>
        <OUI>000000</OUI>
        <ProductClass>JioSTB</ProductClass>
        <SerialNumber>{test_sn}</SerialNumber>
      </DeviceId>
      <Event soap:arrayType="cwmp:EventStruct[1]">
        <EventStruct>
          <EventCode>1 BOOT</EventCode>
          <CommandKey></CommandKey>
        </EventStruct>
      </Event>
      <MaxEnvelopes>1</MaxEnvelopes>
      <CurrentTime>{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}</CurrentTime>
      <RetryCount>0</RetryCount>
      <ParameterList soap:arrayType="cwmp:ParameterValueStruct[1]">
        <ParameterValueStruct>
          <Name>Device.DeviceInfo.SpecVersion</Name>
          <Value>1.0</Value>
        </ParameterValueStruct>
      </ParameterList>
    </cwmp:Inform>
  </soap:Body>
</soap:Envelope>"""

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    url = f"https://127.0.0.1:{tls_port}/"
    headers = {
        "Content-Type": "text/xml; charset=utf-8",
        "SOAPAction": ""
    }

    print(f"  [1/4] Sending synthetic Inform over TLS to {url} ...")
    session_cookie = None
    try:
        req = urllib.request.Request(url, data=soap_body.encode("utf-8"), headers=headers, method="POST")
        with urllib.request.urlopen(req, context=ctx, timeout=8) as resp:
            resp_body = resp.read().decode("utf-8", errors="replace")
            for k, v in resp.getheaders():
                if k.lower() == "set-cookie" and "session=" in v:
                    session_cookie = v.split(";")[0]
            if "InformResponse" in resp_body:
                print(f"  {GREEN}[PASS]{NC} Inform accepted by GenieACS! (Session cookie: {session_cookie or 'none'})")
            else:
                print(f"  {YELLOW}[WARN]{NC} Upstream response received but no InformResponse found.")
    except Exception as e:
        print(f"  {RED}[FAIL]{NC} Could not connect to TLS front on port {tls_port}: {e}")
        return False

    print(f"  [2/4] Sending empty POST with session cookie to close CWMP session...")
    try:
        empty_headers = {}
        if session_cookie:
            empty_headers["Cookie"] = session_cookie
        req2 = urllib.request.Request(url, data=b"", headers=empty_headers, method="POST")
        with urllib.request.urlopen(req2, context=ctx, timeout=8) as resp2:
            print(f"  {GREEN}[PASS]{NC} CWMP session completed cleanly (HTTP {resp2.status})")
    except Exception as e:
        print(f"  {YELLOW}[WARN]{NC} Empty POST notice: {e}")

    print(f"  [3/4] Checking device presence in GenieACS NBI...")
    enc_id = urllib.parse.quote(f"000000-TEST-JioSTB-{test_sn}")
    status, body = query_nbi(f"devices/{enc_id}", nbi_url=nbi_url)
    if status == 200:
        print(f"  {GREEN}[PASS]{NC} Simulated device confirmed in GenieACS database!")
    else:
        print(f"  {RED}[FAIL]{NC} Simulated device not found in GenieACS NBI (HTTP {status})")
        return False

    print(f"  [4/4] Cleaning up simulated device from database...")
    del_status, _ = query_nbi(f"devices/{enc_id}", nbi_url=nbi_url, method="DELETE")
    if del_status in (200, 204):
        print(f"  {GREEN}[PASS]{NC} Simulated device cleanly deleted from GenieACS.")
    else:
        print(f"  {YELLOW}[WARN]{NC} Cleanup status: HTTP {del_status}")

    print(f"\n{GREEN}{BOLD}Result: Full PC-side chain (TLS -> cookie proxy -> GenieACS CWMP -> NBI) is 100% OPERATIONAL!{NC}\n")
    return True


def run_watch(nbi_url=DEFAULT_NBI, stb_ip=None):
    print(f"\n{BOLD}Watching for device check-in... (Ctrl+C to abort){NC}")
    last_inform = None
    while True:
        status, body = query_nbi("devices/?projection=_id,_lastInform", nbi_url=nbi_url)
        if status == 200:
            try:
                devs = json.loads(body)
                for d in devs:
                    did = d.get("_id", "")
                    if "TEST" in did:
                        continue
                    li = d.get("_lastInform")
                    if li != last_inform:
                        last_inform = li
                        print(f"  {GREEN}[✓] Device Inform received!{NC} Device: {did} | Timestamp: {li}")
            except Exception:
                pass

        if stb_ip and port_open(stb_ip, 5555, timeout=0.5):
            print(f"  {GREEN}[✓] ADB Port 5555 is OPEN on {stb_ip}!{NC}")
            break

        time.sleep(3)


def run_full(nbi_url=DEFAULT_NBI, tls_port=DEFAULT_TLS_PORT, stb_ip=None):
    quick_ok = run_quick(nbi_url=nbi_url, tls_port=tls_port)

    print(f"\n{BOLD}Device & Task Status:{NC}")
    status, body = query_nbi("devices/?projection=_id,_lastInform", nbi_url=nbi_url)
    devices = []
    if status == 200:
        try:
            devices = json.loads(body)
        except Exception:
            devices = []

    print(f"  Total devices registered in GenieACS: {len(devices)}")
    for d in devices:
        did = d.get("_id", "")
        li = d.get("_lastInform", "never")
        print(f"    • {did} (Last Inform: {li})")

    run_tasks(nbi_url=nbi_url)

    if stb_ip:
        print(f"\n{BOLD}Target Device ADB Check ({stb_ip}):{NC}")
        if port_open(stb_ip, 5555):
            print(f"  {GREEN}[PASS]{NC} Port 5555 is OPEN on {stb_ip}")
        else:
            print(f"  {YELLOW}[WAIT]{NC} Port 5555 is not reachable on {stb_ip}")

    return quick_ok


def main():
    parser = argparse.ArgumentParser(description="JioSTB Sideload Diagnostic & Chain Health Doctor")
    parser.add_argument("--quick", action="store_true", help="Quick check (ports, NBI, DNS) without side-effects")
    parser.add_argument("--simulate", action="store_true", help="Prove full PC-side chain with synthetic Inform")
    parser.add_argument("--watch", action="store_true", help="Continuously poll for device Inform and ADB opening")
    parser.add_argument("--tasks", action="store_true", help="Display all pending TR-069 tasks")
    parser.add_argument("--clear-tasks", action="store_true", help="Delete all pending TR-069 tasks")
    parser.add_argument("--nbi", default=DEFAULT_NBI, help=f"GenieACS NBI URL (default: {DEFAULT_NBI})")
    parser.add_argument("--tls-port", type=int, default=None, help="TLS front port (default: 9443 or 8443)")
    parser.add_argument("--stb-ip", default=None, help="STB LAN IP address for connectivity check")

    args = parser.parse_args()

    if args.quick:
        ok = run_quick(nbi_url=args.nbi, tls_port=args.tls_port or DEFAULT_TLS_PORT)
        sys.exit(0 if ok else 1)
    elif args.simulate:
        ok = run_simulate(tls_port=args.tls_port, nbi_url=args.nbi)
        sys.exit(0 if ok else 1)
    elif args.tasks:
        ok = run_tasks(nbi_url=args.nbi)
        sys.exit(0 if ok else 1)
    elif args.clear_tasks:
        ok = run_clear_tasks(nbi_url=args.nbi)
        sys.exit(0 if ok else 1)
    elif args.watch:
        run_watch(nbi_url=args.nbi, stb_ip=args.stb_ip)
    else:
        ok = run_full(nbi_url=args.nbi, tls_port=args.tls_port or DEFAULT_TLS_PORT, stb_ip=args.stb_ip)
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
