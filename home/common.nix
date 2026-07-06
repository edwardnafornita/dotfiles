{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    vim
    git
    curl
    wget
    tree
  ];

  programs.bash.enable = true;
}

