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
        assert c.home-manager.users.alice.home.homeDirectory == "/home/alice";
        c.system.build.toplevel.drvPath;
      ediDesktop =
        desktop:
        (self.lib.mkSystem (
          { lib, ... }: {
            imports = [ ../settings/hosts/nixos.nix ];
            desktop = lib.mkForce desktop;
          }
        )).config.system.build.toplevel.drvPath;
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
        profiles =
          pkgs.runCommand "desktop-profile-evaluation"
            {
              # Force complete evaluation without making every desktop a build dependency.
              profiles = builtins.unsafeDiscardStringContext (
                builtins.toJSON {
                  friends = lib.genAttrs [ "plasma" "niri" "hyprland" ] inspect;
                  existing = lib.genAttrs [ "plasma" "niri" "hyprland" ] ediDesktop;
                  hyprlandShells = lib.genAttrs [ "noctalia" "caelestia" ] inspectHyprlandShell;
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
          (self.lib.mkSystem ../settings/hosts/nixos.nix)
          .config.home-manager.users.edi.xdg.configFile."niri/config.kdl".source;
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
              ];
            }
            ''
              cp -r ${../scripts} scripts
              cp -r ${../tests} tests
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
