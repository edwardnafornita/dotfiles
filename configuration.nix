{ config, lib, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.limine.secureBoot.enable = true;  
  boot.loader.limine = {
    enable = true;
    panicOnChecksumMismatch = true;
    maxGenerations = 10;
    extraEntries = ''
      /Windows 11
      protocol: efi
      path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
    '';
  };

  networking.hostName = "nixos";

  networking.networkmanager.enable = true;

  hardware.bluetooth.enable = true;

  services.tuned.enable = true;
  
  services.upower.enable = true;

  time.timeZone = "America/Toronto";

  services.xserver.xkb.layout = "us";

  environment.systemPackages = with pkgs; [
    limine-full
    sbctl
  ];
  
  system.stateVersion = "26.05";
}

