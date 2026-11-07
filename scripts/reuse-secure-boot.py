#!/usr/bin/env python3
"""Validate existing signing keys against firmware, then stage them outside Nix sources."""
import argparse
import base64
import json
from pathlib import Path
import shutil
import ssl
import subprocess
import uuid


def stage_keys(source, destination, enrolled, openssl):
    if not isinstance(enrolled, dict):
        raise ValueError("Expected enrolled firmware certificates")
    if source.resolve() != source.absolute():
        raise ValueError("The source key path must not contain symlinks")
    # Only accept the standard on-disk layout, without following source symlinks.
    for path in [source, source / "keys", *(source / "keys" / name for name in ("PK", "KEK", "db"))]:
        if path.is_symlink() or not path.is_dir():
            raise ValueError(f"Missing or symlinked key directory: {path}")
    files = [source / "GUID"]
    files.extend(source / "keys" / name / f"{name}.{suffix}"
                 for name in ("PK", "KEK", "db") for suffix in ("key", "pem"))
    for path in files:
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Missing or symlinked key file: {path}")
    uuid.UUID((source / "GUID").read_text().strip())
    for name, database in (("PK", "PK"), ("KEK", "KEK"), ("db", "DB")):
        key = source / "keys" / name / f"{name}.key"
        certificate = source / "keys" / name / f"{name}.pem"
        # Compare public keys only. Never print or put private keys in the store.
        public_key = subprocess.check_output(
            [openssl, "pkey", "-in", str(key), "-passin", "pass:", "-pubout"], stderr=subprocess.PIPE)
        certificate_key = subprocess.check_output(
            [openssl, "x509", "-in", str(certificate), "-pubkey", "-noout"], stderr=subprocess.PIPE)
        if public_key != certificate_key:
            raise ValueError(f"{name} private key does not match its certificate")
        der = ssl.PEM_cert_to_DER_cert(certificate.read_text())
        trusted = enrolled.get(database, [])
        if not isinstance(trusted, list) or not any(
            isinstance(entry, dict) and isinstance(entry.get("Raw"), str)
            and base64.b64decode(entry["Raw"], validate=True) == der for entry in trusted
        ):
            raise ValueError(f"{name} certificate is not enrolled in firmware; refusing to erase a disk")
    # Do not carry over files.json: it describes the old installation's EFI files.
    destination.mkdir(mode=0o700)
    (destination / "keys").mkdir(mode=0o700)
    for path in files:
        target = destination / path.relative_to(source)
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        target.chmod(0o600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--openssl", required=True)
    parser.add_argument("--sbctl", required=True)
    args = parser.parse_args()
    try:
        enrolled = json.loads(subprocess.check_output([args.sbctl, "list-enrolled-keys", "--json"]))
        stage_keys(args.source, args.destination, enrolled, args.openssl)
    except (ValueError, TypeError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Cannot reuse Secure Boot keys: {error}\n")
    print("Existing key pairs match the certificates enrolled in firmware.")


if __name__ == "__main__":
    main()
