# The full upstream iNiR Niri rice, adapted only for the selected machine.
{
  inputs,
  pkgs,
  settings,
  ...
}:
let
  port = inputs.inir-nixos;
  runtimePkgs = port.inputs.nixpkgs.legacyPackages.${settings.system};
  rice =
    pkgs.runCommand "inir-niri-config-checked"
      {
        nativeBuildInputs = [ runtimePkgs.niri ];
      }
      ''
        mkdir -p "$out/config.d"
        cp ${port}/niri/config.kdl "$out/config.kdl"
        cp ${port}/niri/config.d/*.kdl "$out/config.d/"
        chmod -R u+w "$out"
        cp ${
          pkgs.writeText "inir-input.kdl" (
            builtins.replaceStrings
              [
                "layout \"latam,us\""
                ''
                  output "eDP-1" {
                      scale 1.0
                  }''
              ]
              [ "layout \"${settings.keyboardLayout}\"" "" ]
              (builtins.readFile "${port}/niri/config.d/10-input-and-cursor.kdl")
          )
        } \
          "$out/config.d/10-input-and-cursor.kdl"
        chmod u+w "$out/config.d/10-input-and-cursor.kdl"
        cat ${pkgs.writeText "inir-outputs.kdl" settings.niriOutputs} >> "$out/config.d/10-input-and-cursor.kdl"
        niri validate --config "$out/config.kdl"
      '';
in
{
  home.packages = [ pkgs.alacritty ];
  # Exposed for validation; activation copies this to writable user files.
  home.file.".local/share/dotfiles/inir-niri".source = rice;
}
