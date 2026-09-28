{ inputs, ... }: {
  flake.nixosModules.applications =
    {
      lib,
      pkgs,
      settings,
      ...
    }:
    let
      gaming = lib.any (u: builtins.elem "gaming" u.appGroups) (builtins.attrValues settings.users);
    in
    {
      imports = [ inputs.helium.nixosModules.default ];
      programs.firefox.enable = settings.browser == "firefox"; # Default supported browser.
      programs.helium = lib.mkIf (settings.browser == "helium") {
        enable = true; # Preserve Edi's selected browser.
        flags = [
          "--ozone-platform-hint=auto"
          "--enable-features=TouchpadOverscrollHistoryNavigation"
        ];
      };
      hardware.xone.enable = settings.xboxControllers; # Xbox USB and wireless adapter driver.
      hardware.xpadneo.enable = settings.xboxControllers; # Xbox Bluetooth driver.
      hardware.graphics = {
        enable = true; # Accelerated desktop rendering.
        enable32Bit = gaming; # 32-bit Wine/Steam graphics.
      };
      hardware.uinput.enable = gaming; # Controller input emulation for games.
      hardware.steam-hardware.enable = gaming; # Steam controller/device permissions.
      services.udev.packages = lib.optional gaming pkgs.game-devices-udev-rules; # Controller access rules.
      programs.steam = lib.mkIf gaming {
        enable = true; # Steam and its NixOS runtime integration.
        extest.enable = true; # Controller-to-pointer support under Wayland.
        extraCompatPackages = with pkgs; [
          proton-ge-bin # Community Proton fixes for Windows games.
          dwproton-bin # Alternative Proton compatibility runner already used by Edi.
        ];
        extraPackages = with pkgs; [
          gamescope # Per-game nested compositor.
          mangohud # Performance overlay within Steam's environment.
          gamemode # Request gaming performance policy.
        ];
      };
      programs.gamemode.enable = gaming; # Temporary performance policy while games run.
      programs.gamescope = lib.mkIf gaming {
        enable = true; # Per-game resolution/scaling control.
        capSysNice = true; # Scheduling capability required by Gamescope.
      };
      fonts.packages =
        with pkgs;
        [
          liberation_ttf # Metric-compatible document fonts.
          dejavu_fonts # Broad Latin/Greek/Cyrillic coverage.
          noto-fonts # General Unicode coverage.
          noto-fonts-cjk-sans # CJK text in applications and games.
        ]
        ++ lib.optional gaming corefonts; # Microsoft fonts expected by some Windows games.
      environment.systemPackages = lib.optionals gaming (
        with pkgs;
        [
          gamescope # Standalone nested compositor outside the Steam wrapper.
          mangohud # Game performance overlay outside Steam.
          goverlay # Graphical MangoHud configuration.
          wineWow64Packages.stable # Run Windows applications outside Proton.
          winetricks # Install common Wine runtime components.
          vulkan-tools # Diagnose Vulkan support.
          mesa-demos # Diagnose OpenGL support.
          pciutils # Identify GPU and PCI hardware.
          usbutils # Identify controllers and USB hardware.
        ]
      );
    };
  flake.homeModules.applications =
    {
      lib,
      pkgs,
      account,
      inputs,
      ...
    }:
    let
      bundles = import ../settings/applications.nix pkgs;
      development = builtins.elem "development" account.appGroups;
    in
    {
      assertions = [
        {
          assertion = lib.all (name: builtins.hasAttr name bundles) account.appGroups;
          message = "Unknown application bundle; see settings/applications.nix.";
        }
      ];
      home.packages =
        lib.concatMap (name: bundles.${name}) account.appGroups
        ++ map (
          name: lib.attrByPath (lib.splitString "." name) (throw "Unknown extra package: ${name}") pkgs
        ) account.extraPackages
        ++ lib.optionals (account.bash == "ctt") (
          with pkgs;
          [
            bash-completion # Completion functions used by the CTT shell.
            starship # CTT prompt renderer.
            fzf # Fuzzy history/file selection.
            zoxide # Directory navigation history.
            fastfetch # System information display.
            neovim # Editor expected by CTT aliases.
            nerd-fonts.meslo-lg # Prompt icon glyphs.
          ]
        );
      programs.direnv = lib.mkIf development {
        enable = true; # Load explicitly approved project environments.
        nix-direnv.enable = true; # Cache Nix development environments.
      };
      home.sessionVariables = lib.mkIf development {
        DOTNET_ROOT = "${pkgs.dotnet-sdk_10}/share/dotnet";
        DOTNET_CLI_TELEMETRY_OPTOUT = "1";
        DOTNET_NOLOGO = "1";
      };
      programs.bash.initExtra = lib.mkIf (account.bash == "ctt") ''
        source ${inputs.ctt-mybash}/.bashrc
      '';
      home.file = lib.mkIf (account.bash == "ctt") {
        ".config/starship.toml".source = "${inputs.ctt-mybash}/starship.toml";
        ".config/fastfetch/config.jsonc".source = "${inputs.ctt-mybash}/config.jsonc";
      };
    };
}
