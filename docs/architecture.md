# Architecture and module ownership

The flake uses flake-parts with feature-oriented modules, inspired by
[Vimjoyer's dendritic Home Manager example](https://www.vimjoyer.com/nix/dendritic-home-manager).
Each feature exports a NixOS module and, when needed, a Home Manager module from
the same file. Explicit imports keep this small repository's enablement graph
visible. There is no automatic import-tree dependency or standalone Home Manager
configuration: these accounts are rebuilt together with their NixOS system.

```text
flake.nix + flake.lock
  modules/hosts.nix
    settings/options.nix + settings/defaults.nix
    settings/hosts/nixos.nix OR settings/local/default.nix
      machineModule (hardware, bootloader, storage)
      modules/core.nix          -> accounts, HM integration, networking/audio/printing
      modules/applications.nix  -> packages, gaming integration, developer shell
      modules/desktop.nix       -> selected login session and desktop services
        desktops/plasma.nix    -> native Plasma preferences
        desktops/niri.nix      -> Niri compositor configuration
        desktops/inir.nix      -> full iNiR Niri rice, validated before seeding
        desktops/hyprland.nix  -> Hyprland compositor configuration
        shells/noctalia.nix    -> Noctalia appearance (Niri or Hyprland)
        shells/caelestia.nix   -> Caelestia appearance and service (Hyprland)
        shells/inir.nix        -> writable first-login rice migration
      modules/inir.nix          -> iNiR runtime, services, PAM and fonts
      modules/input-method.nix  -> opt-in per-user Korean input and browser integration
      modules/maintenance.nix   -> cleanup, packaged commands and shortcuts
      modules/recovery.nix      -> optional Btrfs snapshots and signed Limine
```

`settings` is evaluated once with `lib.evalModules`: enums, booleans, user records
and package groups are validated. It is passed explicitly into NixOS and Home
Manager. Feature modules use native NixOS/HM options; `mkIf` controls optional
features. A module being imported declares its options and does not by itself
enable its service. The Noctalia option module is imported in all profiles so
conditional definitions remain well-typed, but its program/services are enabled
only when `shell = "noctalia"`. Compatibility assertions reject unsupported
desktop/shell combinations.

Both stable nixpkgs and Home Manager retain their previous locked revisions;
Home Manager follows stable nixpkgs and uses the same package set. Noctalia keeps
its pre-existing revision and upstream dependency graph. Caelestia's shell uses
its own upstream package set because its Qt/Quickshell dependencies are newer;
Hyprland and its matching portal still come from the system's stable nixpkgs.
Never mix an unrelated Hyprland compositor and portal package. UWSM manages the
Hyprland session; Home Manager's separate compositor systemd integration is off
to avoid two session managers. Hyprland explicitly selects Home Manager's
`configType = "hyprlang"` because this profile uses legacy bind/monitor syntax.
The pinned Hyprland 0.55.4 supports this format; Home Manager 26.05's implicit Lua
format cannot serialize these settings correctly. `checks.hyprland-config` runs
the pinned compositor's `--verify-config` parser for each supported shell.

SDDM's greeter protocol is left to upstream defaults or the adopted machine's
explicit setting. Hardcoding a normal-priority value here would conflict with
existing installer configurations; a duplicate `mkDefault false` would also
conflict with Plasma's `mkDefault true`.

iNiR uses the pinned `LATAR-web/inir-nixos` port and its patched iNiR source.
Only the upstream shell module and port integration module are imported, with
their own nixpkgs supplied to those module functions. This keeps Qt, Quickshell,
Python and Niri together while leaving the system package set on stable. The
port's aggregate module would also enable GDM and add global Qt/kernel settings
even for other desktop choices, so it is deliberately excluded. Our module owns
the login manager, session lifecycle, lock-screen PAM and required fonts. The
full Niri rice is validated as a store artifact and copied once to writable user
files after Home Manager removes its old managed compositor config. Later
rebuilds preserve changes made through iNiR's settings UI. See [iNiR](inir.md).

Host selection never assigns Edi's hardware to the generic `nixos` output when
local settings are absent. The personal output is explicitly `edi-nixos`.
`tests/host-selection.sh` checks both path and Git views in a temporary repository;
CI runs it outside the Nix build sandbox because it needs the Nix daemon.

## Add a feature

1. Decide if it is system-wide (drivers, services, permissions) or per-user
   (application, dotfile), or needs both.
2. For an application with no integration, add a commented package to
   `settings/applications.nix`. Do not create another one-line module.
3. For a feature needing integration, export `flake.nixosModules.NAME` and/or
   `flake.homeModules.NAME` in a new `modules/NAME.nix` file.
4. Add its explicit import in `flake.nix`, then compose it in `modules/hosts.nix`
   and/or `modules/core.nix` as appropriate. Add a typed setting and explain its
   default, permissions, ports and why it is enabled.
5. Add a meaningful evaluation assertion or behavior test and run the checks.

The existing machine's only special pieces are `settings/hosts/nixos.nix`,
`hosts/nixos/`, and the root `hardware-configuration.nix`. Generic modules contain
no Edi usernames, drive UUIDs or monitor connectors. Tests intentionally create
Alice and Bob to catch accidental coupling to Edi.

The fresh installer formats Btrfs, mounts all subvolumes before hardware detection,
and copies `scripts/fresh-machine.nix` alongside the generated hardware module.
Its local settings enable `btrfsSnapshots` and `secureBoot`; both default off for
existing profiles. `modules/recovery.nix` configures Snapper retention/scheduling
and signed Limine. Only the fresh installer enrolls firmware keys, after verifying
Setup Mode and the target EFI signature. Private keys remain in the target's
`/var/lib/sbctl`, outside all source snapshots. `tests/recovery-vm.nix` exercises
Btrfs file restoration and EFI signing in a disposable guest; mock installer tests
exercise confirmation gates, command ordering and failures without touching disks.

## References checked during the refactor

- [NixOS manual](https://nixos.org/manual/nixos/stable/): installation, native modules,
  generations and `system.stateVersion`.
- [Home Manager flakes](https://nix-community.github.io/home-manager/nix-flakes.html):
  shared nixpkgs and NixOS integration.
- [Hyprland on NixOS](https://wiki.hypr.land/Nix/Hyprland-on-NixOS/): use the NixOS
  module for compositor, portals and session integration.
- [Noctalia NixOS documentation](https://docs.noctalia.dev/noctalia/getting-started/nixos/):
  upstream NixOS/Home Manager interfaces. This repo preserves the existing pin;
  changing shell major versions requires a separate migration.
- [Caelestia upstream](https://github.com/caelestia-dots/shell): shell, CLI and Home
  Manager configuration. The pinned source was checked for IPC and module names.

The dendritic pattern is an organizational choice, not an official NixOS
requirement. Reproducibility, native option types, explicit enablement, hardware
isolation and checks provide the practical safeguards here.
