"""Exercise first migration and subsequent GUI edits without touching a real home."""
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/seed-inir.sh"
PREFERENCES = SCRIPT.with_name("seed-inir-preferences.py")


class InirSeedTests(unittest.TestCase):
    def test_preferences_unify_both_paths_without_overwriting_gui_changes(self):
        for existing in ("none", "inir", "both"):
            with self.subTest(existing=existing), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                defaults = root / "defaults.json"
                defaults.write_text('{"panelFamily":"iris"}')
                config = root / "config"
                alias = config / "inir/config.json"
                active = config / "illogical-impulse/config.json"
                if existing != "none":
                    alias.parent.mkdir(parents=True)
                    alias.write_text('{"panelFamily":"waffle"}')
                if existing == "both":
                    active.parent.mkdir(parents=True)
                    active.write_text('{"panelFamily":"ii"}')
                expected = {"none": defaults.read_text(),
                            "inir": '{"panelFamily":"waffle"}',
                            "both": '{"panelFamily":"ii"}'}[existing]
                command = ["python3", str(PREFERENCES), str(config), str(defaults)]
                subprocess.run(command, check=True, capture_output=True)
                self.assertEqual(active.read_text(), expected)
                self.assertFalse(alias.exists())
                self.assertFalse(alias.is_symlink())
                backups = list(alias.parent.glob("config.json.before-unified-*"))
                self.assertEqual(len(backups), int(existing != "none"))
                if backups:
                    self.assertEqual(backups[0].read_text(), '{"panelFamily":"waffle"}')
                active.write_text('{"panelFamily":"iris","custom":"keep"}')
                subprocess.run(command, check=True, capture_output=True)
                self.assertEqual(active.read_text(), '{"panelFamily":"iris","custom":"keep"}')
                self.assertFalse(alias.exists())
                self.assertEqual(len(list(alias.parent.glob("config.json.before-unified-*"))),
                                 len(backups))

    def test_migration_backs_up_old_config_and_preserves_later_edits(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "store-rice"
            (source / "config.d").mkdir(parents=True)
            (source / "config.kdl").write_text('include "config.d/40-environment.kdl"\n')
            (source / "config.d/40-environment.kdl").write_text(
                'environment { INIR_VENV "$HOME/.local/state/quickshell/.venv"; }\n')
            for path in source.rglob("*.kdl"):
                path.chmod(0o444)

            target = root / "config/niri"
            target.mkdir(parents=True)
            old_file = root / "old-store-config"
            old_file.write_text("old noctalia configuration")
            (target / "config.kdl").symlink_to(old_file)
            (target / "personal.kdl").write_text("old extras")

            command = ["bash", str(SCRIPT), str(target), str(source), "/home/alice"]
            subprocess.run(command, check=True, capture_output=True)
            backups = list(target.parent.glob("niri.before-inir-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / "config.kdl").read_text(), old_file.read_text())
            self.assertEqual((backups[0] / "personal.kdl").read_text(), "old extras")
            self.assertFalse((target / "config.kdl").is_symlink())
            self.assertTrue((target / "config.kdl").stat().st_mode & 0o200)
            self.assertIn('/home/alice/.local/state',
                          (target / "config.d/40-environment.kdl").read_text())
            self.assertIn('$HOME', (source / "config.d/40-environment.kdl").read_text())

            (target / "config.kdl").write_text("settings changed through the GUI")
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual((target / "config.kdl").read_text(), "settings changed through the GUI")
            self.assertEqual(len(list(target.parent.glob("niri.before-inir-*"))), 1)

    def test_missing_source_does_not_move_current_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "niri"
            target.mkdir()
            (target / "config.kdl").write_text("keep")
            result = subprocess.run(
                ["bash", str(SCRIPT), str(target), str(root / "missing"), "/home/alice"],
                capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((target / "config.kdl").read_text(), "keep")
