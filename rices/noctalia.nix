{ inputs, pkgs, ... }:

let
  niriConfig = pkgs.writeText "niri-config.kdl" ''
    input {
      keyboard {
        xkb {
	  layout "us"
	}
	numlock
      }
      touchpad {
        tap
	natural-scroll
      }
    }
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

    layer-rule {
      match namespace="^noctalia-backdrop"
      place-within-backdrop true
    }

    debug {
      honor-xdg-activation-with-invalid-serial
    }

    binds {
      Mod+Return {
        spawn "alacritty"
      }

      Mod+Space {
        spawn "noctalia" "msg" "panel-toggle" "launcher"
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
in
{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  programs.noctalia = {
    enable = true;
    validateConfig = true;

    settings = {
      shell = {
        polkit_agent = true;
	settings_show_advanced = true;

	panel = {
	  transparency_mode = "glass";
	  borders = true;
	  shadow = true;
	  launcher_placement = "centered";
	  clipboard_placement = "centered";
	  control_center_placement = "attached";
	};
      };

      theme = {
        mode = "dark";
	source = "builtin";
	builtin = "Noctalia";
      };

      backdrop = {
        enabled = true;
	blur_intensity = 0.35;
	tint_intensity = 0.25;
      };

      wallpaper = {
        enabled = true;
	directory = "~/Pictures/Wallpapers";
	fill_mode = "crop";
      };

      notification.enable_daemon = true;
      lockscreen.enabled = true;

      bar.main = {
        position = "top";
	thickness = 36;
	background_opacity = 0.92;
	radius = 12;
	margin_h = 12;
	margin_v = 10;
	padding = 12;
	widget_spacing = 6;
	shadow = true;
	reserve_space = true;

	start = [
	  "launcher"
	  "wallpaper"
	  "workspaces"
	];

	center = [
	  "clock"
	];

	end = [
	  "media"
	  "tray"
	  "notifications"
	  "clipboard"
	  "network"
	  "bluetooth"
	  "volume"
	  "brightness"
	  "battery"
	  "control-center"
	  "session"
	];
      };

      dock.enabled = false;
    };
  };

  home.packages = with pkgs; [
    alacritty
    wl-clipboard
    playerctl
    brightnessctl
  ];

  xdg.configFile."niri/config.kdl".source =
    pkgs.runCommand "niri-config-checked" {
      nativeBuildInputs = [ pkgs.niri ];
    } ''
      niri validate --config ${niriConfig}
      cp ${niriConfig} $out
    '';
}

