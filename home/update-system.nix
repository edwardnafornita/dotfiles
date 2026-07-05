{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nh
    git
    foot
  ];

  home.file.".local/bin/update-system" = {
    executable = true;

    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      FLAKE_DIR="$HOME/dotfiles"

      echo "Updating NixOS system..."
      echo

      if [ -d "$FLAKE_DIR/.git" ]; then
        cd "$FLAKE_DIR"

        echo "Pulling latest dotfiles repo..."
        git pull --ff-only || true

        echo
        echo "Updating flake.lock..."
        nix flake update

        echo
        echo "Applying system update..."
        nh os switch
      else
        echo "Could not find flake repo at: $FLAKE_DIR"
        echo
        echo "Edit ~/.local/bin/update-system and set FLAKE_DIR correctly."
        exit 1
      fi

      echo
      echo "Cleaning old generations..."
      nh clean all --keep-since 7d --keep 5

      echo
      echo "Done. Reboot if the update changed the kernel, graphics stack, SDDM, or bootloader."
      echo
      read -rp "Press Enter to close..."
    '';
  };

  home.file.".local/share/applications/update-system.desktop".text = ''
    [Desktop Entry]
    Name=Update System
    Comment=Update NixOS and clean old generations
    Exec=foot -e update-system
    Terminal=false
    Type=Application
    Categories=System;
  '';
}
