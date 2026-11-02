"""Exercise fresh-install ordering with fake firmware/disks and intercepted tools."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("secure_boot", ROOT / "scripts/check-secure-boot.py")
secure_boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(secure_boot)


class SecureBootTests(unittest.TestCase):
    def test_setup_mode_required_even_when_secure_boot_is_disabled(self):
        secure_boot.validate_status({"setup_mode": True, "secure_boot": False}, "setup")
        for status in [{}, {"setup_mode": False, "secure_boot": False},
                       {"setup_mode": True, "secure_boot": True},
                       {"setup_mode": 1, "secure_boot": False}]:
            with self.assertRaises(ValueError):
                secure_boot.validate_status(status, "setup")

    def test_unsigned_missing_or_wrong_binary_rejected(self):
        secure_boot.validate_signature([{"file_name": secure_boot.LIMINE_EFI, "is_signed": 1}])
        for result in [[], {}, [{"file_name": secure_boot.LIMINE_EFI, "is_signed": 0}],
                       [{"file_name": secure_boot.LIMINE_EFI, "is_signed": -1}],
                       [{"file_name": "/wrong.efi", "is_signed": 1}]]:
            with self.assertRaises(ValueError):
                secure_boot.validate_signature(result)

    def test_enrollment_must_leave_setup_mode_with_target_keys(self):
        good = {"installed": True, "setup_mode": False, "guid": "target-owner"}
        secure_boot.validate_status(good, "enrolled")
        for change in [{"installed": False}, {"setup_mode": True}, {"guid": ""}]:
            with self.assertRaises(ValueError):
                secure_boot.validate_status(good | change, "enrolled")


class FreshInstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.repo = self.base / "repo"
        shutil.copytree(ROOT / "scripts", self.repo / "scripts")
        self.target = self.base / "target"
        self.target.mkdir()
        (self.base / "efi").mkdir()
        self.disk = self.base / "nvme0n1"
        self.disk.touch()
        (self.base / "block/nvme0n1/holders").mkdir(parents=True)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.events = self.base / "events"
        self.env = os.environ | {
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "TEST_BASE": str(self.base), "TEST_DISK": str(self.disk),
            "TEST_TARGET": str(self.target), "TEST_EVENTS": str(self.events),
        }
        # Remap host-only preconditions in a test copy. All formatting, mounts,
        # firmware writes and target commands below are intercepted executables.
        script = (ROOT / "scripts/install-fresh.sh").read_text()
        script = script.replace("/sys/firmware/efi", str(self.base / "efi"))
        script = script.replace("[[ -e /iso ||", "[[ -d " + str(self.base / "efi") + " ||")
        script = script.replace("/sys/class/block/", str(self.base / "block") + "/")
        script = script.replace("[[ -b $disk", "[[ -f $disk")
        script = script.replace("/mnt", str(self.target))
        self.script = self.base / "install-fresh.sh"
        self.script.write_text(script)
        tool = self.bin / "fake-tool"
        tool.write_text("#!" + sys.executable + "\n" + r'''
import json
import os
from pathlib import Path
import subprocess
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["TEST_EVENTS"], "a") as log:
    log.write(json.dumps([name] + args) + "\n")
target = Path(os.environ["TEST_TARGET"])
if name == "sudo":
    sys.exit(0 if args == ["-v"] else subprocess.call(args))
elif name == "lsblk":
    if "--json" in args:
        print(json.dumps({"blockdevices": [{"name": os.environ["TEST_DISK"], "type": "disk",
              "size": 64 * 1024**3, "mountpoints": [None], "ro": False}]}))
    elif "-dnro" in args:
        print("disk")
    elif "-nrpo" in args:
        print(os.environ["TEST_DISK"])
elif name == "mountpoint":
    sys.exit(1)
elif name == "sbctl":
    print(json.dumps({"setup_mode": os.environ.get("TEST_SETUP", "1") == "1", "secure_boot": False}))
elif name == "btrfs":
    Path(args[-1]).mkdir()
elif name == "nixos-generate-config":
    (target / "etc/nixos").mkdir(parents=True)
    (target / "etc/nixos/hardware-configuration.nix").write_text("{ ... }: { }\n")
elif name == "nixos-install":
    (target / "var/lib/sbctl").mkdir(parents=True)
    (target / "home/friend").mkdir(parents=True)
elif name == "nixos-enter":
    cmd = args[args.index("-c") + 1]
    if cmd.startswith("sbctl verify"):
        print(json.dumps([{"file_name": "/boot/efi/limine/BOOTX64.EFI",
                           "is_signed": int(os.environ.get("TEST_SIGNED", "1"))}]))
    elif cmd.startswith("sbctl enroll-keys"):
        sys.exit(int(os.environ.get("TEST_ENROLL_STATUS", "0")))
    elif cmd == "sbctl status --json":
        print(json.dumps({"installed": True, "setup_mode": False, "guid": "target-owner"}))
    elif cmd.startswith("snapper"):
        sys.exit(int(os.environ.get("TEST_SNAPSHOT_STATUS", "0")))
elif name == "nix":
    print("1000" if "toString" in args[-1] else "friend")
''')
        tool.chmod(0o755)
        for name in ["sudo", "lsblk", "mountpoint", "swapon", "sbctl", "parted", "partprobe",
                     "udevadm", "mkfs.fat", "mkfs.btrfs", "btrfs", "mount", "umount", "chown",
                     "nixos-generate-config", "nixos-install", "nixos-enter", "nix"]:
            (self.bin / name).symlink_to(tool)

    def run_install(self, enrollment="ENROLL SECURE BOOT KEYS", erase=None, **changes):
        # The real interactive-terminal guard remains active.
        master, slave = os.openpty()
        try:
            process = subprocess.Popen([
                "bash", str(self.script), str(self.repo), "--user", "friend", "--hostname", "pc", "--fresh"
            ], stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, env=self.env | changes)
            os.close(slave)
            slave = None
            os.write(master, f"{enrollment}\n{self.disk}\n{erase or 'ERASE ' + str(self.disk)}\n".encode())
            output, _ = process.communicate(timeout=30)
            return process.returncode, output
        finally:
            os.close(master)
            if slave is not None:
                os.close(slave)

    def log(self):
        return [json.loads(line) for line in self.events.read_text().splitlines()]

    def test_btrfs_layout_signed_bootloader_and_initial_snapshots(self):
        status, output = self.run_install()
        self.assertEqual(status, 0, output)
        events = self.log()
        formats = [e for e in events if e[0].startswith("mkfs.")]
        self.assertEqual(formats, [["mkfs.fat", "-F", "32", str(self.disk) + "p1"],
                                  ["mkfs.btrfs", "-f", str(self.disk) + "p2"]])
        mounts = [e for e in events if e[0] == "mount"]
        for subvol in ["root", "home", "nix", "snapshots", "home-snapshots"]:
            self.assertTrue(any(f"subvol={subvol},compress=zstd,noatime" in e for e in mounts), subvol)
        target_commands = [e[-1] for e in events if e[0] == "nixos-enter"]
        self.assertLess(target_commands.index("sbctl verify --json /boot/efi/limine/BOOTX64.EFI"),
                        target_commands.index("sbctl enroll-keys --microsoft --firmware-builtin"))
        for name in ["root", "home"]:
            self.assertIn(f"snapper --no-dbus -c {name} create --cleanup-algorithm number --description installation",
                          target_commands)
        settings = (self.repo / "settings/local/default.nix").read_text()
        self.assertIn("btrfsSnapshots = true;", settings)
        self.assertIn("secureBoot = true;", settings)
        self.assertIn("Installation complete.", output)

    def test_firmware_preflight_and_confirmations_precede_disk_changes(self):
        for args in [{"TEST_SETUP": "0"}, {"enrollment": "no"}, {"erase": "no"}]:
            with self.subTest(args=args):
                status, output = self.run_install(**args)
                self.assertNotEqual(status, 0, output)
                self.assertFalse(any(e[0] == "parted" for e in self.log()))

    def test_unsigned_bootloader_never_enrolls_keys(self):
        status, output = self.run_install(TEST_SIGNED="0")
        self.assertNotEqual(status, 0, output)
        self.assertFalse(any(e[0] == "nixos-enter" and "enroll-keys" in e[-1] for e in self.log()))
        self.assertNotIn("Installation complete.", output)

    def test_failed_snapshot_never_enrolls_keys(self):
        status, output = self.run_install(TEST_SNAPSHOT_STATUS="1")
        self.assertNotEqual(status, 0, output)
        self.assertFalse(any(e[0] == "nixos-enter" and "enroll-keys" in e[-1] for e in self.log()))

    def test_failed_enrollment_never_reports_success(self):
        status, output = self.run_install(TEST_ENROLL_STATUS="1")
        self.assertNotEqual(status, 0, output)
        self.assertNotIn("Installation complete.", output)


if __name__ == "__main__":
    unittest.main()
