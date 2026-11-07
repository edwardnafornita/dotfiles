# NixOS for a desktop, gaming and development

One shared, pinned configuration with KDE Plasma as the default. Each computer
keeps its own hardware, accounts and preferences. Friends get a familiar desktop
and an **Update System** shortcut. Edi's machine uses Niri + iNiR; Niri + Noctalia
and Hyprland + Noctalia/Caelestia are also available.

## Start here

| Task | File or guide |
| --- | --- |
| Change Edi's current machine | [`settings/hosts/nixos.nix`](settings/hosts/nixos.nix) |
| Use and customize Edi's iNiR rice | [iNiR integration](docs/inir.md) |
| Change a friend's machine after installation | `settings/local/default.nix` (generated; ignored by Git) |
| Add/remove applications in shared bundles | [`settings/applications.nix`](settings/applications.nix) |
| Understand every setting and default | [`settings/README.md`](settings/README.md), [`settings/options.nix`](settings/options.nix) |
| Install on a new or existing computer | [Installation](docs/installation.md) |
| Deliver updates or recover a broken update | [Updates and recovery](docs/maintenance.md) |
| Understand/add feature modules | [Architecture](docs/architecture.md) |
| See what was preserved during migration | [Migration notes](docs/migration.md) |

## Desktops

Select a desktop in your machine settings, then run `apply-system` and restart:

```nix
desktop = "plasma"; # Default: complete KDE desktop, editable through System Settings.
# desktop = "niri"; # Niri with Noctalia; configuration in desktops/niri.nix.
# shell = "inir"; # With Niri: full iNiR rice, including its compositor config.
# desktop = "hyprland"; # Hyprland with Caelestia by default; desktops/hyprland.nix.
# shell = "noctalia"; # Optional Hyprland override; shell defaults follow desktop.
```

Supported combinations are Plasma with its native UI (`shell = "none"`), Niri
with Noctalia or iNiR, and Hyprland with either Noctalia or Caelestia. These shells provide
panels, launchers and locking; Niri and Hyprland provide window management.
Shell integration lives in `shells/`; [iNiR](docs/inir.md) keeps its GUI settings writable.
Remove a shell override when changing desktops to restore the matching default;
unsupported pairings fail with a clear evaluation error.

These are whole-machine session choices. Each account has its own application
selection and shell configuration. Only the chosen session and its shell are
enabled, so two panels/notification daemons do not compete. The Niri and Hyprland
profiles include terminal, file manager, browser, launcher, locking, screenshots,
media keys and window-management shortcuts. Plasma keeps its native UI settings.
Caelestia here is the upstream shell with this repo's Hyprland configuration, not
an installation of the entire upstream Arch dotfiles collection.

## Install

From NixOS (or its live USB), clone this repository and start the guided script:

```bash
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git
git clone https://github.com/edwardnafornita/dotfiles.git ~/dotfiles
cd ~/dotfiles
bash scripts/install.sh --existing
```

For a **fresh whole-disk install**, boot the NixOS x86_64 UEFI ISO and run the same
steps with `--fresh`. It lists disks, refuses disks in use, requires the exact
`ERASE /dev/...` confirmation, generates hardware configuration for that computer,
and asks for the new account password. Fresh installs use compressed **Btrfs**,
automatic root/home **Snapper snapshots**, and signed **Limine Secure Boot**.
For new keys, prepare firmware Setup Mode before installation, authorize key
enrollment, then enable Secure Boot in firmware afterward. To move NixOS to a new
drive on the same computer while preserving existing firmware keys, use:

```bash
bash scripts/install.sh --fresh \
  --reuse-secure-boot-from /dev/disk/by-uuid/OLD-NIXOS-ROOT-UUID
```

The script reads the old root partition automatically, verifies its signing keys
against firmware, and installs onto the separate disk you select. See the
[installation guide](docs/installation.md) first: fresh mode is unencrypted and
erases the chosen disk. Other drives are preserved. Use the graphical installer
for encryption or a dual-boot layout sharing one disk.

Do **not** run either installer on Edi's already-managed machine. Its output is
`edi-nixos` (renamed from `nixos` to prevent accidental fallback); it continues to use its existing hardware and Limine Secure Boot.

## Updates

Friends run **Update System** from their desktop/application menu, or:

```bash
update-system
```

This fetches the configured branch, fast-forwards only a clean checkout, builds
the committed lockfile with private local settings, and installs a generation
for the next reboot. It does not regenerate the lockfile, discard local edits,
change passwords or reboot automatically. Build logs are under
`~/.local/state/dotfiles/`. `apply-system` builds local edits without fetching.

## Validation

```bash
nix flake check path:. --no-update-lock-file
bash tests/host-selection.sh
nix build path:.#nixosConfigurations.edi-nixos.config.system.build.toplevel --no-update-lock-file
```

On a friend's checkout, replace `nixosConfigurations.edi-nixos` with
`nixosConfigurations.local` in the build command above.

Checks evaluate all three desktops for both Edi and two unrelated test accounts,
plus adoption of an existing graphical install. They
validate both Niri shell configurations and both Hyprland shell configurations with their actual parsers,
lint shell scripts, and exercise disk guards and update failure
paths using temporary repositories and mocked Nix/administrator commands. The
separate host-selection test evaluates real Git and path sources, including
ignored local settings and missing-output failures.
Evaluation is not a boot test. A fresh-install rehearsal in a disposable UEFI VM
and a real login/screen-sharing/lock/unlock test should precede a release to friends.
Never use `tests/machine.nix` on a real computer.

Use `path:.` for local builds: Git flakes omit new/untracked files and ignored
`settings/local/`. Path flakes intentionally include local settings in the Nix
source snapshot. **Never put secrets in that directory or elsewhere in this repo**;
Nix source snapshots are readable by local users.
