{ inputs, ... }: {
  flake.nixosModules.inir =
    {
      lib,
      pkgs,
      settings,
      ...
    }:
    let
      port = inputs.inir-nixos;
      # Palette metadata can point to a video thumbnail or a separate backdrop.
      # Keep the port's color watcher from replacing iNiR's selected wallpaper.
      patchedPort = runtimePkgs.applyPatches {
        name = "inir-nixos-preserve-wallpaper";
        src = port;
        patches = [ ../patches/inir-color-sync-wallpaper.patch ];
      };
      runtimePkgs = port.inputs.nixpkgs.legacyPackages.${settings.system};
      # Evaluate just the shell modules with their matching Qt/Python packages.
      # The port's aggregate module also changes login, kernel and global Qt
      # settings, even when iNiR is disabled, so import these explicitly.
      runtimeArgs =
        args:
        args
        // {
          pkgs = runtimePkgs;
          inir = port.inputs.inir;
        };
    in
    {
      imports = [
        (args: import port.inputs.inir.nixosModules.inir (runtimeArgs args))
        (args: import "${patchedPort}/modules/inir.nix" (runtimeArgs args))
      ];

      config = lib.mkIf (settings.shell == "inir") {
        programs.inir = {
          enable = true;
          extraPackages = [ runtimePkgs.libsecret ]; # secret-tool for the shell's keyring.
          niri.autoDeployConfig = false; # Home Manager seeds our adapted rice.
          familyTransitionAnimation.enable = false; # Respect upstream's Qt crash workaround.
        };
        programs.niri.package = runtimePkgs.niri;
        # Portal daemons belong to the host. Mixing the port's and host's
        # versions registers duplicate user units for the same D-Bus services.
        xdg.portal.extraPortals = lib.mkForce [
          pkgs.xdg-desktop-portal-gnome
          pkgs.xdg-desktop-portal-gtk
        ];
        # Match the XWayland runtime and supply the seeded config's cursor theme.
        environment.systemPackages = [
          runtimePkgs.xwayland-satellite
          pkgs.adwaita-icon-theme # Cursor assets for the port's Adwaita default.
        ];
        # Niri loads cursors before user tmpfiles/shell startup. Resolve the
        # immutable assets directly, including on the first login after a switch.
        environment.sessionVariables.XCURSOR_PATH = [
          "${pkgs.adwaita-icon-theme}/share/icons"
        ];
        # iNiR's cursor picker only scans user icon directories and /usr/share.
        systemd.user.tmpfiles.rules = [
          "L+ %h/.local/share/icons/Adwaita - - - - ${pkgs.adwaita-icon-theme}/share/icons/Adwaita"
        ];
        # The port's tmpfiles links and Niri shortcuts resolve through this path.
        environment.pathsToLink = [ "/share/quickshell" ];
        programs.dconf.enable = true;
        services.gnome.gnome-keyring.enable = true;
        security.pam.services.sddm.enableGnomeKeyring = true;
        security.pam.services.quickshell = { }; # iNiR lock screen authentication.
        fonts.packages = with runtimePkgs; [
          material-symbols
          nerd-fonts.jetbrains-mono
          roboto-flex
          twitter-color-emoji
        ];

        # Scope desktop helpers to the Niri session, including logout/relogin.
        systemd.user.services.niri-sync-colors = {
          wantedBy = lib.mkForce [ "niri.service" ];
          partOf = [ "niri.service" ];
          requisite = [ "niri.service" ];
        };
        systemd.user.services.polkit-kde-authentication-agent-1 = {
          wantedBy = lib.mkForce [ "niri.service" ];
          partOf = [ "niri.service" ];
          after = [ "niri.service" ];
        };
        systemd.user.services.inir.environment = {
          # Use the external agent above; prevent competing authentication agents.
          QS_DISABLE_POLKIT = "1";
          # Keep stable Qt/Fcitx plugins out of the newer Quickshell process.
          QT_IM_MODULE = "wayland";
          QT_IM_MODULES = "wayland";
          QT_PLUGIN_PATH = lib.makeSearchPath "lib/qt-6/plugins" [
            runtimePkgs.kdePackages.plasma-integration
            runtimePkgs.darkly
          ];
          QT_QPA_PLATFORMTHEME = "kde";
          QT_STYLE_OVERRIDE = "Darkly";
        };
        # Follow the shell process itself. The welcome window also registers the
        # tray watcher name, so its ownership cannot represent shell readiness.
        systemd.user.services.inir.serviceConfig = {
          Type = lib.mkForce "simple";
          BusName = lib.mkForce "";
        };
        # The upstream service supplies its own PATH. Add each logged-in user's
        # applications so GUI launchers can find Home Manager packages and the
        # per-user browser wrapper (including Korean IME flags).
        systemd.user.services.inir.path = lib.mkBefore [
          "/etc/profiles/per-user/%u"
          "/run/current-system/sw"
        ];
        # The shared setting remains authoritative on machines without Bluetooth.
        services.blueman.enable = lib.mkForce settings.bluetooth;
      };
    };
}
