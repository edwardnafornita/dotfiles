"""Exercise fresh-install ordering with fake firmware/disks and intercepted tools."""
import importlib.util
import base64
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("secure_boot", ROOT / "scripts/check-secure-boot.py")
secure_boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(secure_boot)
reuse_spec = importlib.util.spec_from_file_location("reuse_keys", ROOT / "scripts/reuse-secure-boot.py")
reuse_keys = importlib.util.module_from_spec(reuse_spec)
reuse_spec.loader.exec_module(reuse_keys)


def create_keys(source):
    source.mkdir(parents=True)
    (source / "GUID").write_text("9ce0834b-b223-4a26-9042-bc91a5f57ebe\n")
    enrolled = {}
    for name, database in (("PK", "PK"), ("KEK", "KEK"), ("db", "DB")):
        directory = source / "keys" / name
        directory.mkdir(parents=True)
        subprocess.run(["openssl", "req", "-new", "-x509", "-newkey", "ec",
                        "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes", "-days", "1",
                        "-subj", f"/CN=Test {name}", "-keyout", str(directory / f"{name}.key"),
                        "-out", str(directory / f"{name}.pem")], check=True, capture_output=True)
        der = ssl.PEM_cert_to_DER_cert((directory / f"{name}.pem").read_text())
        enrolled[database] = [{"Raw": base64.b64encode(der).decode()}]
    (source / "files.json").write_text('{"old-efi-file": {}}')
    return enrolled


class KeyReuseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.source = self.base / "source"
        self.destination = self.base / "staged"
        self.enrolled = create_keys(self.source)

    def stage(self):
        reuse_keys.stage_keys(self.source, self.destination, self.enrolled, shutil.which("openssl"))

    def test_preserves_keys_guid_permissions_and_excludes_old_signing_database(self):
        self.stage()
        self.assertEqual((self.destination / "GUID").read_bytes(), (self.source / "GUID").read_bytes())
        for path in (self.source / "keys").rglob("*"):
            target = self.destination / path.relative_to(self.source)
            if path.is_file():
                self.assertEqual(path.read_bytes(), target.read_bytes())
                self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            else:
                self.assertEqual(target.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.destination.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.destination / "keys").stat().st_mode & 0o777, 0o700)
        self.assertFalse((self.destination / "files.json").exists())

    def test_unenrolled_certificate_rejected_before_staging(self):
        self.enrolled["DB"] = []
        with self.assertRaisesRegex(ValueError, "not enrolled"):
            self.stage()
        self.assertFalse(self.destination.exists())

    def test_mismatched_key_rejected_before_staging(self):
        shutil.copyfile(self.source / "keys/PK/PK.key", self.source / "keys/db/db.key")
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.stage()
        self.assertFalse(self.destination.exists())

    def test_missing_key_rejected_before_staging(self):
        (self.source / "keys/db/db.key").unlink()
        with self.assertRaisesRegex(ValueError, "Missing"):
            self.stage()
        self.assertFalse(self.destination.exists())

    def test_symlinked_key_or_ancestor_rejected(self):
        key = self.source / "keys/db/db.key"
        key.rename(self.base / "outside.key")
        key.symlink_to(self.base / "outside.key")
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.stage()
        key.unlink()
        (self.base / "outside.key").rename(key)
        self.source.rename(self.base / "actual")
        self.source.symlink_to(self.base / "actual", target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.stage()

    def test_invalid_guid_rejected_before_staging(self):
        (self.source / "GUID").write_text("invalid")
        with self.assertRaises(ValueError):
            self.stage()
        self.assertFalse(self.destination.exists())


class SecureBootTests(unittest.TestCase):
    def test_reuse_requires_enrolled_keys_but_allows_secure_boot_disabled_for_iso(self):
        for enabled in (True, False):
            secure_boot.validate_status({"setup_mode": False, "secure_boot": enabled}, "reuse")
        for status in ({}, {"setup_mode": True, "secure_boot": False},
                       {"setup_mode": False, "secure_boot": 0}):
            with self.assertRaises(ValueError):
                secure_boot.validate_status(status, "reuse")

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

    def test_reuse_signature_must_match_the_fallback_binary(self):
        result = [{"file_name": secure_boot.LIMINE_REMOVABLE_EFI, "is_signed": 1}]
        secure_boot.validate_signature(result, secure_boot.LIMINE_REMOVABLE_EFI)
        with self.assertRaises(ValueError):
            secure_boot.validate_signature(result)

    def test_enrollment_must_leave_setup_mode_with_target_keys(self):
        good = {"installed": True, "setup_mode": False, "guid": "target-owner"}
        secure_boot.validate_status(good, "enrolled")
        for change in [{"installed": False}, {"setup_mode": True}, {"guid": ""}]:
            with self.assertRaises(ValueError):
                secure_boot.validate_status(good | change, "enrolled")


class InstallerArgumentsTests(unittest.TestCase):
    def test_bootstrap_preserves_key_source_argument(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = root / "install.sh"
            text = (ROOT / "scripts/install.sh").read_text().replace("/etc/NIXOS", str(root / "NIXOS"))
            script.write_text(text)
            (root / "NIXOS").touch()
            tool = root / "nix"
            tool.write_text("#!" + sys.executable + "\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n")
            tool.chmod(0o755)
            master, slave = os.openpty()
            try:
                result = subprocess.run([
                    "bash", str(script), "--fresh", "--reuse-secure-boot-from", "/dev/disk/by-uuid/old-root"
                ], stdin=slave, text=True, capture_output=True, env=os.environ | {
                    "PATH": str(root) + os.pathsep + os.environ["PATH"], "DOTFILES_INSTALL_TOOLS": "0",
                })
                self.assertEqual(result.returncode, 0, result.stderr)
                arguments = json.loads(result.stdout)
                self.assertEqual(arguments[-3:], ["--fresh", "--reuse-secure-boot-from", "/dev/disk/by-uuid/old-root"])
                self.assertIn("nixpkgs#openssl", arguments)
                self.assertIn("nixpkgs#efibootmgr", arguments)
            finally:
                os.close(master)
                os.close(slave)

    def test_bootstrap_preserves_key_source_argument_for_existing_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = root / "install.sh"
            text = (ROOT / "scripts/install.sh").read_text().replace("/etc/NIXOS", str(root / "NIXOS"))
            script.write_text(text)
            (root / "NIXOS").touch()
            tool = root / "nix"
            tool.write_text("#!" + sys.executable + "\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n")
            tool.chmod(0o755)
            master, slave = os.openpty()
            try:
                result = subprocess.run([
                    "bash", str(script), "--existing", "--reuse-secure-boot-from", "/dev/disk/by-uuid/old-root"
                ], stdin=slave, text=True, capture_output=True, env=os.environ | {
                    "PATH": str(root) + os.pathsep + os.environ["PATH"], "DOTFILES_INSTALL_TOOLS": "0",
                })
                self.assertEqual(result.returncode, 0, result.stderr)
                arguments = json.loads(result.stdout)
                self.assertEqual(arguments[-3:],
                                 ["--existing", "--reuse-secure-boot-from", "/dev/disk/by-uuid/old-root"])
            finally:
                os.close(master)
                os.close(slave)

    def test_invalid_options_rejected_before_bootstrap(self):
        for arguments in (["--fresh", "--reuse-secure-boot-from"],
                          ["--existing", "--reuse-secure-boot-from"],
                          ["--fresh", "--unknown", "/dev/old-root"],
                          ["--existing", "--unknown", "/dev/old-root"]):
            result = subprocess.run(["bash", str(ROOT / "scripts/install.sh"), *arguments],
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)


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
        self.source_device = self.base / "nvme1n1p7"
        self.source_device.touch()
        self.source_root = self.base / "old-root"
        self.enrolled = create_keys(self.source_root / "var/lib/sbctl")
        (self.base / "block/nvme0n1/holders").mkdir(parents=True)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.events = self.base / "events"
        self.env = os.environ | {
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "TEST_BASE": str(self.base), "TEST_DISK": str(self.disk),
            "TEST_TARGET": str(self.target), "TEST_EVENTS": str(self.events),
            "TEST_SOURCE_DEVICE": str(self.source_device), "TEST_SOURCE_ROOT": str(self.source_root),
            "TEST_ENROLLED": json.dumps(self.enrolled),
        }
        # Remap host-only preconditions in a test copy. All formatting, mounts,
        # firmware writes and target commands below are intercepted executables.
        script = (ROOT / "scripts/install-fresh.sh").read_text()
        script = script.replace("/sys/firmware/efi", str(self.base / "efi"))
        script = script.replace("[[ -e /iso ||", "[[ -d " + str(self.base / "efi") + " ||")
        script = script.replace("/sys/class/block/", str(self.base / "block") + "/")
        script = script.replace("[[ -b $disk", "[[ -f $disk")
        script = script.replace("[[ -b $source_device", "[[ -f $source_device")
        script = script.replace("/run/dotfiles-secure-boot.", str(self.base / "secure-boot."))
        script = script.replace("/mnt", str(self.target))
        self.script = self.base / "install-fresh.sh"
        self.script.write_text(script)
        tool = self.bin / "fake-tool"
        tool.write_text("#!" + sys.executable + "\n" + r'''
import json
import os
from pathlib import Path
import subprocess
import shutil
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
        if args[1] == "FSTYPE":
            print(os.environ.get("TEST_SOURCE_FSTYPE", "btrfs"))
        else:
            print("part" if args[-1] == os.environ["TEST_SOURCE_DEVICE"] else "disk")
    elif "-snrpo" in args:
        print(os.environ["TEST_SOURCE_DEVICE"])
        print(os.environ["TEST_DISK"] if os.environ.get("TEST_SOURCE_ON_TARGET") else "/dev/old-disk")
    elif "-nrpo" in args:
        print(os.environ["TEST_DISK"])
elif name == "mountpoint":
    sys.exit(1)
elif name == "sbctl":
    if args[0] == "list-enrolled-keys":
        enrolled = json.loads(os.environ["TEST_ENROLLED"])
        if os.environ.get("TEST_UNTRUSTED"):
            enrolled["DB"] = []
        print(json.dumps(enrolled))
    else:
        print(json.dumps({"setup_mode": os.environ.get("TEST_SETUP", "1") == "1",
                          "secure_boot": os.environ.get("TEST_SECURE_BOOT", "0") == "1"}))
elif name == "mount" and args[-2] == os.environ["TEST_SOURCE_DEVICE"]:
    shutil.copytree(os.environ["TEST_SOURCE_ROOT"], args[-1], dirs_exist_ok=True)
elif name == "btrfs":
    Path(args[-1]).mkdir()
elif name == "nixos-generate-config":
    (target / "etc/nixos").mkdir(parents=True)
    (target / "etc/nixos/hardware-configuration.nix").write_text("{ ... }: { }\n")
elif name == "nixos-install":
    if os.environ.get("TEST_EXPECT_REUSE"):
        source = Path(os.environ["TEST_SOURCE_ROOT"]) / "var/lib/sbctl"
        for path in source.rglob("*"):
            if path.is_file() and path.name != "files.json":
                assert path.read_bytes() == (target / "var/lib/sbctl" / path.relative_to(source)).read_bytes()
        assert not (target / "var/lib/sbctl/files.json").exists()
    (target / "var/lib/sbctl").mkdir(parents=True, exist_ok=True)
    (target / "home/friend").mkdir(parents=True)
elif name == "nixos-enter":
    cmd = args[args.index("-c") + 1]
    if cmd.startswith("sbctl verify"):
        print(json.dumps([{"file_name": cmd.split()[-1],
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
                     "nixos-generate-config", "nixos-install", "nixos-enter", "nix", "efibootmgr"]:
            (self.bin / name).symlink_to(tool)

    def run_install(self, enrollment="ENROLL SECURE BOOT KEYS", erase=None, reuse=False, **changes):
        # The real interactive-terminal guard remains active.
        master, slave = os.openpty()
        try:
            options = ["--reuse-secure-boot-from", str(self.source_device)] if reuse else []
            if reuse:
                changes = {"TEST_SETUP": "0", "TEST_EXPECT_REUSE": "1"} | changes
            process = subprocess.Popen([
                "bash", str(self.script), str(self.repo), *options,
                "--user", "friend", "--hostname", "pc", "--fresh"
            ], stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, env=self.env | changes)
            os.close(slave)
            slave = None
            answers = ([] if reuse else [enrollment]) + [str(self.disk), erase or 'ERASE ' + str(self.disk)]
            os.write(master, ("\n".join(answers) + "\n").encode())
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

    def test_reuse_stages_existing_keys_before_install_without_enrollment(self):
        status, output = self.run_install(reuse=True, TEST_SECURE_BOOT="1")
        self.assertEqual(status, 0, output)
        events = self.log()
        self.assertFalse(any("enroll-keys" in " ".join(e) for e in events))
        self.assertFalse(any("create-keys" in " ".join(e) for e in events))
        source_mount = next(e for e in events if e[0] == "mount" and str(self.source_device) in e)
        self.assertIn("ro,nologreplay,subvol=root", source_mount)
        source_unmount = next(e for e in events if e[0] == "umount" and e[-1] == source_mount[-1])
        self.assertLess(events.index(source_unmount), next(i for i, e in enumerate(events) if e[0] == "parted"))
        machine = (self.repo / "settings/local/machine.nix").read_text()
        self.assertIn("autoGenerateKeys = lib.mkForce false", machine)
        self.assertIn("autoEnrollKeys.enable = lib.mkForce false", machine)
        self.assertIn("canTouchEfiVariables = lib.mkForce false", machine)
        self.assertIn("efiInstallAsRemovable = lib.mkForce true", machine)
        boot_entries = [e for e in events if e[0] == "efibootmgr"]
        self.assertEqual(boot_entries, [["efibootmgr", "--create", "--disk", str(self.disk),
                                      "--part", "1", "--loader", "\\efi\\boot\\BOOTX64.EFI",
                                      "--label", "NixOS (new drive)"]])
        verify = next(i for i, e in enumerate(events) if e[0] == "nixos-enter" and e[-1].startswith("sbctl verify"))
        self.assertLess(verify, events.index(boot_entries[0]))
        self.assertIn("Installation complete.", output)
        self.assertFalse(list(self.base.glob("secure-boot.*")))

    def test_reuse_accepts_temporarily_disabled_secure_boot_and_ext4_source(self):
        status, output = self.run_install(reuse=True, TEST_SOURCE_FSTYPE="ext4")
        self.assertEqual(status, 0, output)
        self.assertTrue(any(e[0] == "mount" and "ro,noload" in e for e in self.log()))

    def test_reuse_rejects_untrusted_keys_before_formatting_and_cleans_staging(self):
        status, output = self.run_install(reuse=True, TEST_UNTRUSTED="1")
        self.assertNotEqual(status, 0, output)
        self.assertFalse(any(e[0] == "parted" for e in self.log()))
        self.assertIn("not enrolled", output)
        self.assertFalse(list(self.base.glob("secure-boot.*")))

    def test_reuse_refuses_to_erase_its_source_disk(self):
        status, output = self.run_install(reuse=True, TEST_SOURCE_ON_TARGET="1")
        self.assertNotEqual(status, 0, output)
        self.assertFalse(any(e[0] == "parted" for e in self.log()))
        self.assertIn("supplying your keys", output)

    def test_reuse_rejects_setup_mode_before_formatting(self):
        status, output = self.run_install(reuse=True, TEST_SETUP="1")
        self.assertNotEqual(status, 0, output)
        self.assertFalse(any(e[0] == "parted" for e in self.log()))

    def test_reuse_missing_keys_and_unsupported_filesystems_fail_before_formatting(self):
        (self.source_root / "var/lib/sbctl/keys/db/db.key").unlink()
        for changes in ({}, {"TEST_SOURCE_FSTYPE": "crypto_LUKS"}):
            with self.subTest(changes=changes):
                status, output = self.run_install(reuse=True, **changes)
                self.assertNotEqual(status, 0, output)
                self.assertFalse(any(e[0] == "parted" for e in self.log()))
                self.assertFalse(list(self.base.glob("secure-boot.*")))

    def test_reuse_cancellation_cleans_keys_and_does_not_format(self):
        status, output = self.run_install(reuse=True, erase="no")
        self.assertEqual(status, 1, output)
        self.assertFalse(any(e[0] == "parted" for e in self.log()))
        self.assertFalse(list(self.base.glob("secure-boot.*")))

    def test_reuse_unsigned_bootloader_never_reports_success(self):
        status, output = self.run_install(reuse=True, TEST_SIGNED="0")
        self.assertNotEqual(status, 0, output)
        self.assertNotIn("Installation complete.", output)
        self.assertFalse(any("enroll-keys" in " ".join(e) for e in self.log()))
        self.assertFalse(any(e[0] == "efibootmgr" for e in self.log()))


if __name__ == "__main__":
    unittest.main()
