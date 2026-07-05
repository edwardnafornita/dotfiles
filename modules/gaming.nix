{ config, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  programs.steam = {
    enable = true;
    extest.enable = true; # for controllers
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
    extraPackages = with pkgs; [
      gamescope
      mangohud
      gamemode
    ];
  };

  programs.gamemode.enable = true;

  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };

  hardware.steam-hardware.enable = true;
  services.udev.packages = with pkgs; [
    game-devices-udev-rules
  ];

  fonts.packages = with pkgs; [
    liberation_ttf
    dejavu_fonts
    noto-fonts
    noto-fonts-cjk-sans
    corefonts
  ];

  environment.systemPackages = with pkgs; [
    steam
    protonup-qt
    protontricks

    gamescope
    gamemode
    mangohud
    goverlay

    wineWow64Packages.stable
    winetricks

    vulkan-tools
    mesa-demos
    pciutils
    usbutils
  ];
}

