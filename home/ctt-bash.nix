{ config, pkgs, inputs, ... }:

{
  home.packages = with pkgs; [
    bash-completion
    starship
    fzf
    zoxide
    fastfetch
    neovim
    nerd-fonts.meslo-lg
  ];

  programs.bash = {
    enable = true;

    initExtra = ''
      if [ -f ${inputs.ctt-mybash}/.bashrc ]; then
        source ${inputs.ctt-mybash}/.bashrc
      fi
    '';
  };

  home.file.".config/starship.toml".source = "${inputs.ctt-mybash}/starship.toml";
  home.file.".config/fastfetch/config.jsonc".source = "${inputs.ctt-mybash}/config.jsonc";
}

