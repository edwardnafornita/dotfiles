{ config, pkgs, inputs, ... }:

let
  activeRice = ../rices/noctalia.nix;
in
{
  imports = [
    ../home/common.nix
    ../home/gaming.nix
    ../home/update-system.nix
    ../home/ctt-bash.nix
    activeRice
  ];

  home.username = "edi";
  home.homeDirectory = "/home/edi";

  home.stateVersion = "26.05";
}

