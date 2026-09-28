# Existing machine-specific UUIDs and ownership; never import on another PC.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    ntfs3g # NTFS maintenance tools for the existing Windows drive.
  ];

  boot.supportedFilesystems = [ "ntfs" ];

  fileSystems."/mnt/WD" = {
    device = "/dev/disk/by-uuid/2C309B91309B611E";
    fsType = "ntfs3";

    options = [
      "rw"

      "uid=1000"
      "gid=100"

      "umask=0022"

      "nofail"
      "x-systemd.device-timeout=5s"

      "x-gvfs-show"
    ];
  };

  fileSystems."/mnt/Seagate" = {
    device = "/dev/disk/by-uuid/807bec51-9212-4775-a326-2426c00b1649";
    fsType = "ext4";

    options = [
      "rw"
      "nofail"
      "x-systemd.device-timeout=5s"
      "x-gvfs-show"
    ];
  };

  fileSystems."/mnt/PATRIOT" = {
    device = "/dev/disk/by-uuid/7E12-6F5A";
    fsType = "exfat";

    options = [
      "rw"
      "uid=1000"
      "gid=100"
      "umask=0022"
      "nofail"
      "x-systemd.device-timeout=5s"
      "x-gvfs-show"
    ];
  };

  services.udisks2.enable = true;
  services.gvfs.enable = true;
}
