{ config, pkgs, ... }:

let
  activeRice = ./rices/dank-material.nix;
in
{
  imports = [
    activeRice
    ./home/gaming.nix
  ];

  home.username = "edi";
  home.homeDirectory = "/home/edi";

  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    tree
    vim
    curl
    gh
    git
    wget
  ];

  programs.bash.enable = true;
}

