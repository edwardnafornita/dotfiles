{ pkgs, ... }: {
  # Model a previous graphical installer configuration; its hardware stays local.
  imports = [ ./machine.nix ];
  system.stateVersion = "25.11";
  services.printing.enable = true; # The new settings must be able to disable this.
  hardware.bluetooth.enable = true;
  services.flatpak.enable = true;
  networking.hostName = "previous-host";
  time.timeZone = "Europe/Paris";
  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm.enable = true;
  services.displayManager.sddm.enable = false;
  services.displayManager.sddm.wayland.enable = true; # Preserve installer greeter mode without a conflict.
  services.xserver.xkb.layout = "de";
  users.users.alice = {
    isNormalUser = true;
    description = "Previous display name";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };
  environment.systemPackages = [ pkgs.firefox ]; # Existing installer browser is preserved.
}
