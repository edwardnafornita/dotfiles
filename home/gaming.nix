{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    lutris
    heroic
    bottles

    prismlauncher
    r2modman

    qbittorrent

    p7zip
    unzip
    unrar
    file-roller
  ];
}

