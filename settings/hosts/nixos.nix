{
  # Existing machine; reusable modules never name this account.
  machineModule = ../../hosts/nixos;
  hostname = "nixos";
  stateVersion = "26.05";
  desktop = "plasma";
  shell = "none";
  browser = "helium";
  allowUnfree = true; # Existing gaming, Spotify and development applications.
  xboxControllers = true; # Preserve xone and xpadneo support.
  powerTuning = true; # Preserve tuned.
  sddmAstronaut = true; # Preserve the login screen.
  metaTapLauncher = true; # Preserve tap-Super launcher shortcut.
  updates.output = "edi-nixos"; # Explicit personal profile; never a generic hostname fallback.
  users.edi = {
    description = "Edi";
    admin = true;
    uid = 1000; # Existing files and drive mounts use this ID.
    extraGroups = [
      "video"
      "audio"
    ]; # Preserve current memberships.
    appGroups = [
      "essentials"
      "gaming"
      "development"
      "media"
    ];
    bash = "ctt";
  };
  # Match the Niri monitor layout when selecting Hyprland: DP-2 left, DP-3 right.
  # Both displays use 2560x1440 at 180.002 Hz with 1x scaling.
  hyprlandMonitors = [
    "DP-2,2560x1440@180.002,0x0,1"
    "DP-3,2560x1440@180.002,2560x0,1"
  ];
  # Fixed outputs belong to this machine, not the reusable Niri configuration.
  niriOutputs = ''
    output "DP-2" {
      mode "2560x1440@180.002"
      scale 1.0
      position x=0 y=0
      focus-at-startup
    }
    output "DP-3" {
      mode "2560x1440@180.002"
      scale 1.0
      position x=2560 y=0
    }
  '';
}
