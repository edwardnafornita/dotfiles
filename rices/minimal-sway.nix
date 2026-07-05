{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    foot
    quickshell
    wl-clipboard
  ];

  home.file.".config/sway/config".text = ''
    include /etc/sway/config.d/*

    set $mod Mod4
    set $term foot

    output * bg #111111 solid_color

    exec quickshell

    bindsym $mod+Return exec $term
    bindsym $mod+q kill
    bindsym $mod+Shift+e exit

    input * {
      xkb_layout us
    }
  '';

  home.file.".config/quickshell/shell.qml".text = ''
    import Quickshell
    import QtQuick

    PanelWindow {
      anchors {
        top: true
        left: true
        right: true
      }

      implicitHeight: 32

      Text {
        anchors.centerIn: parent
        text: "minimal-sway"
      }
    }
  '';
}
