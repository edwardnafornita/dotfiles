{ pkgs, ... }:

{
  home.packages = with pkgs; [
    jetbrains.rider
    dotnet-sdk_10
    docker-compose
    openssl
    postgresql
  ];

  home.sessionVariables = {
    DOTNET_ROOT = "${pkgs.dotnet-sdk_10}/share/dotnet";
    DOTNET_CLI_TELEMETRY_OPTOUT = "1";
    DOTNET_NOLOGO = "1";
  };
}

