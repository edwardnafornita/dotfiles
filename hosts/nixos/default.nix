{ pkgs, ... }: {
  # Preserve hardware-configuration.nix byte for byte at its original path.
  imports = [
    ../../hardware-configuration.nix
    ./drives.nix
  ];
  # Existing Limine, Secure Boot and Windows dual-boot behavior.
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

  # Keep Bluetooth headphones in high-fidelity playback; use the Scarlett for input.
  services.pipewire.wireplumber.extraConfig."51-bluetooth-playback" = {
    "wireplumber.settings"."bluetooth.autoswitch-to-headset-profile" = false;
    "monitor.bluez.properties" = {
      "bluez5.roles" = [
        "a2dp_sink"
        "a2dp_source"
        "bap_sink"
        "bap_source"
      ];
      "bluez5.hfphsp-backend" = "none";
    };
  };

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

    limine-full # Bootloader maintenance tools.
    sbctl # Existing Secure Boot key management.
    efibootmgr # UEFI boot entry management.
  ];

}
