{ config, pkgs, ... }:

{
  hardware.graphics.enable = true;

  services.dbus.enable = true;
  security.polkit.enable = true;

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    xwayland.enable = true;
    extraPackages = [ ];
  };
}
