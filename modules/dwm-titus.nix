{ config, pkgs, inputs, ... }:

let
  dwm-titus = pkgs.stdenv.mkDerivation {
    pname = "dwm-titus";
    version = "git";

    src = inputs.ctt-dwm;

    nativeBuildInputs = with pkgs; [
      pkg-config
      makeWrapper
    ];

    buildInputs = with pkgs; [
      xorg.libX11
      xorg.libXft
      xorg.libXinerama
      xorg.libXrender
      xorg.libxcb
      xorg.xcbutil
      xorg.xcbutilwm
      imlib2
      fontconfig
      freetype
    ];

    buildPhase = ''
      runHook preBuild
      make
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      install -Dm755 dwm $out/bin/dwm-titus

      if [ -d scripts ]; then
        for f in scripts/*; do
	  if [ -f "$f" ]; then
	    install -Dm755 "$f" "$out/bin/$(basename "$f")" || true
	  fi
	done
      fi

      mkdir -p $out/share/xsessions
      cat > $out/share/xsessions/dwm-titus.desktop <<EOF
      [Desktop Entry]
      Name=dwm-titus
      Comment=Chris Titus Tech dwm session
      Exec=$out/bin/dwm-titus
      Type=Animation
      DesktopNames=dwm
      EOF

      runHook postInstall
    '';
  };
in
{
  services.xserver.enable = true;

  services.displayManager.sessionPackages = [
    dwm-titus
  ];

  environment.systemPackages = with pkgs; [
    dwm-titus

    xorg.xinit
    xorg.xrdb
    xorg.xrandr
    xorg.xsetroot
    xorg.xprop
    xclip

    picom
    feh
    rofi
    dunst

    alacritty
    st
  ];
}

