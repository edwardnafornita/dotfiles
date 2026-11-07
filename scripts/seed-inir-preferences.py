"""Seed the shell's preferences and retire the port's competing config file."""
import shutil
import sys
from pathlib import Path
from time import time_ns


def seed(config_home, defaults):
    active = config_home / "illogical-impulse/config.json"
    alias = config_home / "inir/config.json"
    active.parent.mkdir(parents=True, exist_ok=True)
    alias.parent.mkdir(parents=True, exist_ok=True)
    if not active.exists():
        shutil.copyfile(alias if alias.exists() else defaults, active)
    if alias.exists() or alias.is_symlink():
        backup = alias.with_name(f"config.json.before-unified-{time_ns()}")
        alias.rename(backup)
        print(f"Previous inactive iNiR preferences saved to {backup}")
    # A file symlink is insufficient: the color helper saves with os.replace(),
    # replacing the link with a second file. With this path absent it selects
    # illogical-impulse/config.json, the same file used by QML and color scripts.


if __name__ == "__main__":
    seed(Path(sys.argv[1]), Path(sys.argv[2]))
