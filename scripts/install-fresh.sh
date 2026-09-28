#!/usr/bin/env bash
# Called by install.sh after collecting and validating preferences.
set -euo pipefail
# Resolve tools before sudo resets PATH, preserving the pinned bootstrap binaries.
as_root() {
  local executable
  executable=$(command -v "$1")
  shift
  sudo "$executable" "$@"
}
repo=${1:?Run scripts/install.sh --fresh}
shift
[[ -d /sys/firmware/efi ]] || { echo 'Boot the NixOS ISO in UEFI mode. Legacy BIOS is not supported by this installer.' >&2; exit 1; }
[[ -e /iso || -e /run/iso || -d /run/initramfs/live || -e /nix/var/nix/profiles/system/iso ]] || {
  # NixOS live media has a squashfs /nix/.ro-store. Refuse installed machines.
  findmnt -rn -t squashfs -o TARGET | grep -qx /nix/.ro-store || {
    echo 'Fresh installation is only permitted from the NixOS live ISO.' >&2; exit 1;
  }
}
[[ -t 0 ]] || { echo 'An interactive terminal is required.' >&2; exit 1; }
sudo -v
printf '\nDisks (check MODEL, SIZE and SERIAL carefully):\n'
lsblk -d -o PATH,SIZE,MODEL,SERIAL,TRAN,TYPE
echo 'This whole-disk installer creates a 1 GiB EFI partition and an ext4 root.'
echo 'It does not preserve Windows, existing partitions or data. Use the graphical installer for dual boot or encryption.'
read -r -p 'Full target disk path (prefer /dev/disk/by-id/...): ' selected
disk=$(readlink -f -- "$selected")
[[ -b $disk && $(lsblk -dnro TYPE "$disk") == disk ]] || { echo 'Choose a whole block disk, not a partition.' >&2; exit 1; }
# Refuse mounted filesystems, active swap, mapped/encrypted devices, and the ISO disk.
python3 "$repo/scripts/check-install-disk.py" "$disk"
while read -r device; do
  if [[ -n $(ls -A "/sys/class/block/$(basename "$device")/holders") ]]; then
    echo 'A partition has active device-mapper/RAID holders. Refusing to erase it.' >&2; exit 1
  fi
  if swapon --noheadings --raw --show=NAME | grep -Fxq "$device"; then
    echo 'The disk contains active swap. Refusing to erase it.' >&2; exit 1
  fi
done < <(lsblk -nrpo NAME "$disk")
mountpoint -q /mnt && { echo '/mnt is already mounted; refusing to reuse it.' >&2; exit 1; }
[[ -z $(ls -A /mnt 2>/dev/null) ]] || { echo '/mnt is not empty.' >&2; exit 1; }
lsblk -o PATH,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS "$disk"
read -r -p "Type ERASE $disk to permanently erase this entire disk: " confirmation
[[ $confirmation == "ERASE $disk" ]] || { echo 'Cancelled; no disk changes.'; exit 1; }
# Recheck mount/swap/mapper state immediately before the first destructive command.
python3 "$repo/scripts/check-install-disk.py" "$disk"
# The first destructive command is below, after all guards and exact confirmation.
as_root parted --script "$disk" mklabel gpt \
  mkpart ESP fat32 1MiB 1025MiB set 1 esp on \
  mkpart primary ext4 1025MiB 100%
as_root partprobe "$disk"
as_root udevadm settle
suffix=''
[[ $disk =~ [0-9]$ ]] && suffix=p
efi="${disk}${suffix}1"
root="${disk}${suffix}2"
as_root mkfs.fat -F 32 "$efi"
as_root mkfs.ext4 -F "$root"
as_root mkdir -p /mnt
as_root mount "$root" /mnt
as_root mkdir -p /mnt/boot
as_root mount "$efi" /mnt/boot
as_root nixos-generate-config --root /mnt
# Only generated hardware is imported. No foreign-machine UUIDs enter this profile.
mkdir -p "$repo/settings/local"
as_root cp /mnt/etc/nixos/hardware-configuration.nix "$repo/settings/local/hardware-configuration.nix"
as_root chown "$(id -u):$(id -g)" "$repo/settings/local/hardware-configuration.nix"
cat > "$repo/settings/local/machine.nix" <<'NIX'
{ ... }: {
  imports = [ ./hardware-configuration.nix ];
  boot.loader.systemd-boot.enable = true; # Standard UEFI bootloader for fresh installs.
  boot.loader.efi.canTouchEfiVariables = true; # Register the boot entry in firmware.
  zramSwap.enable = true; # Compressed RAM swap without another disk partition.
}
NIX
python3 "$repo/scripts/write-local-settings.py" "$@" --destination "$repo/settings/local/default.nix"
# Evaluate identity from the generated settings, never execute user-entered text.
login=$(nix eval --raw --file "$repo/settings/local/default.nix" --apply 's: builtins.head (builtins.attrNames s.users)')
uid=$(nix eval --raw --file "$repo/settings/local/default.nix" --apply 's: toString (builtins.head (builtins.attrValues s.users)).uid')
as_root nixos-install --root /mnt --flake "path:$repo#local" --no-root-passwd --no-write-lock-file
# Set an interactive password directly in the target, never in the Nix store.
echo "Set the password for $login (this account has sudo access):"
as_root nixos-enter --root /mnt -c "passwd $login"
# Carry the exact checkout and private settings into the new user's home.
as_root mkdir -p "/mnt/home/$login/dotfiles"
as_root cp -a "$repo/." "/mnt/home/$login/dotfiles/"
as_root chown -R "$uid:100" "/mnt/home/$login"
echo 'Installation complete. Shut down, remove the USB drive, and start the computer.'
echo 'Use Update System on the desktop for future updates. No automatic reboot was performed.'
