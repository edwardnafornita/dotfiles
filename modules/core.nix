{ inputs, self, ... }: {
  flake.nixosModules.core =
    {
      lib,
      pkgs,
      settings,
      ...
    }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];
      assertions = [
        {
          assertion = settings.users != { };
          message = "Define an account in settings/hosts or settings/local/default.nix.";
        }
        {
          assertion = lib.any (u: u.admin) (builtins.attrValues settings.users);
          message = "Keep at least one admin account for installation and updates.";
        }
        {
          assertion = lib.all (
            name:
            builtins.match "[a-z_][a-z0-9_-]*" name != null
            && !(builtins.elem name [
              "root"
              "nobody"
            ])
            && !(lib.hasPrefix "nixbld" name)
          ) (builtins.attrNames settings.users);
          message = "Use lowercase login names with letters, numbers, underscores or hyphens.";
        }
      ];
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ]; # Pinned configuration entry point.
      nixpkgs.config.allowUnfree = lib.mkForce settings.allowUnfree;
      networking.hostName = lib.mkForce settings.hostname;
      networking.networkmanager.enable = true; # Graphical Wi-Fi and Ethernet management.
      time.timeZone = lib.mkForce settings.timeZone;
      i18n.defaultLocale = lib.mkForce settings.locale;
      services.xserver.xkb.layout = lib.mkForce settings.keyboardLayout;
      hardware.bluetooth.enable = lib.mkForce settings.bluetooth;
      services.upower.enable = true; # Battery and power information for the desktop.
      services.tuned.enable = lib.mkForce settings.powerTuning; # Explicit host power policy.
      services.power-profiles-daemon.enable = lib.mkForce (!settings.powerTuning); # Desktop power profiles; never compete with tuned.
      services.flatpak.enable = lib.mkForce settings.flatpak; # Optional apps outside the curated bundles.
      services.printing = {
        enable = lib.mkForce settings.printing; # CUPS printer queues.
        drivers = lib.mkIf settings.printing [ pkgs.gutenprint ]; # Printers without driverless IPP support.
      };
      services.avahi = {
        enable = lib.mkForce settings.printing; # Local network printer discovery.
        nssmdns4 = lib.mkForce settings.printing; # Resolve printer .local hostnames.
        openFirewall = lib.mkForce settings.printing; # mDNS discovery on UDP 5353.
      };
      environment.systemPackages = lib.optional settings.printing pkgs.system-config-printer; # Printer setup GUI.
      services.pipewire = {
        enable = true; # Desktop audio and screen-capture transport.
        pulse.enable = true; # PulseAudio compatibility.
        wireplumber.enable = true; # Audio device/session policy.
        alsa.enable = true; # ALSA compatibility.
        alsa.support32Bit = true; # Older games and Wine audio.
      };
      security.rtkit.enable = true; # Bounded realtime scheduling for audio.
      system.stateVersion = lib.mkForce settings.stateVersion;
      users.mutableUsers = true; # Passwords managed with passwd, never in Git.
      users.users = lib.mapAttrs (
        name: user:
        {
          isNormalUser = true;
          description = lib.mkForce user.description;
          home = "/home/${name}";
          extraGroups = lib.mkForce (
            [ "networkmanager" ] ++ lib.optional user.admin "wheel" ++ user.extraGroups
          ); # Settings also support removing admin rights.
        }
        // lib.optionalAttrs (user.uid != null) { inherit (user) uid; }
      ) settings.users;
      home-manager = {
        useGlobalPkgs = true; # Share the system's stable package set.
        useUserPackages = true; # Packages visible in graphical sessions.
        backupFileExtension = "hm-backup"; # Preserve existing dotfiles on first activation.
        extraSpecialArgs = { inherit settings inputs; };
        users = lib.mapAttrs (name: user: {
          imports = [
            self.homeModules.core
            self.homeModules.applications
            self.homeModules.desktop
            self.homeModules.input-method
            self.homeModules.maintenance
          ];
          _module.args.account = user;
          home.username = name;
          home.homeDirectory = "/home/${name}";
          home.stateVersion = user.homeStateVersion;
        }) settings.users;
      };
    };
  flake.homeModules.core = { config, ... }: {
    programs.bash.enable = true; # Session variables and shell integration.
    xdg.enable = true; # Standard desktop configuration paths.
    xdg.userDirs = {
      enable = true; # Standard Desktop, Documents and Pictures paths.
      createDirectories = true; # Shortcut and screenshot destinations.
    };
    home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ]; # Personal scripts.
  };
}
