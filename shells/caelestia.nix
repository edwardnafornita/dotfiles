# Caelestia requires Hyprland; the desktop module rejects unsupported pairings.
{
  inputs,
  config,
  pkgs,
  ...
}:
{
  imports = [ inputs.caelestia.homeManagerModules.default ];
  programs.caelestia = {
    enable = true; # Panel, launcher, notifications, lock screen and wallpaper UI.
    systemd.enable = true; # UWSM starts/stops graphical-session.target.
    cli.enable = true; # Wallpaper/theme helpers and IPC commands.
    settings.paths.wallpaperDir = "${config.xdg.userDirs.pictures}/Wallpapers";
  };
  services.hyprpolkitagent.enable = true; # Graphical authentication for settings and disk mounting.
  home.packages = with pkgs; [
    hyprpicker # $mod+shift+C colour picker, exec'd straight from Hyprland below.
    ddcutil # External-monitor DDC brightness backend for services/Brightness.qml.
  ];
  wayland.windowManager.hyprland.settings = {
    # caelestia-cli ships the cliphist binary, but nothing runs it continuously
    # without this: wl-clipboard (providing wl-paste) is already installed by
    # desktops/hyprland.nix.
    "exec-once" = [
      "wl-paste --type text --watch cliphist store"
      "wl-paste --type image --watch cliphist store"
    ];
    # Hyprland 0.55's layerrule syntax requires explicit match:namespace fields
    # and "on" values for boolean rules (bare `blur`/`no_anim` are rejected).
    layerrule = [
      "animation fade, match:namespace hyprpicker"
      "animation popin 80%, match:namespace launcher" # Fuzzel, used by the clipboard/emoji binds below.
      "blur on, match:namespace launcher"
      "no_anim on, match:namespace caelestia-(border-exclusion|area-picker)"
      "animation fade, match:namespace caelestia-(drawers|background)"
    ];
    bind = [
      "$mod, N, global, caelestia:sidebar"
      "$mod, K, global, caelestia:showall"
      "CTRL ALT, Delete, global, caelestia:session"
      "CTRL ALT, C, global, caelestia:clearNotifs"
      # Primary lock key; the shared $mod ALT,L bind from desktops/hyprland.nix
      # still works and now reads as upstream's "restore lock" key.
      "$mod, L, global, caelestia:lock"
      "$mod SHIFT, S, global, caelestia:screenshotFreeze"
      "$mod SHIFT ALT, S, global, caelestia:screenshot"
      "$mod SHIFT, C, exec, hyprpicker -a"
      "$mod, V, exec, pkill fuzzel || caelestia clipboard"
      "$mod ALT, V, exec, pkill fuzzel || caelestia clipboard -d"
      "$mod, Period, exec, pkill fuzzel || caelestia emoji -p"
      "CTRL ALT, R, exec, caelestia record"
      "$mod ALT, R, exec, caelestia record -s"
      "$mod SHIFT ALT, R, exec, caelestia record -r"
      # Special workspaces matching the shell bar's built-in icons. No Lua toggle
      # smarts (auto-spawn/move stray windows) since this repo stays on plain
      # Hyprlang; see shell.json's bar.workspaces.specialWorkspaceIcons defaults.
      "$mod, S, togglespecialworkspace, special"
      "$mod, M, togglespecialworkspace, music"
      "$mod, D, togglespecialworkspace, communication"
      "$mod, R, togglespecialworkspace, todo"
      "CTRL SHIFT, Escape, togglespecialworkspace, sysmon"
    ];
    # windowrulev2 is a hard config error on Hyprland 0.55; use windowrule with
    # the new match:class field instead.
    windowrule = [
      "workspace special:music silent, match:class ^(Spotify)$"
      "workspace special:communication silent, match:class ^(vesktop)$"
    ];
  };
}
