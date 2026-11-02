{ ... }: {
  flake.nixosModules.recovery =
    {
      config,
      lib,
      pkgs,
      settings,
      ...
    }:
    lib.mkMerge [
      (lib.mkIf settings.btrfsSnapshots {
        assertions =
          map
            (mount: {
              assertion = (config.fileSystems.${mount}.fsType or null) == "btrfs";
              message = "btrfsSnapshots requires a separate Btrfs mount for ${mount}; it does not migrate existing filesystems.";
            })
            [
              "/"
              "/home"
              "/nix"
              "/.snapshots"
              "/home/.snapshots"
            ];
        services.btrfs.autoScrub.enable = true; # Monthly integrity checks.
        services.btrfs.autoScrub.fileSystems = [ "/" ]; # All subvolumes share one filesystem.
        services.snapper = {
          snapshotInterval = "hourly";
          persistentTimer = true;
          snapshotRootOnBoot = true;
          configs = lib.genAttrs [ "root" "home" ] (name: {
            SUBVOLUME = if name == "root" then "/" else "/home";
            FSTYPE = "btrfs";
            TIMELINE_CREATE = true;
            TIMELINE_CLEANUP = true;
            TIMELINE_LIMIT_HOURLY = 6;
            TIMELINE_LIMIT_DAILY = 7;
            TIMELINE_LIMIT_WEEKLY = 4;
            TIMELINE_LIMIT_MONTHLY = 3;
            TIMELINE_LIMIT_YEARLY = 0;
            NUMBER_CLEANUP = true;
            NUMBER_LIMIT = 10; # Boot, installation and before-update snapshots.
            EMPTY_PRE_POST_CLEANUP = true;
          });
        };
      })
      (lib.mkIf settings.secureBoot {
        boot.loader = {
          systemd-boot.enable = false;
          efi.canTouchEfiVariables = true;
          limine = {
            enable = true;
            maxGenerations = 10;
            enableEditor = false;
            enrollConfig = true;
            validateChecksums = true;
            panicOnChecksumMismatch = true;
            secureBoot = {
              enable = true;
              autoGenerateKeys = true; # Generated on the target, never embedded in Nix sources.
              autoEnrollKeys.enable = false; # Enrollment is explicit and checked by install-fresh.sh.
            };
          };
        };
        environment.systemPackages = with pkgs; [
          sbctl
          limine
        ]; # Status checks and bootloader maintenance.
      })
    ];
}
