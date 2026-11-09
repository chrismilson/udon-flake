{
  imports = [
    ./hardware-configuration.nix
    ../modules/base.nix
  ];

  networking.hostName = "niku";

  services.resolved.enable = true;

  # Agent node: joins the k3s master over the LAN (never the tailnet). If the
  # LAN addressing ever changes, this and the static LAN IP expectations are
  # the place to look.
  services.k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://192.168.68.62:6443";
    tokenFile = config.sops.secrets."k3s-token".path;
  };

  users.users.chris.packages = with pkgs; [
    btop
    nmap
  ];
}
