{ inputs, ... }: {
  flake.homeModules.input-method =
    {
      config,
      lib,
      pkgs,
      settings,
      account,
      osConfig,
      ...
    }:
    let
      plasma = settings.desktop == "plasma";
    in
    {
      imports = [ inputs.helium.homeModules.default ];

      config = lib.mkIf account.koreanInput {
        i18n.inputMethod = {
          enable = true;
          type = "fcitx5";
          fcitx5 = {
            # The HM module supplies a graphical-session user service and GTK/Qt plugins.
            addons = [ pkgs.fcitx5-hangul ];
            waylandFrontend = !plasma;
            settings = {
              globalOptions = {
                Behavior = {
                  ActiveByDefault = false;
                  ShareInputState = "All";
                };
                Hotkey.EnumerateWithTriggerKeys = false;
                "Hotkey/TriggerKeys" = {
                  "0" = "Control+space";
                  "1" = "Hangul"; # The dedicated 한/영 key on Korean keyboards.
                };
                # Avoid accidental language changes on Shift and leave Super+Space for the launcher.
                "Hotkey/AltTriggerKeys"."0" = "";
                "Hotkey/EnumerateGroupForwardKeys"."0" = "";
                "Hotkey/EnumerateGroupBackwardKeys"."0" = "";
              };
              inputMethod = {
                GroupOrder."0" = "Default";
                "Groups/0" = {
                  Name = "Default";
                  "Default Layout" = "us";
                  DefaultIM = "hangul";
                };
                "Groups/0/Items/0" = {
                  Name = "keyboard-us";
                  Layout = "";
                };
                "Groups/0/Items/1" = {
                  Name = "hangul";
                  Layout = "us";
                };
              };
              addons.hangul.globalSection.Keyboard = "Dubeolsik";
            };
          };
        };

        gtk.enable = true; # HM configures X11 GTK plugins while native Wayland GTK uses text-input-v3.
        home.sessionVariables = lib.mkIf (!plasma) {
          QT_IM_MODULE = "fcitx"; # Qt5 compatibility outside KWin.
          QT_IM_MODULES = "wayland;fcitx"; # Modern Qt6 prefers native Wayland input.
        };
        home.sessionSearchVariables.QT_PLUGIN_PATH = [
          "${pkgs.libsForQt5.fcitx5-qt}/${pkgs.libsForQt5.qtbase.qtPluginPrefix}"
        ];
        # Niri and panel-launched applications inherit the systemd user environment.
        systemd.user.sessionVariables =
          lib.filterAttrs (
            name: _:
            builtins.elem name [
              "GLFW_IM_MODULE"
              "SDL_IM_MODULE"
              "XMODIFIERS"
              "GTK_IM_MODULE"
              "QT_IM_MODULE"
              "QT_IM_MODULES"
            ]
          ) config.home.sessionVariables
          // {
            QT_PLUGIN_PATH = lib.concatStringsSep ":" config.home.sessionSearchVariables.QT_PLUGIN_PATH;
          };

        # A user package also supplies its own desktop entry, so menu and Mod+B launches agree.
        programs.helium = lib.mkIf (settings.browser == "helium") {
          enable = true;
          package = osConfig.programs.helium.package;
          flags = osConfig.programs.helium.flags ++ [
            "--enable-wayland-ime"
            "--wayland-text-input-version=${if plasma then "1" else "3"}"
          ];
        };
      };
    };
}
