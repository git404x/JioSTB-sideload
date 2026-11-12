#!/usr/bin/env python3
"""
pass_front.py — TLS-terminating CWMP Reverse Proxy for Jio STB -> GenieACS

Architecture:
  Jio STB (CPE) --[HTTPS :8443/:9443]--> pass_front.py --[HTTP :7547]--> GenieACS CWMP

Key Functionality:
  1. TLS Termination:
     - JMSC/JMSB: Serves cert chain matching Reliance RILROOTCA pin.
     - JHS/JioOS 2.0: Serves cert chain anchored on Sectigo AAA via forged eMudhra intermediate.
  2. Network-Check Spoofing:
     - Intercepts '/common/v1/network/check' and returns AES-128-CBC encrypted 'FTTH' blob.
  3. Session-Cookie Affinity:
     - Jio STB uses separate TCP connections for Inform, empty-POST, and RPC response.
     - Routes requests sharing the same 'session' cookie to the identical upstream connection.
"""

import argparse
import base64
import datetime
import gzip
import http.client
import os
import re
import socket
import ssl
import sys
import threading

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
DEFAULT_CERT_DIR = os.path.join(REPO_ROOT, "certs")

# Production secret key for AES netcheck gate; FTTH = JioFiber STB
NETCHECK_KEY = b"6bm2I7pTdBaeABX0"
NETTYPE = "FTTH"
PRECOMPUTED_NETCHECK = "UzLgdFHvJkBfRQiHnNQit+55dub3o1PbxIhuNZ7oJc8="

try:
    from Crypto.Cipher import AES
    HAVE_CRYPTO = True
except ImportError:
    HAVE_CRYPTO = False

def forge_netcheck():
    if not HAVE_CRYPTO:
        return PRECOMPUTED_NETCHECK
    iv = os.urandom(16)
    data = NETTYPE.encode()
    pad = 16 - (len(data) % 16)
    data += bytes([pad]) * pad
    cipher = AES.new(NETCHECK_KEY, AES.MODE_CBC, iv)
    ct = cipher.encrypt(data)
    return base64.b64encode(iv + ct).decode()

def parse_args():
    parser = argparse.ArgumentParser(description="Jio STB TLS CWMP Front-End Proxy")
    parser.add_argument("--ports", type=str, default=os.environ.get("TLS_PORTS", "8443,9443"),
                        help="Comma-separated listen ports (default: 8443,9443)")
    parser.add_argument("--cert", type=str, default=None,
                        help="Path to fullchain PEM containing cert + intermediate + key")
    parser.add_argument("--model", choices=["jmsc", "jhs"], default=os.environ.get("STB_MODEL", "jhs"),
                        help="STB model family: jmsc (RILROOTCA) or jhs (eMudhra/Sectigo)")
    parser.add_argument("--genie-host", type=str, default=os.environ.get("GENIE_HOST", "127.0.0.1"),
                        help="GenieACS CWMP upstream host (default: 127.0.0.1)")
    parser.add_argument("--genie-port", type=int, default=int(os.environ.get("GENIE_PORT", 7547)),
                        help="GenieACS CWMP upstream port (default: 7547)")
    parser.add_argument("--log", type=str, default=os.environ.get("LOG_FILE", os.path.join(REPO_ROOT, "logs", "pass_front.log")),
                        help="Log file path")
    return parser.parse_args()

log_lock = threading.Lock()

def log(msg, log_path):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    entry = f"[{ts}] {msg}"
    print(entry)
    with log_lock:
        try:
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(entry + "\n")
        except Exception:
            pass

def extract_cookie(header_value):
    if not header_value:
        return None
    match = re.search(r'session=([0-9a-fA-F]+)', header_value)
    return match.group(1) if match else None

def decompress_body(raw_body, encoding):
    if encoding and "gzip" in encoding.lower():
        try:
            return gzip.decompress(raw_body)
        except Exception:
            return raw_body
    return raw_body

def read_http_request(rfile):
    first_line = rfile.readline()
    if not first_line:
        return None
    req_line = first_line.decode("latin1").rstrip("\r\n")
    headers = {}
    while True:
        line = rfile.readline()
        if not line or line in (b"\r\n", b"\n"):
            break
        key, _, val = line.decode("latin1").partition(":")
        headers[key.strip().lower()] = val.strip()

    body = b""
    if "content-length" in headers:
        length = int(headers["content-length"])
        body = rfile.read(length) if length > 0 else b""
    return req_line, headers, body

class CWMPProxy:
    def __init__(self, args):
        self.args = args
        self.ports = [int(p.strip()) for p in args.ports.split(",") if p.strip()]
        self.genie_target = (args.genie_host, args.genie_port)
        self.log_path = args.log
        self.sessions = {}
        self.session_lock = threading.Lock()

        # Resolve certificate
        if args.cert:
            self.cert_path = args.cert
        elif args.model == "jhs":
            self.cert_path = os.path.join(DEFAULT_CERT_DIR, "forged_chain.pem")
        else:
            self.cert_path = os.path.join(DEFAULT_CERT_DIR, "acs_chain.pem")

        if not os.path.isfile(self.cert_path):
            raise FileNotFoundError(f"TLS certificate chain not found: {self.cert_path}")

        # Setup SSL Context
        self.ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.ssl_ctx.load_cert_chain(self.cert_path)
        try:
            self.ssl_ctx.set_ciphers("DEFAULT:@SECLEVEL=0")
        except Exception:
            pass

    def handle_client(self, raw_sock, addr):
        cid = f"{addr[0]}:{addr[1]}"
        log(f"Incoming TCP connection from {cid}", self.log_path)

        try:
            ssl_sock = self.ssl_ctx.wrap_socket(raw_sock, server_side=True)
        except Exception as err:
            log(f"TLS Handshake failed from {cid}: {err}", self.log_path)
            try:
                raw_sock.close()
            except Exception:
                pass
            return

        rfile = ssl_sock.makefile("rb")
        try:
            while True:
                req = read_http_request(rfile)
                if req is None:
                    break
                req_line, headers, body = req
                method = req_line.split(" ", 1)[0] if req_line else ""
                decompressed = decompress_body(body, headers.get("content-encoding"))
                cookie = extract_cookie(headers.get("cookie"))

                # Intercept Jio network connectivity validation probe
                if "/common/v1/network/check" in req_line:
                    resp_blob = forge_netcheck()
                    resp_data = (
                        f"HTTP/1.1 200 OK\r\n"
                        f"Content-Type: text/plain\r\n"
                        f"Content-Length: {len(resp_blob)}\r\n"
                        f"Connection: keep-alive\r\n\r\n"
                        f"{resp_blob}"
                    ).encode("utf-8")
                    ssl_sock.write(resp_data)
                    log(f"Spoofed /network/check probe from {cid} -> FTTH validation passed", self.log_path)
                    continue

                log(f"HTTP {req_line} | len={len(body)} | session={cookie or 'none'} from {cid}", self.log_path)

                # Check for CWMP Inform envelope
                if b"<cwmp:Inform" in decompressed:
                    m = re.search(r"<SerialNumber>([^<]+)</SerialNumber>", decompressed.decode("latin1", errors="replace"))
                    sn = m.group(1) if m else "UNKNOWN"
                    m2 = re.search(r"<ProductClass>([^<]+)</ProductClass>", decompressed.decode("latin1", errors="replace"))
                    model = m2.group(1) if m2 else "UNKNOWN"
                    log(f"🔥 CWMP INFORM DETECTED: Device={model} | Serial={sn}", self.log_path)

                # Route via session affinity
                conn = None
                with self.session_lock:
                    if cookie and cookie in self.sessions:
                        conn = self.sessions[cookie]

                if not conn:
                    conn = http.client.HTTPConnection(self.genie_target[0], self.genie_target[1], timeout=30)

                forward_headers = {k: v for k, v in headers.items() if k not in ("host", "content-length")}
                forward_headers["host"] = f"{self.genie_target[0]}:{self.genie_target[1]}"
                if len(body) > 0:
                    forward_headers["content-length"] = str(len(body))

                path = req_line.split(" ")[1] if len(req_line.split(" ")) > 1 else "/"
                conn.request(method, path, body=body, headers=forward_headers)
                upstream_resp = conn.getresponse()

                resp_body = upstream_resp.read()
                set_cookie = upstream_resp.getheader("set-cookie")
                new_cookie = extract_cookie(set_cookie)
                if new_cookie:
                    with self.session_lock:
                        self.sessions[new_cookie] = conn

                # Relay response back to STB
                ssl_sock.write(f"HTTP/1.1 {upstream_resp.status} {upstream_resp.reason}\r\n".encode("latin1"))
                for hk, hv in upstream_resp.getheaders():
                    if hk.lower() not in ("transfer-encoding",):
                        ssl_sock.write(f"{hk}: {hv}\r\n".encode("latin1"))
                ssl_sock.write(f"Content-Length: {len(resp_body)}\r\n\r\n".encode("latin1"))
                if resp_body:
                    ssl_sock.write(resp_body)

        except Exception as e:
            log(f"Proxy error handling {cid}: {e}", self.log_path)
        finally:
            try:
                ssl_sock.close()
            except Exception:
                pass

    def start_listener(self, port):
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", port))
        srv.listen(16)
        log(f"Listening on 0.0.0.0:{port} (TLS)", self.log_path)
        while True:
            try:
                client_sock, addr = srv.accept()
                t = threading.Thread(target=self.handle_client, args=(client_sock, addr), daemon=True)
                t.start()
            except Exception as e:
                log(f"Listener error on :{port}: {e}", self.log_path)

    def run(self):
        log(f"Starting Jio STB CWMP TLS Front-End (Model: {self.args.model.upper()})", self.log_path)
        log(f"Active Certificate Chain: {self.cert_path}", self.log_path)
        threads = []
        for port in self.ports:
            t = threading.Thread(target=self.start_listener, args=(port,), daemon=True)
            t.start()
            threads.append(t)
        for t in threads:
            t.join()

if __name__ == "__main__":
    args = parse_args()
    proxy = CWMPProxy(args)
    try:
        proxy.run()
    except KeyboardInterrupt:
        print("\n[!] Shutting down TLS proxy.")
        sys.exit(0)
