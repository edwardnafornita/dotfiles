{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
  mkSystem =
    settingsModule:
    let
      settings =
        (lib.evalModules {
          modules = [
            ../settings/options.nix
            ../settings/defaults.nix
            settingsModule
          ];
        }).config;
    in
    lib.nixosSystem {
      system = settings.system;
      specialArgs = { inherit settings inputs; };
      modules = [
        settings.machineModule
        self.nixosModules.core
        self.nixosModules.applications
        self.nixosModules.desktop
        self.nixosModules.maintenance
        self.nixosModules.recovery
      ];
    };
in
{
  flake.lib.mkSystem = mkSystem;
  # Git flakes omit ignored local settings. Never fall back to a generic hostname
  # such as "nixos": require an explicit maintainer output when local is absent.
  flake.nixosConfigurations =
    if builtins.pathExists ../settings/local/default.nix then
      let
        machine = mkSystem ../settings/local/default.nix;
      in
      { local = machine; } // { ${machine.config.networking.hostName} = machine; }
    else
      { edi-nixos = mkSystem ../settings/hosts/nixos.nix; };
}
