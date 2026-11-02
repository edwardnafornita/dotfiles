{ inputs, ... }: {
  flake.nixosModules.desktop =
    {
      lib,
      pkgs,
      settings,
      ...
    }:
    let
      wm = settings.desktop != "plasma";
    in
    {
      imports = [ inputs.noctalia.nixosModules.default ]; # Declare options; enable only for the selected shell.
      assertions = [
        {
          assertion =
            builtins.elem settings.shell
              {
                plasma = [ "none" ];
                niri = [ "noctalia" ];
                hyprland = [
                  "noctalia"
                  "caelestia"
                ];
              }
              .${settings.desktop};
          message = "Unsupported desktop/shell pairing: Plasma uses none, Niri uses noctalia, Hyprland uses noctalia or caelestia.";
        }
      ];
      # Force only the session selectors so a copied graphical-installer config
      # cannot accidentally start a second DE. Machine boot/hardware is untouched.
      services.desktopManager.plasma6.enable = lib.mkForce (settings.desktop == "plasma");
      services.desktopManager.gnome.enable = lib.mkForce false;
      services.displayManager.gdm.enable = lib.mkForce false;
      services.xserver.enable = lib.mkDefault true; # X11 greeter support; respect adopted Wayland-only installs.
      services.displayManager = {
        defaultSession = lib.mkForce (
          {
            plasma = "plasma";
            niri = "niri";
            hyprland = "hyprland-uwsm";
          }
          .${settings.desktop}
        );
        sddm = {
          enable = lib.mkForce true; # One login manager for all desktop choices.
          # Let NixOS choose its default (Wayland for Plasma, X11 otherwise).
          # An adopted machine's explicit wayland.enable remains authoritative.
          package = lib.mkDefault pkgs.kdePackages.sddm;
          theme = lib.mkIf settings.sddmAstronaut "sddm-astronaut-theme";
          extraPackages = lib.optionals settings.sddmAstronaut (
            with pkgs;
            [
              sddm-astronaut # Existing login theme.
              kdePackages.qtmultimedia # Video/media support used by that theme.
            ]
          );
        };
      };
      programs.niri.enable = lib.mkForce (settings.desktop == "niri"); # Niri session and its portal integration.
      programs.hyprland = {
        enable = lib.mkForce (settings.desktop == "hyprland"); # Hyprland with matching portal package.
        withUWSM = true; # Correct session environment and systemd lifecycle.
      };
      programs.noctalia = lib.mkIf (settings.shell == "noctalia") {
        enable = true; # Selected compositor panel, launcher, notifications and lock screen.
        recommendedServices.enable = true; # Upstream shell integration services.
        systemd.enable = true; # Start and stop with the graphical session.
      };
      services.dbus.enable = true; # Desktop IPC.
      security.polkit.enable = true; # Graphical authorization for privileged settings.
      # Caelestia's Brightness service shells out to ddcutil for external-monitor DDC
      # control; the uaccess-tagged udev rule grants any locally-seated user access.
      hardware.i2c.enable = lib.mkIf (settings.shell == "caelestia") true;
      programs.thunar = lib.mkIf wm {
        enable = true; # File manager for compositor sessions; Plasma provides Dolphin.
        plugins = with pkgs; [
          thunar-archive-plugin # Archive actions in the file manager.
          thunar-volman # Removable media integration.
        ];
      };
      programs.xfconf.enable = wm; # Persist Thunar preferences.
      services.gvfs.enable = true; # Trash, network locations and removable media.
      services.udisks2.enable = true; # Authorized disk mounting through the GUI.
      services.tumbler.enable = wm; # Thunar thumbnails.
      services.keyd = lib.mkIf (settings.metaTapLauncher && wm) {
        enable = true; # Tap Super for launcher; hold Super for shortcuts.
        keyboards.default = {
          ids = [ "*" ];
          settings.main.leftmeta = "overload(meta, M-space)";
        };
      };
      environment.sessionVariables.NIXOS_OZONE_WL = "1"; # Prefer native Wayland in Chromium/Electron.
      environment.systemPackages =
        with pkgs;
        lib.optionals wm [
          pavucontrol # Mixer for compositor sessions.
          file-roller # Thunar archive operations.
        ]
        ++ lib.optional (settings.desktop == "niri") xwayland-satellite # X11 application support in Niri.
        ++ lib.optionals (wm && settings.flatpak) [
          gnome-software # Graphical Flatpak management outside Plasma Discover.
        ]
        ++ lib.optionals settings.sddmAstronaut [
          sddm-astronaut # Make theme assets available to SDDM.
          kdePackages.qtmultimedia # Theme multimedia plugin.
        ]
        ++ lib.optional (settings.metaTapLauncher && wm) keyd; # Inspect/debug keyboard remapping.
    };
  flake.homeModules.desktop = { settings, ... }: {
    imports = [
      ../desktops/${settings.desktop}.nix
    ]
    ++ (if settings.shell == "none" then [ ] else [ ../shells/${settings.shell}.nix ]);
  };
}
