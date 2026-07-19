{ inputs, ... }:

{
  imports = [
    inputs.noctalia.nixosModules.default
  ];

  hardware.graphics.enable = true;
  services.dbus.enable = true;
  security.polkit.enable = true;
  security.rtkit.enable = true;

  programs.niri.enable = true;

  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
    systemd.enable = true;
  };

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    wireplumber.enable = true;

    alsa = {
      enable = true;
      support32Bit = true;
    };
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}

