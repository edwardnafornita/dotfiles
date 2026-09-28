#!/usr/bin/env bash
# Integration regression: Git sources omit ignored local settings, path sources include them.
# Run outside a Nix build sandbox (requires Nix's daemon). No real checkout is modified.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
checkout="$tmp/repo"
mkdir -p "$checkout"
tar --exclude='./.git' --exclude='./settings/local' --exclude='./result*' -C "$repo" -cf - . |
  tar -C "$checkout" -xf -
git -C "$checkout" init -q
git -C "$checkout" add .
git -C "$checkout" -c user.name=Test -c user.email=test@example.invalid commit -qm 'Regression fixture'

# Without local settings, no generic hostname/default/local alias may select Edi.
for source in "path:$checkout" "git+file://$checkout"; do
  nix eval --json --no-update-lock-file "$source#nixosConfigurations" --apply '
    configs: assert builtins.attrNames configs == [ "edi-nixos" ]; true'
done

mkdir -p "$checkout/settings/local"
cat > "$checkout/settings/local/default.nix" <<'NIX'
{
  hostname = "nixos"; # A common hostname must not select the maintainer's hardware.
  machineModule = ../../tests/machine.nix;
  users.friend.admin = true;
}
NIX
# The supported path source sees the friend, including the hostname alias.
nix eval --json --no-update-lock-file "path:$checkout#nixosConfigurations" --apply '
  configs:
    let c = configs.local.config; alias = configs.nixos.config;
    in assert builtins.attrNames configs == [ "local" "nixos" ];
       assert c.users.users ? friend && !(c.users.users ? edi);
       assert c.fileSystems."/".device == "/dev/disk/by-label/test-root";
       assert alias.users.users ? friend;
       assert alias.fileSystems."/".device == c.fileSystems."/".device;
       true'
# Git hides that file. A generic rebuild must fail, never fall back to Edi's disks.
for output in nixos local; do
  if nix eval --no-update-lock-file "git+file://$checkout#nixosConfigurations.$output.config.networking.hostName" > "$tmp/error" 2>&1; then
    echo "Unexpected Git fallback for $output" >&2
    exit 1
  fi
  grep -q 'does not provide attribute' "$tmp/error"
done
echo 'Host selection passed for path and Git sources.'
