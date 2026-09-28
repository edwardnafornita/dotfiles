# Existing Niri + Noctalia configuration; only hardware/user assumptions are parameterized.
{
  pkgs,
  settings,
  ...
}:

let
  niriConfig = pkgs.writeText "niri-config.kdl" ''
        input {
          keyboard {
            xkb {
    	  layout "${settings.keyboardLayout}"
    	}
    	numlock
          }
          touchpad {
            tap
    	natural-scroll
          }
        }

        ${settings.niriOutputs}

        layout {
          gaps 12
          center-focused-column "on-overflow"

          default-column-width {
            proportion 0.5
          }

          focus-ring {
            width 3
    	active-color "#cba6f7"
    	inactive-color "#45475a"
          }
          
          border {
            off
          }
        }

        cursor {
          xcursor-theme "Bibata-Modern-Ice"
          xcursor-size 32
        }

        hotkey-overlay {
          skip-at-startup
        }

        window-rule {
          geometry-corner-radius 16
          clip-to-geometry true
        }

        window-rule {
          match app-id="dev.noctalia.Noctalia"
          open-floating true

          default-column-width {
            fixed 2560
          }

          default-window-height {
            fixed 1440
          }
        }

        window-rule {
          match app-id="steam" title=r#"^notificationtoasts_\d+_desktop$"#
          default-floating-position x=10 y=10 relative-to="bottom-right"
          open-focused false
        }

        window-rule {
          match app-id=r#"^steam_app_[0-9]+$"#
          open-fullscreen true
          variable-refresh-rate true
        }

        window-rule {
          match app-id="btop"
          open-focused true
          open-fullscreen true
        }

        layer-rule {
          match namespace="^noctalia-backdrop"
          place-within-backdrop true
        }

        debug {
          honor-xdg-activation-with-invalid-serial
        }

        binds {
          Mod+T {
            spawn "alacritty"
          }

          Mod+E {
            spawn "thunar"
          }

          Mod+B {
            spawn "${settings.browser}"
          }

          Mod+Shift+S hotkey-overlay-title="Screenshot Area" {
            screenshot;
          }

          Ctrl+Mod+Shift+S hotkey-overlay-title="Screenshot Monitor" {
            screenshot-screen;
          }

          Alt+Mod+Shift+S hotkey-overlay-title="Screenshot Window" {
            screenshot-window;
          }

          Mod+Alt+V {
            spawn "pavucontrol"
          }

          Ctrl+Shift+Escape repeat=false hotkey-overlay-title="Task Manager" {
            spawn "alacritty" "-e" "btop"
          }

          Mod+Space repeat=false hotkey-overlay-title="Application Launcher" {
            spawn "noctalia" "msg" "panel-toggle" "launcher";
          }

          Mod+S {
            spawn "noctalia" "msg" "panel-toggle" "control-center"
          }

          Mod+Comma {
            spawn "noctalia" "msg" "settings-toggle"
          }

          Alt+Tab {
            spawn "noctalia" "msg" "window-switcher"
          }

          Super+Alt+L {
            spawn "noctalia" "msg" "session" "lock"
          }

          Mod+O repeat=false {
            toggle-overview
          }

          Mod+Q repeat=false {
            close-window
          }

          Mod+Left { focus-column-left; }
          Mod+Down { focus-window-down; }
          Mod+Up { focus-window-up; }
          Mod+Right { focus-column-right; }

          Mod+H { focus-column-left; }
          Mod+J { focus-window-down; }
          Mod+K { focus-window-up; }
          Mod+L { focus-column-right; }

          Mod+Ctrl+Left { move-column-left; }
          Mod+Ctrl+Down { move-window-down; }
          Mod+Ctrl+Up { move-window-up; }
          Mod+Ctrl+Right { move-column-right; }

          Mod+Page_Down {
            focus-workspace-down
          }

          Mod+Page_Up {
            focus-workspace-up
          }

          Mod+Ctrl+Page_Down {
            move-column-to-workspace-down
          }

          Mod+Ctrl+Page_Up {
            move-column-to-workspace-up
          }

          Mod+R {
            switch-preset-column-width
          }

          Mod+F {
            maximize-column
          }

          Mod+Shift+F {
            fullscreen-window
          }

          Mod+V {
            toggle-window-floating
          }

          Mod+Minus {
            set-column-width "-10%"
          }

          Mod+Equal {
            set-column-width "+10%"
          }

          XF86AudioRaiseVolume allow-when-locked=true {
            spawn "noctalia" "msg" "volume-up"
          }

          XF86AudioLowerVolume allow-when-locked=true {
            spawn "noctalia" "msg" "volume-down"
          }

          XF86AudioMute allow-when-locked=true {
            spawn "noctalia" "msg" "volume-mute"
          }

          XF86MonBrightnessUp allow-when-locked=true {
            spawn "noctalia" "msg" "brightness-up"
          }

          XF86MonBrightnessDown allow-when-locked=true {
            spawn "noctalia" "msg" "brightness-down"
          }

          XF86AudioPlay {
            spawn "playerctl" "play-pause"
          }

          XF86AudioPrev {
            spawn "playerctl" "previous"
          }

          XF86AudioNext {
            spawn "playerctl" "next"
          }

          Print {
            screenshot
          }

          Ctrl+Print {
            screenshot-screen
          }

          Alt+Print {
            screenshot-window
          }

          Mod+Shift+P {
            power-off-monitors
          }

          Mod+Shift+E {
            quit
          }
        }
  '';
  cursorSize = 32;
  cursorTheme = "Bibata-Modern-Ice";
in
{
  home.packages = with pkgs; [
    alacritty # Terminal launched by Mod+T.
    wl-clipboard # Wayland clipboard utilities.
    playerctl # Media key commands.
    brightnessctl # Brightness controls for supported displays.
  ];

  home.pointerCursor = {
    enable = true;

    package = pkgs.bibata-cursors; # Preserve the existing pointer appearance.
    name = cursorTheme;
    size = cursorSize;

    gtk.enable = true; # Apply cursor/theme integration to GTK applications.
    x11.enable = true;
  };

  home.sessionVariables = {
    XCURSOR_THEME = cursorTheme;
    XCURSOR_SIZE = toString cursorSize;
  };

  dconf.settings."org/gnome/desktop/interface" = {
    cursor-theme = cursorTheme;
    cursor-size = cursorSize;
  };

  gtk.enable = true; # Apply cursor/theme integration to GTK applications.

  xdg.configFile."niri/config.kdl".source =
    pkgs.runCommand "niri-config-checked"
      {
        nativeBuildInputs = [ pkgs.niri ]; # Reject invalid compositor syntax at build time.
      }
      ''
        niri validate --config ${niriConfig}
        cp ${niriConfig} $out
      '';
}
