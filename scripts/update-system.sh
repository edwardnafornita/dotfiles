#!/usr/bin/env bash
# Packaged by modules/maintenance.nix. Can also be tested with explicit DOTFILES_*.
set -euo pipefail
mode=${DOTFILES_MODE:-update}
desktop=false
activation=boot
for arg in "$@"; do
  case "$arg" in
    --desktop) desktop=true ;;
    --switch) activation=switch ;;
    --help) printf '%s\n' 'update-system [--desktop] [--switch]' 'Default: install for the next boot; restart when convenient.'; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done
finish() {
  local status=$?
  if (( status != 0 )); then
    printf '\nUpdate failed. See the log above. Your current session has not been restarted.\n' >&2
  fi
  if "$desktop"; then read -r -p 'Press Enter to close...' _ || true; fi
  exit "$status"
}
trap finish EXIT
: "${DOTFILES_CHECKOUT:?Missing checkout}" "${DOTFILES_OUTPUT:?Missing profile}"
[[ $EUID != 0 ]] || { echo 'Run as your normal administrator account, without sudo.' >&2; exit 1; }
repo=$(realpath -- "$DOTFILES_CHECKOUT")
[[ -d $repo/.git && -f $repo/flake.lock ]] || { echo 'Expected a Git checkout with flake.lock.' >&2; exit 1; }
[[ $(stat -c %u "$repo") == "$EUID" ]] || { echo 'The checkout must belong to you.' >&2; exit 1; }
state=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles
mkdir -p "$state"
exec 9>"$state/update.lock"
flock -n 9 || { echo 'An update is already running.' >&2; exit 1; }
log="$state/update-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$log") 2>&1
printf 'Log: %s\n' "$log"
cd "$repo"
if [[ $mode == update ]]; then
  : "${DOTFILES_REPOSITORY:?Missing repository}" "${DOTFILES_BRANCH:?Missing branch}"
  # Never overwrite tracked edits, untracked work, or local commits.
  [[ -z $(git status --porcelain --untracked-files=normal) ]] || {
    echo 'Shared files have local changes. Commit them, or use apply-system for local work.' >&2; exit 1;
  }
  remote=$(git remote get-url origin)
  [[ ${remote%.git} == "${DOTFILES_REPOSITORY%.git}" ]] || { echo 'Origin differs from the trusted repository in settings.' >&2; exit 1; }
  [[ $(git branch --show-current) == "$DOTFILES_BRANCH" ]] || { echo 'Checkout is not on the configured update branch.' >&2; exit 1; }
  git fetch --no-tags origin "$DOTFILES_BRANCH"
  git merge-base --is-ancestor HEAD FETCH_HEAD || { echo 'Local commits diverge from the update branch; refusing to overwrite them.' >&2; exit 1; }
  git merge --ff-only FETCH_HEAD
elif [[ $mode != apply ]]; then
  echo 'Invalid update mode.' >&2; exit 2
fi
# path: includes ignored settings/local. This snapshots hardware and preferences
# together with the shared code. No live checkout is reevaluated during activation.
snapshot=$(nix flake metadata --json --no-update-lock-file "path:$repo" | jq -er .path)
flake="path:$snapshot#$DOTFILES_OUTPUT"
printf 'Building %s from commit %s\n' "$DOTFILES_OUTPUT" "$(git rev-parse --short HEAD)"
nix build --no-update-lock-file "path:$snapshot#nixosConfigurations.$DOTFILES_OUTPUT.config.system.build.toplevel" --out-link "$state/candidate"
# Build first, then request sudo. A failed build never changes boot selection.
if [[ ${DOTFILES_SNAPSHOTS:-0} == 1 ]]; then
  for snapshot_config in root home; do
    sudo "$(command -v snapper)" --no-dbus -c "$snapshot_config" create \
      --cleanup-algorithm number --description "before-$mode-system"
  done
fi
sudo "$(command -v nixos-rebuild)" "$activation" --flake "$flake" --no-write-lock-file
if [[ $activation == boot ]]; then
  echo 'Update installed. Restart when convenient to use it.'
  echo 'If it fails to boot, select the previous NixOS generation in the boot menu.'
else
  echo 'Configuration activated. A reboot may still be needed for kernel/driver changes.'
fi
