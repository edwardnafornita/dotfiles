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
    (pkgs.writeShellScriptBin "reboot-windows" ''
      set -euo pipefail
  
      boot_number="$(
        ${pkgs.efibootmgr}/bin/efibootmgr |
        ${pkgs.gnused}/bin/sed -n \
          's/^Boot\([0-9A-Fa-f]\{4\}\)\*.*Windows Boot Manager.*/\1/p' |
        ${pkgs.coreutils}/bin/head -n1
      )"
  
      if [ -z "$boot_number" ]; then
        echo "Windows Boot Manager was not found in the UEFI boot entries." >&2
        exit 1
      fi
  
      echo "Setting Windows Boot Manager ($boot_number) as BootNext..."
      ${pkgs.efibootmgr}/bin/efibootmgr --bootnext "$boot_number"
      ${pkgs.systemd}/bin/systemctl reboot
    '')

    limine-full
    sbctl
    efibootmgr
    pavucontrol
  ];
  
  system.stateVersion = "26.05";
}

