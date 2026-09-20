"""Create the distribution certificate here, keeping the private key.

Why this exists rather than letting fastlane's `get_certificates` do it:

A certificate is a public key signed by Apple. The *private* key never leaves
the machine that generated it. When CI generates one, that key dies with the
runner, so the certificate Apple now holds is permanently unusable and cannot be
recreated - it can only be revoked. Apple caps distribution certificates, so a
few failed CI runs quietly exhaust the account.

Generating the key here and storing the signed result as a .p12 means CI only
ever imports. Nothing is created per run, nothing is orphaned, and the same
identity signs every build forever.

    python Store/signing.py list
    python Store/signing.py revoke-orphans
    python Store/signing.py create
"""

import base64
import os
import subprocess
import sys
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12, PrivateFormat
from cryptography.x509.oid import NameOID

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc import call  # noqa: E402

OUT = Path(__file__).resolve().parent / "private"
P12_PASSWORD = "glyphstorm"


def list_certs():
    r = call("GET", "/v1/certificates", params={"limit": 50})
    data = (r or {}).get("data", [])
    print(f"{len(data)} certificate(s):")
    for d in data:
        a = d["attributes"]
        print(f"  {a.get('certificateType'):16} id={d['id']}  expires {a.get('expirationDate','')[:10]}")
    return data


def revoke_orphans():
    """Revoke every certificate, because none of them has a usable private key.

    Safe here and nowhere else: every certificate on this account was generated
    on a CI runner whose filesystem is gone, so not one of them can sign
    anything ever again. Revoking frees the slots.
    """
    data = list_certs()
    if not data:
        return
    for d in data:
        cid = d["id"]
        r = call("DELETE", f"/v1/certificates/{cid}")
        print(f"  revoked {cid}" if r is not None else f"  failed to revoke {cid}")


def create():
    """Generate a key, get Apple to sign it, and write a .p12."""
    OUT.mkdir(exist_ok=True)

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(
            x509.Name(
                [
                    x509.NameAttribute(NameOID.COMMON_NAME, "Glyphstorm Distribution"),
                    x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
                ]
            )
        )
        .sign(key, hashes.SHA256())
    )
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()

    made = call(
        "POST",
        "/v1/certificates",
        {
            "data": {
                "type": "certificates",
                "attributes": {
                    "certificateType": "DISTRIBUTION",
                    "csrContent": csr_pem,
                },
            }
        },
    )
    if not made:
        sys.exit("Apple refused to issue the certificate")

    cert_id = made["data"]["id"]
    content = made["data"]["attributes"]["certificateContent"]
    print(f"issued {cert_id}")

    # Apple returns the signed certificate as base64 DER.
    cert = x509.load_der_x509_certificate(base64.b64decode(content))

    # Legacy PKCS#12: 3DES with a SHA-1 HMAC.
    #
    # Not BestAvailableEncryption, which produces the AES-256 form. macOS
    # `security import` cannot read that and reports it as "MAC verification
    # failed during PKCS12 import (wrong password?)", which sends you hunting
    # for a password problem that does not exist.
    encryption = (
        PrivateFormat.PKCS12.encryption_builder()
        .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
        .hmac_hash(hashes.SHA1())
        .build(P12_PASSWORD.encode())
    )
    blob = pkcs12.serialize_key_and_certificates(
        name=b"Glyphstorm Distribution",
        key=key,
        cert=cert,
        cas=None,
        encryption_algorithm=encryption,
    )

    p12 = OUT / "distribution.p12"
    p12.write_bytes(blob)
    print(f"wrote {p12} ({len(blob)} bytes)")

    b64 = base64.b64encode(blob).decode()
    (OUT / "distribution.p12.base64").write_text(b64)

    # Straight into GitHub, so the key never sits anywhere it could be committed.
    for name, value in [
        ("DIST_CERT_P12", b64),
        ("DIST_CERT_PASSWORD", P12_PASSWORD),
    ]:
        proc = subprocess.run(
            ["gh", "secret", "set", name],
            input=value.encode(),
            capture_output=True,
        )
        print(f"  secret {name}: {'set' if proc.returncode == 0 else proc.stderr.decode()[:120]}")

    print("\ndone. CI now imports this identity rather than creating one.")


COMMANDS = {"list": list_certs, "revoke-orphans": revoke_orphans, "create": create}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(f"usage: python Store/signing.py [{'|'.join(COMMANDS)}]")
    COMMANDS[sys.argv[1]]()
