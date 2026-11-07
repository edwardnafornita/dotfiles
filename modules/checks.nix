{ self, inputs, ... }: {
  perSystem =
    { pkgs, lib, ... }:
    let
      sample = desktop: sampleWith desktop { };
      sampleWith =
        desktop: extra:
        self.lib.mkSystem (
          {
            inherit desktop;
            hostname = "test-${desktop}";
            machineModule = ../tests/machine.nix;
            # Test two independent users; this must never create Edi or mount Edi's disks.
            users.alice.admin = true; # Exercise the actual default essentials + desktop bundles.
            users.bob.appGroups = [ ];
          }
          // extra
        );
      hyprlandShell = shell: (sampleWith "hyprland" { inherit shell; }).config;
      inir =
        (sampleWith "niri" {
          shell = "inir";
          bluetooth = false;
          users.alice = {
            admin = true;
            koreanInput = true;
          };
          users.bob.appGroups = [ ];
        }).config;
      # Use the exact generated machine module, with fake hardware alongside it.
      freshMachine = pkgs.runCommand "fresh-machine-fixture" { } ''
        mkdir -p $out
        cp ${../scripts/fresh-machine.nix} $out/machine.nix
        cp ${../tests/fresh-hardware.nix} $out/hardware-configuration.nix
      '';
      fresh =
        (self.lib.mkSystem {
          machineModule = "${freshMachine}/machine.nix";
          users.alice.admin = true;
          btrfsSnapshots = true;
          secureBoot = true;
        }).config;
      inspectKoreanInput =
        desktop:
        let
          c =
            (sampleWith desktop {
              browser = "helium";
              users.alice = {
                admin = true;
                koreanInput = true;
              };
              users.bob.appGroups = [ ];
            }).config;
          alice = c.home-manager.users.alice;
          bob = c.home-manager.users.bob;
        in
        # Enabling one account must not change the greeter, system environment or other users.
        assert !c.i18n.inputMethod.enable;
        assert c.services.xserver.xkb.layout == "us";
        assert !(c.environment.sessionVariables ? XMODIFIERS);
        assert !bob.i18n.inputMethod.enable;
        assert !(bob.systemd.user.services ? fcitx5-daemon);
        assert !(bob.home.sessionVariables ? XMODIFIERS);
        assert !bob.programs.helium.enable;
        assert alice.i18n.inputMethod.enable;
        assert alice.systemd.user.services ? fcitx5-daemon;
        assert alice.systemd.user.sessionVariables.XMODIFIERS == "@im=fcitx";
        assert (alice.home.sessionVariables ? GTK_IM_MODULE) == (desktop == "plasma");
        assert alice.i18n.inputMethod.fcitx5.settings.globalOptions.Behavior.ShareInputState == "All";
        assert alice.i18n.inputMethod.fcitx5.settings.inputMethod."Groups/0".DefaultIM == "hangul";
        assert builtins.elem "--enable-wayland-ime" alice.programs.helium.flags;
        assert builtins.elem "--wayland-text-input-version=${
          if desktop == "plasma" then "1" else "3"
        }" alice.programs.helium.flags;
        assert
          c.programs.helium.flags == [
            "--ozone-platform-hint=auto"
            "--enable-features=TouchpadOverscrollHistoryNavigation"
          ];
        c.system.build.toplevel.drvPath;
      inspectHyprlandShell =
        shell:
        let
          c = hyprlandShell shell;
          hm = c.home-manager.users.alice;
        in
        assert c.programs.noctalia.enable == (shell == "noctalia");
        assert (hm.programs.caelestia.enable or false) == (shell == "caelestia");
        assert (hm.services.hyprpolkitagent.enable or false) == (shell == "caelestia");
        assert hm.wayland.windowManager.hyprland.configType == "hyprlang";
        assert !(hm.xdg.configFile ? "hypr/hyprland.lua");
        assert lib.hasInfix (
          if shell == "noctalia" then "noctalia msg session lock" else "caelestia-shell ipc call lock lock"
        ) hm.xdg.configFile."hypr/hyprland.conf".text;
        c.system.build.toplevel.drvPath;
      inspect =
        desktop:
        let
          c = (sample desktop).config;
        in
        assert c.users.users ? alice && c.users.users ? bob && !(c.users.users ? edi);
        assert !(c.fileSystems ? "/mnt/WD");
        assert c.services.desktopManager.plasma6.enable == (desktop == "plasma");
        assert c.programs.niri.enable == (desktop == "niri");
        assert c.programs.hyprland.enable == (desktop == "hyprland");
        assert !c.programs.steam.enable;
        assert !c.programs.inir.enable;
        assert !(c.systemd.user.services ? inir);
        assert c.home-manager.users.alice.home.homeDirectory == "/home/alice";
        c.system.build.toplevel.drvPath;
      ediSystem =
        desktop:
        self.lib.mkSystem (
          { lib, ... }: {
            imports = [ ../settings/hosts/nixos.nix ];
            # Test each complete session independently of the host's active choice.
            # Overriding only desktop leaves an explicitly selected shell behind.
            desktop = lib.mkForce desktop;
            shell =
              lib.mkForce
                {
                  plasma = "none";
                  niri = "noctalia";
                  hyprland = "caelestia";
                }
                .${desktop};
          }
        );
      ediInir = self.lib.mkSystem (
        { lib, ... }: {
          imports = [ ../settings/hosts/nixos.nix ];
          desktop = lib.mkForce "niri";
          shell = lib.mkForce "inir";
        }
      );
      adopted =
        (self.lib.mkSystem {
          machineModule = ../tests/adopted-machine.nix;
          stateVersion = "25.11";
          users.alice.admin = false; # Central roles must remove inherited wheel membership.
          users.bob.admin = true;
          printing = false;
          bluetooth = false;
          flatpak = false;
        }).config;
    in
    {
      checks = {
        recovery-vm = pkgs.testers.runNixOSTest (
          import ../tests/recovery-vm.nix {
            recoveryModule = self.nixosModules.recovery;
          }
        );
        profiles =
          pkgs.runCommand "desktop-profile-evaluation"
            {
              # Force complete evaluation without making every desktop a build dependency.
              profiles = builtins.unsafeDiscardStringContext (
                builtins.toJSON {
                  friends = lib.genAttrs [ "plasma" "niri" "hyprland" ] inspect;
                  existing = lib.genAttrs [ "plasma" "niri" "hyprland" ] (
                    desktop: (ediSystem desktop).config.system.build.toplevel.drvPath
                  );
                  hyprlandShells = lib.genAttrs [ "noctalia" "caelestia" ] inspectHyprlandShell;
                  inir =
                    assert inir.programs.inir.enable;
                    assert !inir.programs.noctalia.enable;
                    assert !inir.services.blueman.enable;
                    assert inir.services.displayManager.sddm.enable;
                    assert !inir.services.displayManager.gdm.enable;
                    assert !(builtins.elem "i915.enable_psr=0" inir.boot.kernelParams);
                    assert !inir.programs.inir.niri.autoDeployConfig;
                    assert builtins.elem "${pkgs.adwaita-icon-theme}/share/icons" (
                      lib.splitString ":" inir.environment.sessionVariables.XCURSOR_PATH
                    );
                    assert builtins.elem
                      "L+ %h/.local/share/icons/Adwaita - - - - ${pkgs.adwaita-icon-theme}/share/icons/Adwaita"
                      inir.systemd.user.tmpfiles.rules;
                    assert inir.security.pam.services ? quickshell;
                    assert inir.systemd.user.services.inir.partOf == [ "niri.service" ];
                    assert builtins.elem "/share/quickshell" inir.environment.pathsToLink;
                    assert inir.systemd.user.services.inir.serviceConfig.Type == "simple";
                    assert inir.systemd.user.services.niri-sync-colors.wantedBy == [ "niri.service" ];
                    assert inir.home-manager.users.alice.i18n.inputMethod.enable;
                    assert !inir.home-manager.users.bob.i18n.inputMethod.enable;
                    assert !(inir.home-manager.users.alice.xdg.configFile ? "niri/config.kdl");
                    inir.system.build.toplevel.drvPath;
                  existingInir = ediInir.config.system.build.toplevel.drvPath;
                  koreanInput = lib.genAttrs [ "plasma" "niri" "hyprland" ] inspectKoreanInput;
                  fresh =
                    assert fresh.fileSystems."/".fsType == "btrfs";
                    assert builtins.elem "subvol=home" fresh.fileSystems."/home".options;
                    assert builtins.elem "subvol=nix" fresh.fileSystems."/nix".options;
                    assert builtins.elem "compress=zstd" fresh.fileSystems."/".options;
                    assert builtins.elem "fmask=0077" fresh.fileSystems."/boot".options;
                    assert fresh.boot.loader.limine.secureBoot.enable;
                    assert fresh.boot.loader.limine.secureBoot.autoGenerateKeys;
                    assert !fresh.boot.loader.limine.secureBoot.autoEnrollKeys.enable;
                    assert !fresh.boot.loader.systemd-boot.enable;
                    assert fresh.boot.loader.limine.enrollConfig && fresh.boot.loader.limine.validateChecksums;
                    assert fresh.boot.loader.limine.panicOnChecksumMismatch;
                    assert fresh.services.snapper.configs.root.TIMELINE_CREATE;
                    assert fresh.services.snapper.configs.home.TIMELINE_CLEANUP;
                    assert fresh.services.snapper.configs.home.SUBVOLUME == "/home";
                    assert fresh.systemd.timers.snapper-timeline.timerConfig.Persistent;
                    assert fresh.services.btrfs.autoScrub.enable;
                    assert adopted.services.snapper.configs == { };
                    assert !adopted.boot.loader.limine.enable;
                    fresh.system.build.toplevel.drvPath;
                  adoption =
                    assert adopted.system.stateVersion == "25.11";
                    assert !adopted.services.desktopManager.gnome.enable;
                    assert adopted.services.desktopManager.plasma6.enable;
                    assert adopted.services.displayManager.sddm.wayland.enable;
                    assert !(builtins.elem "wheel" adopted.users.users.alice.extraGroups);
                    assert !adopted.services.printing.enable;
                    assert !adopted.hardware.bluetooth.enable;
                    assert !adopted.services.flatpak.enable;
                    adopted.system.build.toplevel.drvPath;
                }
              );
              passAsFile = [ "profiles" ];
            }
            ''
              cp "$profilesPath" "$out"
            '';
        niri-config =
          (ediSystem "niri").config.home-manager.users.edi.xdg.configFile."niri/config.kdl".source;
        inir-config =
          ediInir.config.home-manager.users.edi.home.file.".local/share/dotfiles/inir-niri".source;
        hyprland-config =
          pkgs.runCommand "hyprland-config-checked"
            {
              nativeBuildInputs = [ pkgs.hyprland ]; # Use the exact compositor that reads these files at login.
            }
            (
              ''
                export HOME="$TMPDIR/home"
                export XDG_RUNTIME_DIR="$TMPDIR/runtime"
                mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
                chmod 700 "$XDG_RUNTIME_DIR"
              ''
              +
                lib.concatMapStringsSep "\n"
                  (
                    shell:
                    let
                      hm = (hyprlandShell shell).home-manager.users.alice;
                      config = pkgs.writeText "hyprland-${shell}.conf" hm.xdg.configFile."hypr/hyprland.conf".text;
                    in
                    ''
                      Hyprland --verify-config --config ${config}
                    ''
                  )
                  [
                    "noctalia"
                    "caelestia"
                  ]
              + ''
                touch "$out"
              ''
            );
        scripts =
          pkgs.runCommand "installer-and-update-tests"
            {
              nativeBuildInputs = with pkgs; [
                bash # Script syntax and isolated execution tests.
                shellcheck # Shell correctness checks.
                python3 # Settings escaping and update failure-path tests.
                git # Temporary local repositories for update tests.
                jq # Stubbed Nix metadata parser in update tests.
                util-linux # Update lock handling.
                patch # Exercise the pinned iNiR color-sync fix.
              ];
              INIR_COLOR_SYNC_SOURCE = "${inputs.inir-nixos}/scripts/niri-sync-colors";
            }
            ''
              cp -r ${../scripts} scripts
              cp -r ${../tests} tests
              cp -r ${../patches} patches
              chmod -R u+w scripts tests
              shellcheck scripts/*.sh tests/*.sh
              bash -n scripts/install.sh
              bash -n scripts/install-fresh.sh
              bash -n scripts/update-system.sh
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              python3 -m unittest discover -s tests -v
              touch "$out"
            '';
      };
    };
}
