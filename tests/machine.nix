{ ... }: {
  # Evaluation fixture only: never install this fake disk on real hardware.
  fileSystems."/" = {
    device = "/dev/disk/by-label/test-root";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/test-efi";
    fsType = "vfat";
  };
  boot.loader.systemd-boot.enable = true;
}
