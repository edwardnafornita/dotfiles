# Caelestia requires Hyprland; the desktop module rejects unsupported pairings.
{ inputs, config, ... }: {
  imports = [ inputs.caelestia.homeManagerModules.default ];
  programs.caelestia = {
    enable = true; # Panel, launcher, notifications, lock screen and wallpaper UI.
    systemd.enable = true; # UWSM starts/stops graphical-session.target.
    cli.enable = true; # Wallpaper/theme helpers and IPC commands.
    settings.paths.wallpaperDir = "${config.xdg.userDirs.pictures}/Wallpapers";
  };
  services.hyprpolkitagent.enable = true; # Graphical authentication for settings and disk mounting.
}
