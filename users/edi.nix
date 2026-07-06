{ config, pkgs, inputs, ... }:

let
  activeRice = ../rices/dank-material.nix;
in
{
  imports = [
    ../home/common.nix
    ../home/gaming.nix
    ../home/update-system.nix
    activeRice
  ];

  home.username = "edi";
  home.homeDirectory = "/home/edi";

  home.stateVersion = "26.05";
}

