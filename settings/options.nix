{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  option =
    type: default: description:
    mkOption { inherit type default description; };
in
{
  options = {
    hostname = option types.str "nixos" "Network hostname; the local flake output remains named local.";
    system = option (types.enum [ "x86_64-linux" ]) "x86_64-linux" "Supported CPU platform.";
    machineModule = mkOption {
      type = types.path;
      description = "Machine-only NixOS module for hardware and boot configuration.";
    };
    stateVersion =
      option types.str "26.05"
        "Original NixOS install version; do not increase to update packages.";
    timeZone = option types.str "America/Toronto" "Local clock timezone.";
    locale = option types.str "en_US.UTF-8" "System language and formatting.";
    keyboardLayout = option types.str "us" "XKB layout for login screen and compositors.";
    desktop = option (types.enum [
      "plasma"
      "niri"
      "hyprland"
    ]) "plasma" "Desktop environment or compositor; shell selects its panel/launcher.";
    shell =
      option
        (types.enum [
          "none"
          "noctalia"
          "caelestia"
          "inir"
        ])
        (
          {
            plasma = "none";
            niri = "noctalia";
            hyprland = "caelestia";
          }
          .${config.desktop}
        )
        "Desktop shell: Plasma uses none, Niri supports Noctalia or iNiR, Hyprland supports Noctalia or Caelestia.";
    browser = option (types.enum [
      "firefox"
      "helium"
    ]) "firefox" "Browser installed and used by compositor shortcuts.";
    allowUnfree =
      option types.bool false
        "Accept proprietary licenses (Steam, Spotify, Rider and VS Code require this).";
    bluetooth = option types.bool true "Bluetooth headphones, mice and controllers.";
    printing = option types.bool true "CUPS and local network printer discovery.";
    flatpak = option types.bool true "Allow graphical applications installed through Flatpak.";
    btrfsSnapshots =
      option types.bool false
        "Snapper snapshots for separate Btrfs root/home subvolumes; enabled by fresh installs, never converts disks.";
    secureBoot =
      option types.bool false
        "Signed Limine bootloader with machine-local keys; firmware enrollment is performed by the fresh installer.";
    xboxControllers = option types.bool false "Xbox USB/wireless and Bluetooth controller drivers.";
    powerTuning = option types.bool false "Use tuned, preserving Edi's power management choice.";
    sddmAstronaut = option types.bool false "Use the existing Astronaut SDDM theme.";
    metaTapLauncher =
      option types.bool false
        "Map tapped left Super to Super+Space in compositor sessions using keyd.";
    niriOutputs = option types.lines "" "Niri monitor blocks; empty uses automatic detection.";
    hyprlandMonitors = option (types.listOf types.str) [
      ",preferred,auto,1"
    ] "Hyprland monitor rules.";
    updates = {
      repository =
        option types.str "https://github.com/edwardnafornita/dotfiles.git"
          "Trusted configuration update repository.";
      branch = option types.str "main" "Branch containing reviewed configuration and lockfile.";
      checkout = option types.str "dotfiles" "Checkout directory relative to each user's home.";
      output = option types.str "local" "Flake output used by update-system and apply-system.";
    };
    users = option (types.attrsOf (
      types.submodule (
        { name, ... }: {
          options = {
            description = option types.str name "Account display name.";
            admin = option types.bool false "Allow sudo through wheel membership.";
            uid = option (types.nullOr types.int) null "Optional fixed UID; preserve existing file ownership.";
            extraGroups = option (types.listOf types.str) [ ] "Additional Unix groups needed by this account.";
            appGroups = option (types.listOf types.str) [
              "essentials"
              "desktop"
            ] "Bundles in settings/applications.nix.";
            extraPackages =
              option (types.listOf types.str) [ ]
                "Extra nixpkgs attribute paths, e.g. libreoffice or kdePackages.kate.";
            bash = option (types.enum [
              "standard"
              "ctt"
            ]) "standard" "Standard Bash or Chris Titus Tech's customization.";
            koreanInput =
              option types.bool false
                "Enable user-only Fcitx5 Korean Dubeolsik input; Ctrl+Space toggles US English/Korean.";
            homeStateVersion =
              option types.str "26.05"
                "Original Home Manager version; leave unchanged during upgrades.";
          };
        }
      )
    )) { } "Accounts keyed by login name. Passwords stay outside Git and the Nix store.";
  };
}
