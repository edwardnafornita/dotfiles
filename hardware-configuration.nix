{ config, lib, pkgs, modulesPath, ... }:

let
  rootDisk = "/dev/disk/by-label/nixos";
  bootDisk = "/dev/disk/by-label/boot";
  swapDisk = "/dev/disk/by-label/swap";

  btrfsOptions = [ "compress=zstd" ];
in
{
  imports =
    [
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

  boot = {
    initrd = {
      availableKernelModules = [
        "ahci"
        "xhci_pci"
        "virtio_pci"
        "sr_mod"
        "virtio_blk"
      ];

      kernelModules = [ ];
    };

    kernelModules = [ "kvm-amd" ];
    extraModulePackages = [ ];
  };

  fileSystems = {
    "/" = {
      device = rootDisk;
      fsType = "btrfs";
      options = [ "subvol=root" ] ++ btrfsOptions;
    };
    "/home" = {
      device = rootDisk;
      fsType = "btrfs";
      options = [ "subvol=home" ] ++ btrfsOptions;
    };
    "/nix" = {
      device = rootDisk;
      fsType = "btrfs";
      options = [ "subvol=nix" "noatime" ] ++ btrfsOptions;
    };
    "/boot" = {
      device = bootDisk;
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
  };

  swapDevices = [
    {
      device = swapDisk;
      options = [ "noatime" ];
    }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

