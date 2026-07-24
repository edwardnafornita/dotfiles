{ pkgs, ... }:

{
  programs.thunar = {
    enable = true;

    plugins = with pkgs; [
      thunar-archive-plugin
      thunar-volman
    ];
  };

  programs.xfconf.enable = true;

  services.gvfs.enable = true;

  services.tumbler.enable = true;

  environment.systemPackages = with pkgs; [
    file-roller
  ];
}

