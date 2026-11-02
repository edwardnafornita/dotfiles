#!/usr/bin/env bash
# Interactive onboarding for an installed NixOS system or a UEFI live installer.
# Fresh mode intentionally has no unattended/--yes option.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:---help}
case "$mode" in
  --existing|--fresh) ;;
  --help)
    printf '%s\n' 'Usage: bash scripts/install.sh --existing | --fresh' \
      'Existing: preserve /etc/nixos, create private settings, build, then offer activation.' \
      'Fresh: from a NixOS UEFI live ISO, explicitly erase one empty/unmounted whole disk.'
    exit 0 ;;
  *) echo 'Choose --existing or --fresh. See --help.' >&2; exit 2 ;;
esac
[[ $# == 1 ]] || { echo 'Unexpected arguments.' >&2; exit 2; }
[[ -f /etc/NIXOS ]] || { echo 'Run this from NixOS or its live installer.' >&2; exit 1; }
[[ $(uname -m) == x86_64 ]] || { echo 'Only x86_64 is supported by these profiles.' >&2; exit 1; }
[[ -t 0 ]] || { echo 'This installer requires an interactive terminal.' >&2; exit 1; }
# Bootstrap tools from the committed nixpkgs input, never an arbitrary channel.
if [[ ${DOTFILES_INSTALL_TOOLS:-0} != 1 ]]; then
  export DOTFILES_INSTALL_TOOLS=1
  exec nix --extra-experimental-features 'nix-command flakes' shell \
    --inputs-from "path:$repo" --no-update-lock-file \
    nixpkgs#git nixpkgs#python3 nixpkgs#parted nixpkgs#btrfs-progs nixpkgs#sbctl \
    nixpkgs#dosfstools nixpkgs#util-linux nixpkgs#nixos-install-tools nixpkgs#nixos-rebuild \
    --command bash "$repo/scripts/install.sh" "$mode"
fi
# Commands needed by helper scripts also inherit flake support on fresh installs.
export NIX_CONFIG="${NIX_CONFIG:-}
experimental-features = nix-command flakes"
[[ ! -e $repo/settings/local ]] || { echo 'settings/local already exists; edit it and run apply-system.' >&2; exit 1; }
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null
repository=$(git -C "$repo" remote get-url origin)
branch=$(git -C "$repo" branch --show-current)
[[ -n $branch ]] || { echo 'Check out the intended update branch first.' >&2; exit 1; }
read -r -p "Login name [${SUDO_USER:-${USER:-friend}}]: " login
login=${login:-${SUDO_USER:-${USER:-friend}}}
read -r -p 'Computer name [nixos]: ' hostname
hostname=${hostname:-nixos}
read -r -p 'Timezone [America/Toronto]: ' timezone
timezone=${timezone:-America/Toronto}
read -r -p 'Keyboard layout [us]: ' keyboard
keyboard=${keyboard:-us}
read -r -p 'Desktop: plasma, niri, hyprland [plasma]: ' desktop
desktop=${desktop:-plasma}
echo 'Office, video, browser and basic tools are included.'
echo 'Optional bundles: gaming (Steam/launchers), development (.NET IDEs), media (Spotify).'
echo 'These optional bundles include proprietary software; select only licenses you accept.'
read -r -p 'Extra bundles, separated by spaces [none]: ' choices
read -r -a apps <<< "$choices"
state_version=26.05
uid=1000
extra_groups=()
if [[ $mode == --existing ]]; then
  [[ $EUID != 0 ]] || { echo 'Use your normal account, without sudo.' >&2; exit 1; }
  [[ $login == "$(id -un)" ]] || { echo 'For adoption, use the account you are logged into. Add other accounts later.' >&2; exit 1; }
  uid=$(id -u)
  # Preserve existing hardware/service memberships while making role settings authoritative.
  read -r -a current_groups <<< "$(id -nG)"
  for group in "${current_groups[@]}"; do
    case "$group" in users|wheel|networkmanager|"$(id -gn)") ;; *) extra_groups+=("$group") ;; esac
  done
  [[ $repo == "$HOME/dotfiles" ]] || { echo 'Clone this repository to ~/dotfiles first.' >&2; exit 1; }
  [[ -f /etc/nixos/configuration.nix && -f /etc/nixos/hardware-configuration.nix ]] || {
    echo 'Expected the graphical installer configuration in /etc/nixos. See docs/installation.md for custom systems.' >&2; exit 1;
  }
  [[ ! -f /etc/nixos/flake.nix ]] || { echo 'An existing flake requires manual migration; preserve its inputs and hardware modules. See docs/installation.md.' >&2; exit 1; }
  read -r -p 'Original system.stateVersion from /etc/nixos/configuration.nix (required): ' state_version
fi
# Validate every setting before touching disks or creating local configuration.
args=(--user "$login" --hostname "$hostname" --uid "$uid" --state-version "$state_version"
  --timezone "$timezone" --keyboard "$keyboard" --desktop "$desktop"
  --repository "$repository" --branch "$branch" --apps "${apps[@]}" --extra-groups "${extra_groups[@]}")
if [[ $mode == --fresh ]]; then args+=(--fresh); fi
python3 "$repo/scripts/write-local-settings.py" "${args[@]}" >/dev/null
if [[ $mode == --fresh ]]; then
  bash "$repo/scripts/install-fresh.sh" "$repo" "${args[@]}"
  exit
fi
mkdir -p "$repo/settings/local/base"
# Keep every relative import intact, including the machine's generated hardware.
cp -a /etc/nixos/. "$repo/settings/local/base/"
cat > "$repo/settings/local/machine.nix" <<'NIX'
{ ... }: {
  # Original installer configuration preserves boot, disks, GPU and firmware.
  # Move application preferences into settings over time. This file is local.
  imports = [ ./base/configuration.nix ];
}
NIX
python3 "$repo/scripts/write-local-settings.py" "${args[@]}" --destination "$repo/settings/local/default.nix"
echo 'Private configuration created in settings/local. Building before activation...'
nix build --no-update-lock-file "path:$repo#nixosConfigurations.local.config.system.build.toplevel" --out-link /tmp/dotfiles-install-result
read -r -p 'Build succeeded. Install this generation for the next reboot? [y/N] ' confirm
if [[ $confirm == y || $confirm == Y ]]; then
  sudo "$(command -v nixos-rebuild)" boot --flake "path:$repo#local" --no-write-lock-file
  echo 'Ready. Restart when convenient, then use the Update System desktop shortcut.'
else
  echo 'Nothing activated. Settings are ready for review in settings/local.'
fi
