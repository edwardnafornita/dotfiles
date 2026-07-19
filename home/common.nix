{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    btop
    vim
    git
    gh
    curl
    wget
    tree
  ];

  programs.bash.enable = true;
}

