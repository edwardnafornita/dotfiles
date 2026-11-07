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
reuse_from=''
if [[ ${1:-} == --reuse-secure-boot-from ]]; then
  [[ $# -ge 2 && -n $2 ]] || { echo 'Specify the old NixOS root partition.' >&2; exit 2; }
  reuse_from=$2
  shift 2
fi
# Temporary keys stay in the live system's /run, never the checkout or Nix store.
key_workspace=''
source_mounted=0
cleanup_keys() {
  local status=$?
  if [[ -n $key_workspace ]]; then
    if (( source_mounted )); then
      as_root umount "$key_workspace/source" || return "$status"
    fi
    as_root rm -rf -- "$key_workspace"
  fi
  return "$status"
}
trap cleanup_keys EXIT
[[ -d /sys/firmware/efi ]] || { echo 'Boot the NixOS ISO in UEFI mode. Legacy BIOS is not supported by this installer.' >&2; exit 1; }
[[ -e /iso || -e /run/iso || -d /run/initramfs/live || -e /nix/var/nix/profiles/system/iso ]] || {
  # NixOS live media has a squashfs /nix/.ro-store. Refuse installed machines.
  findmnt -rn -t squashfs -o TARGET | grep -qx /nix/.ro-store || {
    echo 'Fresh installation is only permitted from the NixOS live ISO.' >&2; exit 1;
  }
}
[[ -t 0 ]] || { echo 'An interactive terminal is required.' >&2; exit 1; }
sudo -v
# Validate firmware and keys before the first destructive operation.
if [[ -n $reuse_from ]]; then
  as_root sbctl status --json | python3 "$repo/scripts/check-secure-boot.py" reuse
  source_device=$(readlink -f -- "$reuse_from")
  [[ -b $source_device && $(lsblk -dnro TYPE "$source_device") == part ]] || {
    echo 'Key reuse requires the old NixOS root partition, not a whole disk.' >&2; exit 1;
  }
  case $(lsblk -dnro FSTYPE "$source_device") in
    btrfs) source_options=ro,nologreplay,subvol=root ;;
    ext4) source_options=ro,noload ;;
    *) echo 'Key reuse supports Btrfs (root subvolume) or ext4 root partitions.' >&2; exit 1 ;;
  esac
  key_workspace=$(as_root mktemp -d /run/dotfiles-secure-boot.XXXXXX)
  as_root mkdir "$key_workspace/source"
  as_root mount -o "$source_options" "$source_device" "$key_workspace/source"
  source_mounted=1
  as_root python3 "$repo/scripts/reuse-secure-boot.py" \
    "$key_workspace/source/var/lib/sbctl" "$key_workspace/sbctl" \
    --openssl "$(command -v openssl)" --sbctl "$(command -v sbctl)"
  # Unmount before hardware detection so the old drive never enters its output.
  as_root umount "$key_workspace/source"
  source_mounted=0
  echo 'Reusing existing Secure Boot keys. Firmware keys will not be changed.'
else
  as_root sbctl status --json | python3 "$repo/scripts/check-secure-boot.py" setup
  echo 'Secure Boot keys will be generated on the target and enrolled with Microsoft and firmware vendor certificates.'
  echo 'After installation, enable Secure Boot in your firmware menu.'
  read -r -p 'Type ENROLL SECURE BOOT KEYS to authorize enrollment for this new installation: ' enrollment
  [[ $enrollment == 'ENROLL SECURE BOOT KEYS' ]] || { echo 'Cancelled; no disk or firmware changes.'; exit 1; }
fi
printf '\nDisks (check MODEL, SIZE and SERIAL carefully):\n'
lsblk -d -o PATH,SIZE,MODEL,SERIAL,TRAN,TYPE
echo 'This whole-disk installer creates a 1 GiB EFI partition and compressed Btrfs with root/home snapshots.'
echo 'It erases every partition on the selected disk. Other disks are preserved.'
echo 'For a shared-disk dual boot or encryption, use the graphical installer.'
read -r -p 'Full target disk path (prefer /dev/disk/by-id/...): ' selected
disk=$(readlink -f -- "$selected")
[[ -b $disk && $(lsblk -dnro TYPE "$disk") == disk ]] || { echo 'Choose a whole block disk, not a partition.' >&2; exit 1; }
check_source_disk() {
  if [[ -n $reuse_from ]]; then
    local source_ancestors
    source_ancestors=$(lsblk -snrpo NAME "$source_device")
    if grep -Fxq "$disk" <<< "$source_ancestors"; then
      echo 'The target contains the old installation supplying your keys. Choose the new drive.' >&2; exit 1
    fi
  fi
}
check_source_disk
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
# Keep the source disk protected even after its read-only mount is removed.
check_source_disk
# The first destructive command is below, after all guards and exact confirmation.
as_root parted --script "$disk" mklabel gpt \
  mkpart ESP fat32 1MiB 1025MiB set 1 esp on \
  mkpart primary btrfs 1025MiB 100%
as_root partprobe "$disk"
as_root udevadm settle
suffix=''
[[ $disk =~ [0-9]$ ]] && suffix=p
efi="${disk}${suffix}1"
root="${disk}${suffix}2"
as_root mkfs.fat -F 32 "$efi"
as_root mkfs.btrfs -f "$root"
as_root mkdir -p /mnt
as_root mount -o subvolid=5 "$root" /mnt
for subvolume in root home nix snapshots home-snapshots; do
  as_root btrfs subvolume create "/mnt/$subvolume"
done
as_root umount /mnt
as_root mount -o subvol=root,compress=zstd,noatime "$root" /mnt
as_root mkdir -p /mnt/home /mnt/nix /mnt/.snapshots
as_root mount -o subvol=home,compress=zstd,noatime "$root" /mnt/home
as_root mount -o subvol=nix,compress=zstd,noatime "$root" /mnt/nix
as_root mount -o subvol=snapshots,compress=zstd,noatime "$root" /mnt/.snapshots
as_root mkdir -p /mnt/home/.snapshots
as_root mount -o subvol=home-snapshots,compress=zstd,noatime "$root" /mnt/home/.snapshots
as_root chmod 0700 /mnt/.snapshots /mnt/home/.snapshots
as_root mkdir -p /mnt/boot
as_root mount -o umask=0077 "$efi" /mnt/boot
as_root nixos-generate-config --root /mnt
# Only generated hardware is imported. No foreign-machine UUIDs enter this profile.
mkdir -p "$repo/settings/local"
as_root cp /mnt/etc/nixos/hardware-configuration.nix "$repo/settings/local/hardware-configuration.nix"
as_root chown "$(id -u):$(id -g)" "$repo/settings/local/hardware-configuration.nix"
cp "$repo/scripts/fresh-machine.nix" "$repo/settings/local/machine.nix"
if [[ -n $reuse_from ]]; then
  mv "$repo/settings/local/machine.nix" "$repo/settings/local/fresh-machine.nix"
  cat > "$repo/settings/local/machine.nix" <<'NIX'
{ lib, ... }: {
  imports = [ ./fresh-machine.nix ];
  # Missing migrated keys must fail signing rather than generate untrusted keys.
  boot.loader.limine.secureBoot.autoGenerateKeys = lib.mkForce false;
  boot.loader.limine.secureBoot.autoEnrollKeys.enable = lib.mkForce false;
  # Upstream Limine replaces an existing entry named Limine. Keep both drives
  # bootable by maintaining the fallback file and registering it separately.
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.limine.efiInstallAsRemovable = lib.mkForce true;
}
NIX
  as_root mkdir -p /mnt/var/lib
  as_root cp -a "$key_workspace/sbctl" /mnt/var/lib/
fi
python3 "$repo/scripts/write-local-settings.py" "$@" --destination "$repo/settings/local/default.nix"
# Evaluate identity from the generated settings, never execute user-entered text.
login=$(nix eval --raw --file "$repo/settings/local/default.nix" --apply 's: builtins.head (builtins.attrNames s.users)')
uid=$(nix eval --raw --file "$repo/settings/local/default.nix" --apply 's: toString (builtins.head (builtins.attrValues s.users)).uid')
as_root nixos-install --root /mnt --flake "path:$repo#local" --no-root-passwd --no-write-lock-file
# sbctl verify may return 0 for an unsigned/missing file; validate its JSON too.
limine_efi=/boot/efi/limine/BOOTX64.EFI
[[ -n $reuse_from ]] && limine_efi=/boot/efi/boot/BOOTX64.EFI
as_root nixos-enter --root /mnt -c "sbctl verify --json $limine_efi" |
  python3 "$repo/scripts/check-secure-boot.py" signed "$limine_efi"
if [[ -n $reuse_from ]]; then
  as_root efibootmgr --create --disk "$disk" --part 1 \
    --loader '\efi\boot\BOOTX64.EFI' --label 'NixOS (new drive)'
fi
as_root chmod 0700 /mnt/var/lib/sbctl
# Set an interactive password directly in the target, never in the Nix store.
echo "Set the password for $login (this account has sudo access):"
as_root nixos-enter --root /mnt -c "passwd $login"
# Carry the exact checkout and private settings into the new user's home.
as_root mkdir -p "/mnt/home/$login/dotfiles"
as_root cp -a "$repo/." "/mnt/home/$login/dotfiles/"
as_root chown -R "$uid:100" "/mnt/home/$login"
for snapshot_config in root home; do
  as_root nixos-enter --root /mnt -c "snapper --no-dbus -c $snapshot_config create --cleanup-algorithm number --description installation"
done
if [[ -z $reuse_from ]]; then
  # Recheck immediately before firmware writes; never use safety-bypass flags.
  as_root sbctl status --json | python3 "$repo/scripts/check-secure-boot.py" setup
  as_root nixos-enter --root /mnt -c 'sbctl enroll-keys --microsoft --firmware-builtin'
else
  as_root sbctl status --json | python3 "$repo/scripts/check-secure-boot.py" reuse
fi
as_root nixos-enter --root /mnt -c 'sbctl status --json' |
  python3 "$repo/scripts/check-secure-boot.py" enrolled
echo 'Installation complete. Shut down, remove the USB drive, and start the computer.'
if [[ -n $reuse_from ]]; then
  echo 'Existing firmware keys were preserved. Enable Secure Boot if temporarily disabled for the USB.'
  echo 'Test booting the new drive with the old drive disabled before removing the old installation.'
else
  echo 'In firmware settings, enable Secure Boot with the enrolled custom keys (do not restore factory keys).'
fi
echo 'After booting, run sudo sbctl status and confirm Secure Boot is enabled.'
echo 'Use Update System on the desktop for future updates. No automatic reboot was performed.'
