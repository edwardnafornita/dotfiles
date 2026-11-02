#!/usr/bin/env python3
"""Validate sbctl JSON; its verify command can exit successfully for unsigned files."""
import json
import sys


LIMINE_EFI = "/boot/efi/limine/BOOTX64.EFI"


def validate_status(status, phase):
    if not isinstance(status, dict):
        raise ValueError("Expected a Secure Boot status object")
    if phase == "setup":
        if status.get("setup_mode") is not True or status.get("secure_boot") is not False:
            raise ValueError(
                "Before installing, disable Secure Boot and enter firmware Setup Mode "
                "(custom-key enrollment mode), then boot the NixOS USB again. "
                "Disabling Secure Boot alone is not enough. No disk changes were made."
            )
    elif phase == "enrolled":
        if status.get("installed") is not True or status.get("setup_mode") is not False:
            raise ValueError("Target keys were not generated/enrolled successfully; keep Secure Boot disabled")
        if not isinstance(status.get("guid"), str) or not status["guid"]:
            raise ValueError("Missing target Secure Boot key owner GUID")
    else:
        raise ValueError("Unknown Secure Boot validation phase")


def validate_signature(files):
    if not isinstance(files, list) or len(files) != 1:
        raise ValueError("Expected verification of exactly the installed Limine EFI binary")
    entry = files[0]
    if not isinstance(entry, dict) or entry.get("file_name") != LIMINE_EFI or entry.get("is_signed") != 1:
        raise ValueError("Installed Limine EFI binary is missing or unsigned; refusing key enrollment")


def main():
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: check-secure-boot.py setup|signed|enrolled < sbctl.json")
        result = json.load(sys.stdin)
        if sys.argv[1] == "signed":
            validate_signature(result)
        else:
            validate_status(result, sys.argv[1])
    except (ValueError, TypeError) as error:
        raise SystemExit(f"Secure Boot check failed: {error}") from error


if __name__ == "__main__":
    main()
