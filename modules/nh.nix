{ config, pkgs, ... }:

{
  programs.nh = {
    enable = true;

    flake = "~/dotfiles";

    clean = {
      enable = true;
      extraArgs = "--keep-since 7d --keep 5";
    };
  };
}

