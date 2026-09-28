{ ... }: {
  flake.nixosModules.maintenance = { lib, settings, ... }: {
    programs.nh = {
      enable = true; # Optional interactive rebuild/diff tool retained for Edi.
      # No implicit Git flake: it would omit settings/local. Use apply-system,
      # or pass nh an explicit path: source and hostname selection.
      clean = {
        enable = true; # Bound store growth while retaining rollback generations.
        extraArgs = "--keep-since 7d --keep 5";
      };
    };
    # Expose the selected output for diagnostics; never store credentials here.
    environment.etc."dotfiles-profile".text = settings.updates.output + "\n";
  };
  flake.homeModules.maintenance =
    {
      config,
      lib,
      pkgs,
      settings,
      account,
      ...
    }:
    let
      command =
        name: mode:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            git # Fetch reviewed updates and require a fast-forward.
            nix # Evaluate and build the exact locked source snapshot.
            nixos-rebuild # Install a system generation using NixOS's supported command.
            jq # Read snapshot metadata without fragile text parsing.
            coreutils # Paths, directories, timestamps and logging utilities.
            util-linux # flock prevents simultaneous update operations.
          ];
          text = ''
            export DOTFILES_REPOSITORY=${lib.escapeShellArg settings.updates.repository}
            export DOTFILES_BRANCH=${lib.escapeShellArg settings.updates.branch}
            export DOTFILES_CHECKOUT=${lib.escapeShellArg "${config.home.homeDirectory}/${settings.updates.checkout}"}
            export DOTFILES_OUTPUT=${lib.escapeShellArg settings.updates.output}
            export DOTFILES_MODE=${mode}
            ${builtins.readFile ../scripts/update-system.sh}
          '';
        };
      update = command "update-system" "update";
      apply = command "apply-system" "apply";
      # Select an actually installed terminal. Both support -e; absolute paths
      # work even before a desktop has learned the user's preferred terminal.
      terminal =
        if settings.desktop == "plasma" then
          "${pkgs.kdePackages.konsole}/bin/konsole" # Plasma terminal.
        else
          "${pkgs.alacritty}/bin/alacritty"; # Compositor terminal.
      desktopFile = pkgs.writeText "update-system.desktop" ''
        [Desktop Entry]
        Type=Application
        Name=Update System
        Comment=Install the latest reviewed system update, then restart when convenient
        Exec=${terminal} -e ${update}/bin/update-system --desktop
        Icon=system-software-update
        Terminal=false
        Categories=System;
      '';
    in
    {
      home.packages = lib.optionals account.admin [
        update
        apply
      ]; # Only administrators perform system updates.
      # Applications-menu entry plus a real Desktop shortcut using the selected terminal.
      xdg.dataFile."applications/update-system.desktop" = lib.mkIf account.admin {
        source = desktopFile;
      };
      home.file."${config.xdg.userDirs.desktop}/Update System.desktop" = lib.mkIf account.admin {
        source = desktopFile;
        executable = true;
      };
      home.activation.screenshotDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Pictures/Wallpapers"
      ''; # Destination for screenshots and shell wallpaper selection.
    };
}
