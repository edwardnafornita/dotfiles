{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.dms.homeModules.dank-material-shell
  ];

  programs.dank-material-shell = {
    enable = true;
  };

  home.packages = with pkgs; [
    foot
    wl-clipboard
  ];

  home.file.".config/sway/config".text = ''
    include /etc/sway/config.d/*

    set $mod Mod4
    set $term foot

    exec dms run

    bindsym $mod+Return exec $term
    bindsym $mod+Space exec dms ipc call spotlight toggle
    bindsym $mod+Shift+e exit

    input * {
      xkb_layout us
    }
  '';
}

