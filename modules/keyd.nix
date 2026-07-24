{ pkgs, ... }:

{
  services.keyd = {
    enable = true;

    keyboards.default = {
      ids = [ "*" ];

      settings.main = {
        leftmeta = "overload(meta, M-space)";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    keyd
  ];
}

