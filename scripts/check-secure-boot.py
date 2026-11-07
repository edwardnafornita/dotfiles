#!/usr/bin/env python3
"""Validate sbctl JSON; its verify command can exit successfully for unsigned files."""
import json
import sys


LIMINE_EFI = "/boot/efi/limine/BOOTX64.EFI"
LIMINE_REMOVABLE_EFI = "/boot/efi/boot/BOOTX64.EFI"


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
    elif phase == "reuse":
        if status.get("setup_mode") is not False or type(status.get("secure_boot")) is not bool:
            raise ValueError("Key reuse requires existing enrolled firmware keys (Setup Mode disabled)")
    elif phase == "enrolled":
        if status.get("installed") is not True or status.get("setup_mode") is not False:
            raise ValueError("Target keys were not generated/enrolled successfully; keep Secure Boot disabled")
        if not isinstance(status.get("guid"), str) or not status["guid"]:
            raise ValueError("Missing target Secure Boot key owner GUID")
    else:
        raise ValueError("Unknown Secure Boot validation phase")


def validate_signature(files, expected=LIMINE_EFI):
    if not isinstance(files, list) or len(files) != 1:
        raise ValueError("Expected verification of exactly the installed Limine EFI binary")
    entry = files[0]
    if not isinstance(entry, dict) or entry.get("file_name") != expected or entry.get("is_signed") != 1:
        raise ValueError("Installed Limine EFI binary is missing or unsigned; refusing to finish installation")


def main():
    try:
        if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[1] != "signed"):
            raise ValueError("Usage: check-secure-boot.py setup|reuse|signed [EFI-PATH]|enrolled < sbctl.json")
        result = json.load(sys.stdin)
        if sys.argv[1] == "signed":
            expected = sys.argv[2] if len(sys.argv) == 3 else LIMINE_EFI
            if expected not in (LIMINE_EFI, LIMINE_REMOVABLE_EFI):
                raise ValueError("Unexpected Limine EFI path")
            validate_signature(result, expected)
        else:
            validate_status(result, sys.argv[1])
    except (ValueError, TypeError) as error:
        raise SystemExit(f"Secure Boot check failed: {error}") from error


if __name__ == "__main__":
    main()
