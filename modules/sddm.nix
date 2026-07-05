{ config, pkgs, ... }:

{
  services.displayManager = {
    defaultSession = "sway";

    sddm = {
      enable = true;
      wayland.enable = true;

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

