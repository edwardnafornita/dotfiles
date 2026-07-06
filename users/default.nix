{ lib, ... }:

let
  mkUser = {
    username,
    description ? username,
    isAdmin ? false,
    extraGroups ? [ ],
    homeModule ? ./. + "${username}.nix",
  }: {
    users.users.${username} = {
      isNormalUser = true;
      description = description;

      extraGroups = [
        "networkmanager"
        "video"
        "audio"
      ]
      ++ extraGroups
      ++ lib.optionals isAdmin [ "wheel" ];
    };

    home-manager.users.${username} = import homeModule;
  };
in
lib.mkMerge [
  (mkUser {
    username = "edi";
    description = "Edi";
    isAdmin = true;
  })
]
