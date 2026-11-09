{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/k3s-server.nix
  ];

  networking.hostName = "kamatama";
  networking.hostId = "82762a99";
}
