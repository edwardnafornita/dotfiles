{
  config,
  lib,
  pkgs,
  inputs,
  settings,
  ...
}:
let
  defaults = builtins.fromJSON (
    builtins.readFile "${inputs.inir-nixos.inputs.inir}/defaults/config.json"
  );
  preferences = pkgs.writeText "inir-initial-config.json" (
    builtins.toJSON (
      defaults
      // {
        panelFamily = "iris";
        appearance = defaults.appearance // {
          iconTheme = "Papirus-Dark"; # Installed by the port; WhiteSur is not.
        };
        apps = defaults.apps // {
          browser = settings.browser;
          terminal = "alacritty";
        };
      }
    )
  );
  seed = pkgs.writeShellApplication {
    name = "seed-inir-rice";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
    ];
    text = builtins.readFile ../scripts/seed-inir.sh;
  };
in
{
  # The color-sync helper rewrites these files when changing light/dark mode.
  # Fcitx's GTK integration remains enabled through the shared input module.
  xdg.configFile."gtk-3.0/settings.ini".enable = lib.mkForce false;
  xdg.configFile."gtk-4.0/settings.ini".enable = lib.mkForce false;

  # iNiR edits Niri files and generated themes from its settings GUI. Seed once
  # instead of installing read-only Home Manager symlinks over those files.
  home.activation.seedInirRice = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe seed} ${
      lib.escapeShellArgs [
        "${config.xdg.configHome}/niri"
        "${config.home.homeDirectory}/.local/share/dotfiles/inir-niri"
        config.home.homeDirectory
      ]
    }
    run ${pkgs.python3}/bin/python3 ${../scripts/seed-inir-preferences.py} ${
      lib.escapeShellArgs [
        config.xdg.configHome
        "${preferences}"
      ]
    }
  '';
}
