# iNiR on this machine

Edi's profile selects `desktop = "niri"; shell = "inir";`. It installs the full
[iNiR NixOS rice](https://github.com/LATAR-web/inir-nixos), including modular Niri
configuration, panel, launcher, notifications, clipboard, wallpapers, dynamic
colors, lock screen, screenshot/OCR tools and screen recording. The port currently
pins its patched [iNiR source](https://github.com/LATAR-web/iNiR/tree/feat/nixos-port)
at version 2.33.0, derived from [snowarch/iNiR](https://github.com/snowarch/iNiR).
Both source revisions and desktop dependencies are recorded in `flake.lock`.

The host stays on its existing stable NixOS and Home Manager pins. iNiR uses its
own matching Niri, Quickshell, Qt and Python packages. The machine keeps its
hardware module, Limine Secure Boot and Windows boot entry, mounted drives,
accounts, application bundles, Korean input, and DP-2/DP-3 monitor layout. The
previous Niri shortcuts and appearance are replaced by the rice.

## Apply

From this checkout:

```bash
sudo nixos-rebuild boot --flake path:/home/edi/dotfiles#edi-nixos --no-write-lock-file
```

Restart when convenient, then select Niri in SDDM. Installing for the next boot
keeps the active desktop session running during the migration. The first Home
Manager activation backs up the remaining old Niri directory to
`~/.config/niri.before-inir-TIMESTAMP` and seeds the new rice. Home Manager removes
its old managed `config.kdl` symlink before this backup; the old system generation
still contains that configuration. Previous generations remain available in Limine.

The NixOS module starts `inir.service` with `niri.service`; the color-sync and
authentication helpers stop with the session. Do not also add `inir run` to Niri
startup. User tmpfiles deploy the shell/runtime links and theming templates at
login. The shell uses your normal account password for unlocking.

## Use

| Shortcut | Action |
| --- | --- |
| Super+Space / tap Super | Launcher and shell overview |
| Super+T / Super+Enter | Terminal selected by iNiR (initially Alacritty) |
| Super+E | Nautilus |
| Super+B / Super+W | Selected browser (Helium on Edi's machine) |
| Super+, | iNiR settings |
| Super+Shift+W | Cycle Material ii, Waffle and iRiS |
| Super+/ | Shortcut cheatsheet |
| Super+V | Clipboard history |
| Super+Shift+S | Screenshot region menu |
| Super+Alt+L | Lock |
| Ctrl+Space | English/Korean input |
| Super+Shift+E | Quit Niri |

Configure panels, wallpapers and appearance in iNiR settings. Compositor files
are writable under `~/.config/niri/config.d/`; shell preferences live under
`~/.config/illogical-impulse/config.json`. The old inactive `~/.config/inir/config.json`
is backed up and retired so the port's color helper follows that same file.
New accounts start with iRiS, the island-and-dock family featured in upstream's
main screenshot. Material ii and Waffle remain available through settings or
Super+Shift+W. To select iRiS explicitly, run `inir panelFamily set iris`.
Existing preferences survive activation.
Live wallpapers selected or downloaded through iNiR keep their video path. The
port's color-sync helper is patched to leave wallpaper selection to the shell;
video thumbnails and separate color sources only supply theme colors.

Edi's current installation also uses a user-service override at
`~/.config/systemd/user/niri-sync-colors.service.d/50-preserve-live-wallpaper.conf`,
with the patched helper retained at `~/.local/state/dotfiles/inir-color-sync`.
This activates the fix immediately and across logins without a system rebuild.
After rebuilding and booting the updated system, remove that override so future
system updates select the helper version, then reload and restart the service:

```bash
rm ~/.config/systemd/user/niri-sync-colors.service.d/50-preserve-live-wallpaper.conf
systemctl --user daemon-reload
systemctl --user restart niri-sync-colors
rm ~/.local/state/dotfiles/inir-color-sync
```

Adwaita cursor assets are included in the session's cursor search path before
Niri starts and linked into the user icon directory for iNiR's cursor picker.
The animated panel-family transition keeps upstream's Qt
crash workaround enabled.

Useful diagnostics:

```bash
systemctl --user status inir niri-sync-colors
journalctl --user -u inir -b
inir settings
inir doctor
```

`inir doctor` contains distro-specific checks; use the service journal to diagnose
actual startup failures. No Arch installer or package-manager commands are needed.

## Updates and recovery

Use `apply-system` for local repository edits. To update iNiR itself, review and
update the flake input, validate, then rebuild:

```bash
nix flake update inir-nixos
nix flake check path:. --no-update-lock-file
apply-system
```

The packaged runtime is updated through Nix. Avoid `inir update` and
`inir-sync --update`, which target upstream checkouts instead of this host flake.
The latest snowarch branch may contain changes beyond the NixOS port's pinned
version; updating that source independently requires checking the port's patches.

Existing writable Niri files survive rebuilds and input updates. To deliberately
reset them to the currently pinned rice (including changed monitor/keyboard
settings), remove `~/.config/niri/.dotfiles-inir-seeded` and run `apply-system`.
The next activation backs up the current directory before reseeding it.

To return to the previous shell, set `shell = "noctalia";` in machine settings
and rebuild. Move the writable `~/.config/niri/config.kdl` aside before activation
so Home Manager can restore its managed file. To recover from a failed login,
select the preceding system generation in Limine or use a TTY (Ctrl+Alt+F3).
