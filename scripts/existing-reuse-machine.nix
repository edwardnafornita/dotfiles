{ lib, ... }: {
  imports = [ ./base/configuration.nix ];
  # The copied configuration manages its own systemd-boot. Override it in favor
  # of signed Limine, reusing Secure Boot keys already enrolled in this
  # machine's firmware by another installation on this computer.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  # Missing migrated keys must fail signing rather than generate untrusted keys.
  boot.loader.limine.secureBoot.autoGenerateKeys = lib.mkForce false;
  boot.loader.limine.secureBoot.autoEnrollKeys.enable = lib.mkForce false;
  # Upstream Limine replaces an existing entry named Limine. Keep both drives
  # bootable by maintaining the fallback file and registering it separately.
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.limine.efiInstallAsRemovable = lib.mkForce true;
}
