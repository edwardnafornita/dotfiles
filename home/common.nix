{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    vim
    git
    gh
    curl
    wget
    tree
  ];

  programs.bash.enable = true;
}

