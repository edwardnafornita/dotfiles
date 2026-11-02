{ ... }: {
  imports = [ ./hardware-configuration.nix ];
  # The installer mounts these before hardware detection. Persist the performance
  # and permission options explicitly, without depending on generator defaults.
  fileSystems = {
    "/".options = [
      "compress=zstd"
      "noatime"
    ];
    "/home".options = [
      "compress=zstd"
      "noatime"
    ];
    "/nix".options = [
      "compress=zstd"
      "noatime"
    ];
    "/.snapshots".options = [
      "compress=zstd"
      "noatime"
    ];
    "/home/.snapshots".options = [
      "compress=zstd"
      "noatime"
    ];
    "/boot".options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };
  zramSwap.enable = true; # No disk swap/hibernation; keep swap outside snapshots.
}
