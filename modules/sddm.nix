{ config, pkgs, ... }:

{
  services.xserver.enable = true;

  services.displayManager = {
    defaultSession = "niri";

    sddm = {
      enable = true;
      wayland.enable = false;

      package = pkgs.kdePackages.sddm;

      theme = "sddm-astronaut-theme";

      extraPackages = with pkgs; [
        sddm-astronaut
        kdePackages.qtmultimedia
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    sddm-astronaut
    kdePackages.qtmultimedia
  ];
}

