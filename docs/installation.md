# Installation

## What the installer supports

- NixOS on x86_64 PCs, using the committed stable package set.
- An existing graphical-installer NixOS configuration in `/etc/nixos`.
- A fresh UEFI installation on an explicitly selected whole disk, at least 32 GiB.
- Plasma by default, with Niri/Noctalia and Hyprland/Caelestia as opt-in choices. Hyprland can
  instead use Noctalia by setting `shell = "noctalia"` in the generated settings.
- Account, hostname, timezone, keyboard and application-bundle prompts.

An internet connection is required. Initial downloads, particularly gaming and
IDE bundles, can be large. The initial clone command may use the ISO's nixpkgs
registry; the installer itself resolves tools through this repository's lockfile.

## Existing NixOS, easiest route for friends

Use the [official graphical installer](https://nixos.org/manual/nixos/stable/#sec-installation-graphical)
first. It can guide disk layout, encryption and desktop/user creation. Boot the
installed system, connect to the internet, and open a terminal as your normal
administrator account:

```bash
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git
git clone https://github.com/edwardnafornita/dotfiles.git ~/dotfiles
cd ~/dotfiles
bash scripts/install.sh --existing
```

Use your current username. The script asks for the original `system.stateVersion`
from `/etc/nixos/configuration.nix`; this is a compatibility value, not today's
release. It copies the entire original configuration into `settings/local/base/`
so relative imports, hardware, encrypted disks, GPU settings and bootloader remain
available. Passwords are preserved. It builds the new system before offering to
install a generation for the next reboot. The running desktop stays in place.

The copied original module still contributes settings, installed packages and
accounts. The selected desktop takes priority over Plasma/GNOME/SDDM/GDM defaults.
When moving preferences into the new settings, remove duplicate preferences from
the **copied** local base, leaving its boot/hardware settings intact. Any unresolved
module conflicts stop the build before activation. Other existing desktop managers
or heavily customized modules need a manual review; this is not a universal
migration tool. Existing `/etc/nixos/flake.nix` setups are deliberately refused
because silently dropping their inputs would lose machine-specific configuration.

If creating local settings succeeds but a later build fails, do not rerun the
installer or delete hardware files. Fix the reported conflict, then use:

```bash
nix build --no-update-lock-file path:.#nixosConfigurations.local.config.system.build.toplevel
sudo nixos-rebuild boot --flake path:.#local --no-write-lock-file
```

The installation scripts never overwrite an existing `settings/local` directory.
Back it up separately: Git intentionally does not contain it. Copied Nix source
must not contain secrets; use external password files/secret management if the
original system already does so.

## Fresh whole-disk installation

This mode **erases all data on the selected disk**. It creates a GPT partition
table, a 1 GiB FAT32 EFI partition and Btrfs using the rest of the disk. Separate
`root`, `home`, and `nix` subvolumes use Zstd compression and `noatime`. Separate
`snapshots` and `home-snapshots` subvolumes mount at `/.snapshots` and
`/home/.snapshots`, with root-only access. `/boot` has restrictive permissions.
Compressed RAM swap remains enabled; disk encryption and hibernation are not
configured. For encryption or Windows dual boot, use the graphical installer
followed by the existing-install route above. Adoption preserves that install's
storage/boot configuration; it does not automatically enable these fresh-install
features. Edi's existing boot and disk configuration is independent.

Fresh installs use **Limine with Secure Boot signing and enrolled configuration
checksums**, rather than systemd-boot. Before starting, disable Secure Boot and
enter **UEFI Setup Mode** for custom-key enrollment. Disabling Secure Boot alone
is insufficient. Firmware calls this Reset to Setup Mode, Delete Platform Key,
or a similar device-specific action. Back up any existing firmware keys and
recovery information first; do not reset keys on a machine whose existing boot
setup you intend to keep.

The installer checks Setup Mode before formatting, asks for explicit enrollment
authorization, generates keys inside the target's `/var/lib/sbctl`, and verifies
the installed Limine signature. It then enrolls the target keys with Microsoft
and firmware vendor certificates. It does not use safety-bypass flags or enroll
keys again during routine updates. Keys never enter the checkout or Nix store.
If signature verification, initial snapshots or enrollment fail, the installer
stops without reporting success; inspect the mounted target instead of rerunning
formatting. Keep Secure Boot disabled until the failure is resolved.

1. Back up the target computer. Prepare firmware Setup Mode as described above,
   then boot the official x86_64 NixOS live ISO in UEFI mode.
2. Connect to the internet. Open a terminal and clone the repository using the
   commands above. Do not launch the graphical installer at the same time.
3. Run `bash scripts/install.sh --fresh`.
4. Enter the account and software choices. Authorize Secure Boot key enrollment
   with the exact phrase shown. Review the disk table, including serial
   number/model/size. Enter a whole-disk path, preferably `/dev/disk/by-id/...`.
5. Type the exact `ERASE /dev/...` phrase shown. Any different response cancels.
6. Wait for formatting, hardware detection, downloads and installation. Set the
   administrator password when prompted; it is written directly inside the new
   installation, never into a Nix expression or Git.
7. Shut down, remove the USB drive, and enable **Secure Boot** in firmware using
   the enrolled custom keys. Do not restore factory keys over the newly enrolled
   keys. Start the machine and check `sudo sbctl status`: Secure Boot should be
   enabled and Setup Mode disabled. No automatic reboot occurs.

Snapper takes initial snapshots during installation, a root snapshot on boot,
hourly root/home snapshots, and root/home snapshots before `apply-system` or
`update-system` activates a built configuration. Daily cleanup retains up to
6 hourly, 7 daily, 4 weekly and 3 monthly timeline snapshots, plus 10 numbered
snapshots per config (subject to Snapper's minimum age). Monthly Btrfs scrubs
check filesystem integrity. `/nix` and `/boot` are outside root snapshots:
NixOS boot generations remain the mechanism for reverting installed software.
See [snapshot recovery](maintenance.md#btrfs-file-recovery) for restoring files.

The installer refuses disks with mounted children, active swap or device-mapper
holders, rejects partitions instead of whole disks, and refuses an occupied
`/mnt`. It only runs from live media. There is no unattended erase switch. It
leaves mounts intact if installation fails so a knowledgeable user can inspect
and resume; never rerun formatting just to recover from a download failure.

## Custom hardware and manual migration

For an existing flake/custom boot stack, retain that stack as a local machine
module, including any inputs it needs. Create `settings/local/default.nix` using
the [settings example](../settings/README.md) and set `machineModule` to that
module. Do not import `hosts/nixos` or copy Edi's generated hardware file.
Evaluate and build before choosing `nixos-rebuild boot --flake path:.#local`.

NVIDIA hybrid graphics, unusual firmware and proprietary drivers may need explicit
hardware modules. The installer preserves such settings on existing systems but
does not guess them on fresh installs. Run a disposable UEFI VM installation and
then a hardware-specific smoke test before recommending the image/profile to a
friend. A successful Nix evaluation cannot prove the physical machine boots.

## After installation

- **Update System** appears on the Desktop and in the applications menu for admins.
  Plasma may ask to trust/execute the launcher once. Niri/Hyprland do not render
  desktop icons; use the launcher entry or run `update-system` in a terminal.
- Edit `~/dotfiles/settings/local/default.nix` for desktop/users/application choices.
  Run `apply-system` and reboot when convenient.
- Plasma Discover (or GNOME Software in compositor sessions) can manage Flatpak.
  To enable Flathub per user, run
  `flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo`.
  It is not automatically added: choosing a separate application source is explicit.
  Flatpak apps/data update separately from `update-system`.

## Installer tools

The bootstrap shell uses the locked nixpkgs versions of Git (checkout/update),
Python (settings serialization, disk checks and Secure Boot JSON validation),
parted/partprobe (partition table creation and kernel rescan), dosfstools (EFI FAT
filesystem), btrfs-progs (root filesystem and subvolumes), sbctl (firmware status), util-linux
(block-device inspection and mounts), and nixos-install-tools (hardware detection,
installation and entering the installed system), and nixos-rebuild (installing
a built generation on an existing system). Privileged commands use resolved
absolute paths so sudo cannot silently select different tools. Only fresh mode formats disks;
existing mode only copies configuration and builds until you accept activation.
