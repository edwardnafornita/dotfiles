pkgs: {
  # Edit packages here; select bundles per account in settings/hosts or settings/local.
  essentials = with pkgs; [
    btop # CPU, memory and process monitor.
    vim # Terminal editor for configuration and recovery.
    git # Version control and configuration updates.
    gh # GitHub repository maintenance.
    curl # HTTP requests and terminal downloads.
    wget # Download files from URLs.
    tree # Inspect directory layouts.
  ];
  desktop = with pkgs; [
    libreoffice # Documents, spreadsheets and presentations.
    vlc # Play common audio and video formats.
    kdePackages.kate # Graphical text and configuration editor.
  ];
  gaming = with pkgs; [
    lutris # Game library and Wine runner manager.
    heroic # Epic, GOG and Amazon launcher.
    bottles # Isolated Wine environments.
    prismlauncher # Minecraft instances and mod packs.
    r2modman # Mod manager for supported games.
    qbittorrent # Torrents, including large game/mod distributions.
    p7zip # Extract 7z installers and mods.
    unzip # Extract ZIP archives.
    unrar # Extract RAR archives; proprietary license.
    file-roller # Graphical archive management.
    vesktop # Discord-compatible client with Wayland screen sharing.
  ];
  development = with pkgs; [
    jetbrains.rider # .NET IDE; proprietary license may be required.
    vscode # General-purpose editor; Microsoft distribution.
    dotnet-sdk_10 # Build and run .NET 10 projects.
    docker-compose # Compose client; does not enable a Docker daemon.
    openssl # TLS and cryptography development tools.
    postgresql # Database client/development binaries; no database service.
    claude-code # Claude Code for AI driven development.
  ];
  media = with pkgs; [
    spotify # Spotify desktop client; proprietary.
  ];
}
