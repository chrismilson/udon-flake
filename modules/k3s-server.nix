# Server node module (kamatama).
{ config, ... }:

{
  networking.wireless.enable = true; # Ethernet is primary; WiFi is backup.
  networking.wireless.secretsFile =
    config.sops.secrets."wpa-secrets-file".path;
  networking.wireless.networks."ayay2022oct".pskRaw = "ext:wifi-psk";

  services.tailscale.extraSetFlags = [ "--advertise-routes=192.168.68.0/24" ];

  # --cluster-init: the cluster is bootstrapped from this node; the same shared
  # token in secrets keeps the agent node joined.
  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
    extraFlags = [ "--flannel-backend=host-gw" ];
    tokenFile = config.sops.secrets."k3s-token".path;
  };
}
