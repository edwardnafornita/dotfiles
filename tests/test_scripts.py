"""No activation, network or disk operations: use temporary Git repos and fake Nix/sudo."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("settings_writer", ROOT / "scripts/write-local-settings.py")
disk_spec = importlib.util.spec_from_file_location("disk_guard", ROOT / "scripts/check-install-disk.py")
disk_guard = importlib.util.module_from_spec(disk_spec)
disk_spec.loader.exec_module(disk_guard)
writer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(writer)


class SettingsTests(unittest.TestCase):
    def settings(self, **changes):
        args = dict(user="friend", hostname="friend-pc", state_version="26.05",
                    timezone="America/Toronto", keyboard="us", desktop="plasma",
                    apps=[], uid=1000, repository="https://example.com/config.git", branch="main")
        args.update(changes)
        return SimpleNamespace(**args)

    def test_default_is_plasma_without_proprietary_apps(self):
        text = writer.render(self.settings())
        self.assertIn('desktop = "plasma";', text)
        self.assertIn('allowUnfree = false;', text)
        self.assertNotIn('users.edi', text)

    def test_rejects_invalid_identity_and_bundles(self):
        for changes in [dict(user='root'), dict(user='nixbld1'), dict(user='root; bad'), dict(hostname='../bad'),
                        dict(state_version='latest'), dict(apps=['unknown'])]:
            with self.assertRaises(ValueError):
                writer.render(self.settings(**changes))

    def test_nix_interpolation_is_escaped(self):
        text = writer.render(self.settings(timezone='${builtins.abort "injection"}'))
        self.assertIn(r'\${builtins.abort', text)

    def test_destination_never_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'default.nix'
            dest.write_text('keep me')
            result = subprocess.run(['python3', str(ROOT / 'scripts/write-local-settings.py'),
                '--user', 'friend', '--hostname', 'pc', '--destination', str(dest)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(dest.read_text(), 'keep me')


class DiskGuardTests(unittest.TestCase):
    def inventory(self, **changes):
        disk = dict(name="/dev/vda", type="disk", size=64 * 1024**3,
                    mountpoints=[None], ro=False, children=[])
        disk.update(changes)
        return {"blockdevices": [disk]}

    def test_empty_whole_disk_allowed(self):
        disk_guard.validate_disk(self.inventory(), "/dev/vda")

    def test_wrong_device_partition_small_and_readonly_refused(self):
        for changes in [dict(name="/dev/vdb"), dict(type="part"),
                        dict(size=1024), dict(ro=True)]:
            with self.assertRaises(ValueError):
                disk_guard.validate_disk(self.inventory(**changes), "/dev/vda")

    def test_live_usb_root_and_swap_mounts_refused(self):
        for mount in ["/", "/iso", "/nix/.ro-store", "/mnt", "[SWAP]"]:
            with self.assertRaises(ValueError):
                disk_guard.validate_disk(self.inventory(children=[{
                    "type": "part", "mountpoints": [mount], "ro": False
                }]), "/dev/vda")

    def test_mapper_children_refused_even_when_unmounted(self):
        with self.assertRaises(ValueError):
            disk_guard.validate_disk(self.inventory(children=[{
                "type": "crypt", "mountpoints": [None], "ro": False
            }]), "/dev/vda")

    def test_ambiguous_inventory_refused(self):
        with self.assertRaises(ValueError):
            disk_guard.validate_disk({"blockdevices": []}, "/dev/vda")


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.remote = self.base / 'remote'
        self.repo = self.base / 'dotfiles'
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.events = self.base / 'events'
        self.env = os.environ | {
            'HOME': str(self.base), 'XDG_STATE_HOME': str(self.base / 'state'),
            'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_NOSYSTEM': '1',
            'GIT_AUTHOR_NAME': 'Test', 'GIT_AUTHOR_EMAIL': 'test@example.invalid',
            'GIT_COMMITTER_NAME': 'Test', 'GIT_COMMITTER_EMAIL': 'test@example.invalid',
            'DOTFILES_CHECKOUT': str(self.repo), 'DOTFILES_OUTPUT': 'local',
            'DOTFILES_REPOSITORY': str(self.remote), 'DOTFILES_BRANCH': 'main',
            'PATH': str(self.bin) + os.pathsep + os.environ['PATH'],
            'TEST_EVENTS': str(self.events), 'TEST_SNAPSHOT': str(self.base / 'snapshot'),
        }
        self.git('init', '-b', 'main', str(self.remote))
        (self.remote / 'flake.lock').write_text('{}')
        (self.remote / '.gitignore').write_text('/settings/local/\n')
        self.git('-C', str(self.remote), 'add', '.')
        self.git('-C', str(self.remote), 'commit', '-m', 'initial')
        self.git('clone', str(self.remote), str(self.repo))
        (self.repo / 'settings/local').mkdir(parents=True)
        (self.repo / 'settings/local/default.nix').write_text('private settings')
        self.stub('nix', r'''#!/usr/bin/env bash
set -eu
printf 'nix %s\n' "$*" >> "$TEST_EVENTS"
if [[ $1 == flake && $2 == metadata ]]; then
  printf '{"path":"%s"}\n' "$TEST_SNAPSHOT"
elif [[ $1 == build ]]; then
  exit "${TEST_BUILD_STATUS:-0}"
else
  exit 90
fi
''')
        self.stub('nixos-rebuild', '#!/usr/bin/env bash\nexit 99\n')
        self.stub('sudo', r'''#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$TEST_EVENTS"
exit "${TEST_SUDO_STATUS:-0}"
''')

    def stub(self, name, content):
        path = self.bin / name
        path.write_text(content.replace("#!/usr/bin/env bash", "#!" + shutil.which("bash")))
        path.chmod(0o755)

    def git(self, *args):
        return subprocess.run(['git', *args], env=self.env, check=True, capture_output=True, text=True)

    def run_update(self, **extra):
        return subprocess.run(['bash', str(ROOT / 'scripts/update-system.sh')],
            env=self.env | extra, text=True, capture_output=True)

    def log(self):
        return self.events.read_text() if self.events.exists() else ''

    def test_update_uses_lock_and_preserves_private_settings(self):
        (self.remote / 'fix.nix').write_text('# reviewed fix')
        self.git('-C', str(self.remote), 'add', '.')
        self.git('-C', str(self.remote), 'commit', '-m', 'fix')
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.repo / 'fix.nix').exists())
        self.assertEqual((self.repo / 'settings/local/default.nix').read_text(), 'private settings')
        log = self.log()
        self.assertIn('#nixosConfigurations.local.config.system.build.toplevel', log)
        self.assertRegex(log, r'sudo [^\n ]*/nixos-rebuild boot')
        self.assertIn('snapshot#local', log)
        self.assertNotIn('flake update', log)

    def test_failed_build_never_activates(self):
        result = self.run_update(TEST_BUILD_STATUS='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('sudo ', self.log())

    def test_dirty_checkout_refused_without_losing_work(self):
        (self.repo / 'flake.lock').write_text('local edits')
        result = self.run_update()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.repo / 'flake.lock').read_text(), 'local edits')
        self.assertEqual(self.log(), '')

    def test_local_commits_refused(self):
        (self.repo / 'local').write_text('local work')
        self.git('-C', str(self.repo), 'add', '.')
        self.git('-C', str(self.repo), 'commit', '-m', 'local')
        result = self.run_update()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.repo / 'local').exists())
        self.assertEqual(self.log(), '')

    def test_wrong_origin_refused(self):
        result = self.run_update(DOTFILES_REPOSITORY='https://wrong.invalid/repo')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.log(), '')

    def test_apply_accepts_local_changes_without_fetching(self):
        (self.repo / 'flake.lock').write_text('local edits')
        result = self.run_update(DOTFILES_MODE='apply')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(self.log(), r'sudo [^\n ]*/nixos-rebuild boot')

    def test_activation_failure_reported(self):
        result = self.run_update(TEST_SUDO_STATUS='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Update installed.', result.stdout)


if __name__ == '__main__':
    unittest.main()
