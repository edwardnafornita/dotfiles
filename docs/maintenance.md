# Updates, releases and recovery

## For friends

Open **Update System** or run `update-system`. Enter your administrator password
when requested after the build. On success, restart when convenient. If an update
fails, leave the machine running and send the maintainer the log from
`~/.local/state/dotfiles/update-*.log` (review it for private paths before sharing).

`apply-system` applies local preferences without fetching. Both commands default
to `nixos-rebuild boot`, preserving the current desktop session. Experienced users
can request immediate activation with `apply-system --switch` or
`update-system --switch`; this can restart services and affect the session.

## What the updater does

1. Verifies the checkout, its ownership and the selected update branch/origin.
2. Acquires a per-user lock so duplicate clicks cannot overlap.
3. Refuses tracked/untracked shared edits and local divergent commits. Ignored
   `settings/local/` is intentionally allowed.
4. Fetches the configured branch and performs only a fast-forward merge.
5. Snapshots the repository with `path:` so private machine settings are included.
6. Builds the chosen system with `--no-update-lock-file` from that snapshot.
7. On snapshot-enabled installs, takes root/home Snapper snapshots after a
   successful build; a snapshot failure stops activation.
8. Requests sudo to install the same immutable source snapshot as a new generation.
9. Reports success and keeps the terminal/log visible for desktop launches.

No `git reset`, automatic stash, `git pull || true`, passwordless root helper,
automatic reboot or client-side `nix flake update` is involved. A build failure
never reaches activation. A bootloader/activation failure can occur after NixOS
has started installing a generation; follow the recovery steps rather than assume
that any such failure was fully rolled back. Sources are trusted code; source
repository changes are explicit settings changes, not discovered automatically.

## Publishing an update (maintainer)

Change shared modules/bundles, preserving compatibility with old local settings.
Use defaults when adding options. Do not commit `settings/local/`. To update
package versions, update inputs deliberately on the maintainer's machine:

```bash
nix flake update nixpkgs home-manager
nix flake check path:. --no-update-lock-file
nix build path:.#nixosConfigurations.edi-nixos.config.system.build.toplevel --no-update-lock-file
```

Keep the NixOS and Home Manager release branches aligned. Review lockfile changes;
do not silently switch stable friends to unstable. Noctalia and Caelestia upgrades
need their own login/launcher/lock/unlock/screensharing tests. Build and boot the
friend Plasma profile in a disposable UEFI VM before delivering installer changes.
The GitHub Actions workflow runs the same profile, script and formatting checks
on pushes and pull requests using pinned action revisions. It does not publish or
activate systems. Test optional gaming/development bundles when those change. The automated profile
check evaluates the complete system derivations but does not build or boot all
three desktops.

Commit the configuration **and lockfile**, then push the tested branch. Friends
only need their shortcut. The updater intentionally refuses a developer checkout
with edits or local commits ahead of the remote; use `apply-system` for development.
These commands are documentation, not an instruction for automation to publish.

## Recovery

If a new generation does not boot or its desktop fails:

1. Reboot and select the previous NixOS generation in the boot menu. With
   systemd-boot, hold Space while starting; fresh installs and Edi use Limine.
2. After login, make the previous configuration the default if needed:
   `sudo nixos-rebuild switch --rollback`.
3. Ask the maintainer to push a fix, then rerun `update-system`.

To return to a known source revision without discarding current work, keep the
normal checkout intact and create a separate recovery copy/worktree. Copy the
private `settings/local/` into it before building `path:/absolute/recovery#local`.
The hardware and account configuration must travel with the shared code.

Automatic cleanup keeps at least five generations and those from the last seven
days. It is not a backup of user files or private settings. Back up personal data
and `settings/local/` independently.

## Btrfs file recovery

Fresh installations configure Snapper for both `/` and `/home`, with hourly
snapshots, root snapshots on boot and snapshots before updates. List snapshots:

```bash
sudo snapper -c root list
sudo snapper -c home list
```

Recover a specific file by copying it from the chosen read-only snapshot to its
normal location, after saving the current version if needed. For example, home
snapshot number `42` exposes `/home/alex/Documents/report.txt` at:

```text
/home/.snapshots/42/snapshot/alex/Documents/report.txt
```

Root snapshots are similarly under `/.snapshots/NUMBER/snapshot`. Snapshot
directories are accessible only to root, including old user files and system
secrets. Use `sudo` to inspect/copy and restore the destination's correct ownership.
Do not run `snapper rollback` blindly: the installer mounts explicitly named
subvolumes, and `/nix` and `/boot` are excluded. Use NixOS generations for software
rollback; filesystem snapshots do not preserve garbage-collected store paths.
Snapshots share the disk with live data and are not protection against disk loss.

Secure Boot keys are in `/var/lib/sbctl`. Back them up securely outside the machine;
never copy them into `dotfiles`, `settings/local`, Git, or the Nix store. Routine
updates sign Limine using the existing keys and enrolled config checksums; they do
not replace firmware keys. After the initial firmware toggle, check
`sudo sbctl status` to confirm Secure Boot is enabled. A successful installation
or signature check alone does not prove firmware enforcement is enabled.

## Common failures

| Symptom | Action |
| --- | --- |
| Dirty checkout | Keep/commit shared edits; use `apply-system` for local development. Put friend preferences in `settings/local`. |
| Wrong branch/origin | Check settings and Git remote. Do not reset blindly. |
| Missing `local` output | Confirm `settings/local/default.nix` exists; use a `path:` flake reference. |
| Lockfile needs updating | Maintainer must commit a complete tested lockfile; clients should not resolve new versions. |
| Home Manager backup collision | Inspect the named `.hm-backup` file; move it to a dated backup, then retry. Do not delete it without review. |
| New account cannot log in | Set its password with `sudo passwd NAME`; no passwords are embedded in the repo. |
| Low disk space | Inspect generations and logs; retain a known-working generation before cleaning. |
| Desktop icon does nothing | Try the applications-menu entry or `update-system` in a terminal to see the error. |
