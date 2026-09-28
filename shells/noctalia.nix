# Shared Noctalia appearance and behavior for Niri and Hyprland.
{ inputs, ... }: {
  imports = [
    inputs.noctalia.homeModules.default
  ];

  programs.noctalia = {
    enable = true; # Panel, launcher, notifications, wallpaper and locking.
    validateConfig = true; # Validate settings against the pinned shell schema.

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

}
