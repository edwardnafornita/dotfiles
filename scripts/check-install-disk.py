#!/usr/bin/env python3
"""Read-only whole-disk validation. Never mounts, formats or modifies a device."""
import json
import subprocess
import sys


def validate_disk(inventory, expected):
    devices = inventory.get("blockdevices", [])
    if len(devices) != 1:
        raise ValueError("Expected exactly one disk")
    disk = devices[0]
    if disk.get("name") != expected or disk.get("type") != "disk":
        raise ValueError("Select a whole physical/virtual disk, not a partition or mapper")
    if int(disk.get("size", 0)) < 32 * 1024**3:
        raise ValueError("Use a disk of at least 32 GiB; more is needed for games")

    def visit(device):
        if device.get("ro") in (True, 1, "1"):
            raise ValueError("Disk or partition is read-only")
        if any(device.get("mountpoints") or []):
            raise ValueError("Disk or a child is mounted/in use (including active swap)")
        if device.get("type") not in {"disk", "part"}:
            raise ValueError("Disk has active encrypted, RAID or device-mapper children")
        for child in device.get("children", []):
            visit(child)
    visit(disk)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: check-install-disk.py /dev/WHOLE-DISK")
    disk = sys.argv[1]
    try:
        output = subprocess.check_output([
            "lsblk", "--json", "--bytes", "--paths", "--output",
            "NAME,TYPE,SIZE,MOUNTPOINTS,RO", disk], text=True)
        validate_disk(json.loads(output), disk)
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Refusing to erase disk: {error}") from error


if __name__ == "__main__":
    main()
