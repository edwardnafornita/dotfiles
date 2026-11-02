{ ... }: {
  # Evaluation fixture only; scripts/fresh-machine.nix is copied next to the
  # actual generated hardware file by the installer.
  fileSystems =
    builtins.listToAttrs (
      map
        (mount: {
          name = builtins.elemAt mount 0;
          value = {
            device = "/dev/disk/by-uuid/test-btrfs";
            fsType = "btrfs";
            options = [ "subvol=${builtins.elemAt mount 1}" ];
          };
        })
        [
          [
            "/"
            "root"
          ]
          [
            "/home"
            "home"
          ]
          [
            "/nix"
            "nix"
          ]
          [
            "/.snapshots"
            "snapshots"
          ]
          [
            "/home/.snapshots"
            "home-snapshots"
          ]
        ]
    )
    // {
      "/boot" = {
        device = "/dev/disk/by-uuid/test-efi";
        fsType = "vfat";
      };
    };
}
