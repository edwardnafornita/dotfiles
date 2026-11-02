# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single flake-parts NixOS configuration shared between the maintainer's
machine and friends' computers. One pinned, shared configuration; each
computer supplies its own hardware and account settings. Read `README.md`
first — it is the canonical entry point and task-to-file table.

## Commands

```bash
# Evaluate all desktop/account profiles, validate compositor configs, test installer/updater scripts
nix flake check path:. --no-update-lock-file --print-build-logs

# Host-selection behavior (path vs. Git source, local settings) — needs the Nix daemon, run outside the build sandbox
bash tests/host-selection.sh

# Build the maintainer's own system (sanity build before pushing)
nix build path:.#nixosConfigurations.edi-nixos.config.system.build.toplevel --no-update-lock-file
# on a friend's checkout, use .local instead of .edi-nixos

# Format all *.nix (never hardware-configuration.nix, which is machine-generated)
nix run path:.#formatter.x86_64-linux -- --write $(find . -name '*.nix' -not -path './.git/*' -not -name hardware-configuration.nix)

# Run just the Python installer/updater unit tests
python3 -m unittest discover -s tests -v

# Shell script syntax/lint only
shellcheck scripts/*.sh tests/*.sh
bash -n scripts/install.sh scripts/install-fresh.sh scripts/update-system.sh
```

Always use `path:.` rather than a bare flake path for local builds/checks:
Git flakes silently omit untracked files and the git-ignored
`settings/local/`, which changes which `nixosConfigurations` outputs exist.

CI (`.github/workflows/check.yml`) runs exactly: `nix flake check`,
`tests/host-selection.sh`, and the formatter in `--check` mode, on pushes and
PRs to `main`. There is no separate lint/typecheck step — formatting and the
flake checks are the whole gate.

## Architecture

Flake-parts module composition, following a "dendritic" pattern (feature
modules export both NixOS and Home Manager config from one file; no
implicit/automatic imports — see `docs/architecture.md` for the full
rationale and upstream references):

```
flake.nix (explicit imports only — adding a file never auto-enables it)
  modules/hosts.nix        -> self.lib.mkSystem: evalModules settings + lib.nixosSystem
    settings/options.nix + settings/defaults.nix   (typed schema, lib.evalModules)
    settings/hosts/nixos.nix  OR  settings/local/default.nix   (per-machine values; local/ is git-ignored)
      machineModule (per-machine hardware/bootloader/storage)
      modules/core.nix         -> accounts, Home Manager wiring, network/audio/printing
      modules/applications.nix -> package bundles, gaming integration, dev shell
      modules/desktop.nix       -> selected login session + desktop services
        desktops/{plasma,niri,hyprland}.nix -> compositor/session config
        shells/{noctalia,caelestia}.nix     -> shell appearance (Niri/Hyprland only)
      modules/maintenance.nix  -> generation cleanup, update-system/apply-system commands
  modules/checks.nix        -> flake checks (evaluates sample profiles, verifies configs, runs scripts/tests)
```

Key invariants (see `docs/architecture.md` for why):
- `settings` is validated once via `lib.evalModules` before being threaded into
  NixOS/Home Manager as `specialArgs`. A typo or unsupported value fails
  evaluation rather than being silently ignored.
- A module being imported only *declares* options; it never *enables* a
  service by itself — enablement is gated by settings (`mkIf`).
- The maintainer's own machine is never the fallback: `settings/local/default.nix`
  absent -> only `edi-nixos` exists as an output. Present -> outputs are `local`
  and that machine's hostname. This is deliberately asymmetric so a friend's
  Git checkout (which omits ignored `local/`) can never resolve to the
  maintainer's disks.
- Generic modules (`modules/`, `desktops/`, `shells/`) must stay free of the
  maintainer's username, drive UUIDs or monitor connectors. Only
  `settings/hosts/nixos.nix`, `hosts/nixos/`, and the root
  `hardware-configuration.nix` are maintainer-specific. `modules/checks.nix`
  intentionally builds profiles for synthetic `alice`/`bob` accounts to catch
  accidental coupling to the maintainer.
- nixpkgs/home-manager stay on the same pinned stable release; Noctalia and
  Caelestia intentionally keep their own separate upstream pins (newer
  Qt/Quickshell deps) — do not casually unify these in `flake.nix`.

## Adding a feature

Per `docs/architecture.md`: decide system-wide vs. per-user vs. both. A bare
package with no integration goes as a commented entry in
`settings/applications.nix` — don't create a one-line module for it. A
feature needing real integration gets `flake.nixosModules.NAME` /
`flake.homeModules.NAME` in a new `modules/NAME.nix`, wired into `flake.nix`'s
import list and composed from `modules/hosts.nix`/`modules/core.nix`. Add a
typed option (with its default and rationale) and a check/assertion in
`modules/checks.nix`.

## Settings vs. implementation

`settings/options.nix`/`settings/defaults.nix` define the typed schema and
repo-wide defaults; `settings/hosts/nixos.nix` and (git-ignored, installer-
generated) `settings/local/default.nix` are the only places per-machine
*values* belong. `settings/README.md` documents every option, its default,
and why. Don't hardcode machine-specific values in `modules/`.
