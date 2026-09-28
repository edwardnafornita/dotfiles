{
  description = "Shared NixOS desktops with private machine settings";
  inputs = {
    # Preserve the existing stable pins during this refactor.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    helium = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ctt-mybash = {
      url = "github:ChrisTitusTech/mybash";
      flake = false;
    };
    # Shells retain upstream nixpkgs for their newer UI dependencies.
    # Only the selected desktop installs its shell.
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
    caelestia.url = "github:caelestia-dots/shell";
  };
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      # Explicit imports: adding a file alone never enables a service.
      imports = [
        inputs.home-manager.flakeModules.home-manager
        ./modules/core.nix
        ./modules/applications.nix
        ./modules/desktop.nix
        ./modules/maintenance.nix
        ./modules/hosts.nix
        ./modules/checks.nix
      ];
      perSystem = { pkgs, ... }: {
        formatter = pkgs.nixfmt; # Shared formatter for maintainers and CI.
      };
    };
}
