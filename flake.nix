{
  description = "Minimal NixOS configuration";

  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=";
  };

  inputs = {
    dms.url = "github:AvengeMedia/DankMaterialShell";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    helium = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ctt-mybash = {
      url = "github:ChrisTitusTech/mybash";
      flake = false;
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia/cachix";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, dms, ... }:
    let
      system = "x86_64-linux";
      hostname = "nixos";
      username = "edi";
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = {
          inherit inputs;
        };

        modules = [
          ./configuration.nix
          ./modules/niri.nix
          ./modules/sddm.nix
          ./modules/gaming.nix
          ./modules/nh.nix
	  ./modules/helium.nix
	  ./modules/keyd.nix
	  ./modules/thunar.nix
	  ./modules/screenshots.nix

	  inputs.helium.nixosModules.default

          home-manager.nixosModules.home-manager
          ./modules/home-manager.nix

          ./users
        ];
      };
    };
}
