"""Run the patched port's palette engine against isolated wallpaper preferences."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = os.environ.get("INIR_COLOR_SYNC_SOURCE")


@unittest.skipUnless(SOURCE, "Set INIR_COLOR_SYNC_SOURCE to the pinned port script")
class InirColorSyncTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = root / "scripts/niri-sync-colors"
            script.parent.mkdir()
            script.write_text(Path(SOURCE).read_text())
            subprocess.run(
                ["patch", "--batch", "--fuzz=0", "-p1", "-i",
                 str(ROOT / "patches/inir-color-sync-wallpaper.patch")],
                cwd=root, check=True, capture_output=True)
            subprocess.run(["bash", "-n", str(script)], check=True)
            # Run the actual embedded Python engine, without broadcasting terminal
            # escapes or invoking desktop services from the surrounding shell.
            cls.engine = script.read_text().split('"$PYTHON" -c \'\n', 1)[1].split(
                '\n\' "$GENERATED_DIR"', 1)[0]

    def test_palette_sources_never_replace_shell_wallpaper(self):
        cases = (
            ("live.mp4", "video-thumbnail.jpg"),
            ("live.webm", "video-thumbnail.jpg"),
            ("live.gif", "gif-thumbnail.jpg"),
            ("photo.png", "backdrop.jpg"),
            ("photo.png", "colors-only-preview.jpg"),
        )
        for wallpaper, color_source in cases:
            with self.subTest(wallpaper=wallpaper, source=color_source), \
                    tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                generated = root / "generated"
                generated.mkdir()
                (generated / "colors.json").write_text(json.dumps({
                    "primary": "#abcdef", "secondary": "#123456", "dark": True}))
                image = root / color_source
                image.touch()
                (generated / "theme-meta.json").write_text(json.dumps({
                    "source_path": str(image), "mode": "dark"}))
                config = root / "config.json"
                config.write_text(json.dumps({
                    "background": {
                        "wallpaperPath": str(root / wallpaper),
                        "thumbnailPath": str(image),
                        "wallpapersByMonitor": [{"monitor": "DP-2", "path": "other.mp4"}],
                    },
                    "panelFamily": "iris",
                }))
                before = config.read_bytes()
                layout = root / "niri/config.d/20-layout-and-overview.kdl"
                layout.parent.mkdir(parents=True)
                layout.write_text('focus-ring {\n active-color "#000000"\n'
                                  ' inactive-color "#111111"\n}\n')
                # Repeated palette updates must preserve shell preferences while
                # still updating the compositor's colors.
                for _ in range(2):
                    subprocess.run(
                        [sys.executable, "-c", self.engine, str(generated),
                         str(config), str(root / "niri/config.kdl"), ""],
                        env={**os.environ, "HOME": str(root), "PATH": ""},
                        check=True, capture_output=True)
                    self.assertEqual(config.read_bytes(), before)
                    self.assertIn('active-color "#abcdef"', layout.read_text())
                    self.assertIn('inactive-color "#123456"', layout.read_text())
