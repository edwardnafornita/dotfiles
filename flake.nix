{
  description = "Minimal NixOS configuration";

  inputs = {
    dms.url = "github:AvengeMedia/DankMaterialShell";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
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
          ./modules/sway.nix
          ./modules/sddm.nix
          ./modules/gaming.nix
          ./modules/nh.nix

          home-manager.nixosModules.home-manager
          ./modules/home-manager.nix

          ./users
        ];
      };
    };
}
