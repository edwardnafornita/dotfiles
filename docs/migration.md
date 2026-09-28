# Migration from the original layout

The refactor used the working tree, including pre-existing uncommitted changes.
It did not switch, install or reboot the running system.

| Old location | New owner |
| --- | --- |
| `configuration.nix` | `modules/core.nix` and `hosts/nixos/default.nix` |
| `hardware-configuration.nix` | Unchanged, at the original root path |
| `modules/hardware/other-drives.nix` | `hosts/nixos/drives.nix` |
| `users/edi.nix`, `users/default.nix` | `settings/hosts/nixos.nix` plus generic account creation |
| `home/common.nix`, `home/gaming.nix`, `home/programming.nix` | `settings/applications.nix` and `modules/applications.nix` |
| `home/ctt-bash.nix` | Optional per-account `bash = "ctt"` integration |
| `home/update-system.nix` | Packaged scripts in `modules/maintenance.nix` and `scripts/` |
| `rices/noctalia.nix` | `desktops/niri.nix` and `shells/noctalia.nix`, with monitors in host settings |
| One-purpose system modules | Consolidated into core, applications, desktop and maintenance features |
| Unused root `home.nix`, Sway/Dank presets | Removed; the supported matrix is Plasma/Niri/Hyprland |

## Existing machine invariants

- Root hardware file preserved byte for byte, including Btrfs subvolumes, EFI mount,
  swap, initrd modules and AMD microcode configuration.
- Same Limine settings, Secure Boot, Windows entry and `reboot-windows` helper.
- Same external drive UUIDs, filesystem types and mount options.
- Same NixOS/Home Manager state versions and existing dependency pins.
- Same `nixos` hostname, Niri/Noctalia selection, monitors, shell, browser,
  gaming/development applications, keyboard remapping and SDDM theme.
- Edi remains an administrator with the same home and group memberships; the actual
  existing UID 1000 is now explicit to protect disk ownership.
- The duplicate Home Manager installation of `nh` is removed; the system module
  still provides the same command. Applications otherwise remain available.

The personal flake output is now **`edi-nixos`**, replacing `nixos`. This prevents a
Git flake that omits a friend's ignored local settings from selecting Edi's
hardware through the common hostname `nixos`. The hostname and hardware remain
unchanged. Use the explicit command below for the first application; the old
installed updater may still request the retired output until this generation is
activated. Friends continue to use `local` and `path:`.

Intentional improvements include standard XDG user directories, user-owned
screenshot/wallpaper directories, packaged update commands, and a desktop launcher using the terminal installed by the selected profile. The previously managed `~/.local/bin/update-system` symlink is removed
by Home Manager when its old declaration disappears. The new command lives in the
user package profile; `~/.local/bin` is explicitly added for other personal scripts.

For the first application, review the diff, build, and install for the next boot:

```bash
nix flake check path:. --no-update-lock-file
nix build path:.#nixosConfigurations.edi-nixos.config.system.build.toplevel --no-update-lock-file
sudo nixos-rebuild boot --flake path:.#edi-nixos --no-write-lock-file
```

Use `path:.` for local builds, including after committing. The regular Git flake still needs new
files tracked; the existing staged changes have deliberately not been restaged
or committed by the refactor. After reboot, use `apply-system` while developing
and `update-system` once your branch is clean and published.

A preserved evaluated configuration and successful builds reduce migration risk;
they cannot guarantee a physical boot, firmware behavior, or runtime desktop
functionality. Keep the prior generation for the first reboot.

## Initial verification on 2026-09-27

- Full personal system build succeeded before the output rename;
  no activation, bootloader installation, partitioning or reboot was performed.
- `nix flake check` passed: all three desktop selections on the existing machine,
  all three on a generic two-account machine, and adoption of a prior GNOME install.
- Sixteen isolated tests passed for generated settings, disk selection guards,
  update fast-forwards, preservation of private settings, dirty/divergent checkout
  refusal, and failure handling before/after the mocked administrator command.
- The generated Niri configuration passed `niri validate` and matched the original
  configuration apart from whitespace.
- Hardware file matched byte for byte; evaluated bootloader, filesystems, swap,
  initrd and kernel module settings matched the captured pre-refactor working tree.
- System package names/versions matched exactly. Home packages changed only by
  removing the redundant per-user `nh` (still installed system-wide) and adding
  `apply-system`, `update-system` and `xdg-user-dirs`.
- Original nixpkgs, Home Manager, Noctalia, Helium and CTT input pins were retained.
- The initial friend test covered only a path source; review subsequently found
  that Git sources could fall back to Edi. The regression test now covers both.
- ShellCheck, Bash syntax checks, Nix formatting checks and `git diff --check` passed.

The fresh installer was not run against a real disk or booted in a UEFI VM during
this refactor. Plasma and Hyprland were evaluated, not interactively exercised.
These remain release rehearsal steps; configuration/build success is not a claim
of physical-machine or graphical-session testing.

## Review corrections verified on 2026-09-27

- Removed the generic personal-host fallback. The personal output is `edi-nixos`;
  friends retain `local`. The real Git/path integration test passes, including a
  friend's hostname `nixos` and refusal when Git omits private local settings.
- Explicitly selected Hyprlang for the existing Hyprland syntax. Both Noctalia and
  Caelestia variants pass the pinned Hyprland binary's `--verify-config` parser.
- Removed the redundant SDDM greeter override. The adoption fixture now includes
  an explicit Wayland greeter and evaluates successfully; Edi still uses X11.
- Moved shell configuration into `shells/` and added the central `shell` option.
  The profile checks cover both Hyprland shell choices and their authentication
  agents, alongside the existing desktop matrix.
- The corrected `edi-nixos` system built successfully. Bootloader, filesystem,
  swap, initrd and kernel module values match the original snapshot; the hardware
  file remains byte-for-byte identical and Niri matches apart from whitespace.
- Flake checks, the 16 installer/updater tests, formatting and diff checks pass.
  No system activation or graphical login test was performed.
