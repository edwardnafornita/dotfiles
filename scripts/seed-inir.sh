#!/usr/bin/env bash
# Install a writable rice once; later rebuilds preserve changes from iNiR's GUI.
set -euo pipefail

config_dir="$1"
source_dir="$2"
user_home="$3"

if [[ -e "$config_dir/.dotfiles-inir-seeded" ]]; then
  exit 0
fi

# Check the source before moving any existing user files.
test -f "$source_dir/config.kdl"
test -f "$source_dir/config.d/40-environment.kdl"
if [[ -e "$config_dir" || -L "$config_dir" ]]; then
  backup="$config_dir.before-inir-$(date +%Y%m%d-%H%M%S-%N)"
  mv "$config_dir" "$backup"
  echo "Previous Niri configuration saved to $backup"
fi
mkdir -p "$config_dir"
cp -rL "$source_dir/." "$config_dir/"
chmod -R u+w "$config_dir"
# Niri's environment block takes literal strings, so resolve $HOME explicitly.
# shellcheck disable=SC2016
sed -i 's|\$HOME|'"$user_home"'|g' "$config_dir/config.d/40-environment.kdl"
touch "$config_dir/.dotfiles-inir-seeded"
