{ recoveryModule }:
{ pkgs, ... }: {
  name = "btrfs-snapshots-and-efi-signing";
  requiredFeatures.kvm = false; # Also runnable with software emulation.
  nodes.machine = { lib, pkgs, ... }: {
    imports = [ recoveryModule ];
    _module.args.settings = {
      btrfsSnapshots = true;
      secureBoot = false;
    };
    virtualisation = {
      diskImage = null;
      useDefaultFilesystems = false;
      emptyDiskImages = [
        {
          size = 2048;
          driveConfig.deviceExtraOpts.serial = "btrfs-test";
        }
      ];
      memorySize = 1024;
      fileSystems = builtins.listToAttrs (
        map
          (mount: {
            name = builtins.elemAt mount 0;
            value = {
              device = "/dev/disk/by-id/virtio-btrfs-test";
              fsType = "btrfs";
              options = [
                "subvol=${builtins.elemAt mount 1}"
                "compress=zstd"
                "noatime"
              ];
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
      );
    };
    boot.initrd.systemd.enable = false;
    boot.initrd.extraUtilsCommands = ''
      copy_bin_and_libs ${pkgs.btrfs-progs}/bin/mkfs.btrfs
    '';
    # This disk belongs only to the disposable guest. Production formatting is
    # separately exercised by test_fresh_install.py with intercepted commands.
    boot.initrd.postDeviceCommands = lib.mkAfter ''
      mkfs.btrfs -f /dev/disk/by-id/virtio-btrfs-test
      mkdir -p /btrfs
      mount -t btrfs /dev/disk/by-id/virtio-btrfs-test /btrfs
      for name in root home nix snapshots home-snapshots; do
        btrfs subvolume create /btrfs/$name
      done
      chmod 0700 /btrfs/snapshots /btrfs/home-snapshots
      umount /btrfs
    '';
    environment.systemPackages = [
      pkgs.sbctl
      pkgs.sbsigntool
      pkgs.limine
    ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl show snapper-boot.service -p Result --value | grep -x success")
    machine.succeed("snapper --no-dbus -c root list | grep boot")
    machine.succeed("findmnt -n -o FSTYPE / | grep -x btrfs")
    machine.succeed("findmnt -n -o OPTIONS /home | grep compress=zstd")
    machine.succeed("echo before > /home/recovery-test")
    before = machine.succeed("snapper --no-dbus -c home create --print-number").strip()
    machine.succeed("echo after > /home/recovery-test")
    after = machine.succeed("snapper --no-dbus -c home create --print-number").strip()
    machine.succeed(f"snapper --no-dbus -c home undochange {before}..{after}")
    assert machine.succeed("cat /home/recovery-test").strip() == "before"
    machine.succeed("systemctl start --wait snapper-timeline.service snapper-cleanup.service")
    machine.succeed("snapper --no-dbus -c root list | grep timeline")
    machine.succeed("snapper --no-dbus -c home list | grep timeline")
    machine.succeed("test $(stat -c %a /.snapshots) = 700")
    machine.succeed("sbctl create-keys")
    machine.succeed("cp ${pkgs.limine}/share/limine/BOOTX64.EFI /tmp/BOOTX64.EFI")
    machine.succeed("limine enroll-config /tmp/BOOTX64.EFI $(printf test | b2sum | cut -d ' ' -f1)")
    machine.succeed("sbctl sign /tmp/BOOTX64.EFI")
    machine.succeed("sbverify --cert /var/lib/sbctl/keys/db/db.pem /tmp/BOOTX64.EFI")
  '';
}
