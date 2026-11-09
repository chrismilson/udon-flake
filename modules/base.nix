# Baseline shared by every udon host: OS plumbing only.
#
# Responsibilities of this layer, per the division of responsibilities in the
# cluster repo's docs/nix-config-refactor.md:
#   - networking baseline (tailscale, sshd)
#   - the admin user + authorized keys
#   - sops secrets plumbing and flake-based auto-upgrade
# Workloads belong in k3s, not here.
{ config, lib, pkgs, ... }:

{
  time.timeZone = "Asia/Tokyo";

  # Both remote hosts boot via systemd-boot/EFI (matching the local configs
  # they replace).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # DHCP on the wired interface; see host files for specifics.
  networking.useDHCP = lib.mkDefault true;

  # Preserve current behaviour (firewall disabled on both hosts). Tightening
  # this is a deliberate TODO for the next iteration.
  networking.firewall.enable = lib.mkDefault false;

  # The onramp ("irasshai") key comes from the cluster side; its private key
  # never lives in this repo. The personal key is also listed so that being
  # locked out of the flake does not lock anyone out of the host.
  services.openssh.enable = true;

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
  };

  users.users.chris = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # irasshai onramp (managed as a k8s secret on the home cluster)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILkYMnqftlc7Z5xs7SJAl0pEBI7Z4JgNiZXe6dG0gGt/ irasshai"
      # personal laptop/home key (break-glass; also currently present in the
      # hosts' manual authorized_keys)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC6Rn44BKcRRPRo784yeXvs8NBEOprsF88npfPWC64qd"
    ];
    packages = with pkgs; [
      tree
      git
    ];
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
  ];

  # Secrets come from secrets/japan.yaml (sops). The age key is derived from
  # the host's /etc/ssh/ssh_host_ed25519_key (sops-nix default), so hosts only
  # need their existing SSH host key.
  sops.defaultSopsFile = ../secrets/japan.yaml;
  sops.secrets."k3s-token" = { };
  # WiFi backup link. "wpa-psk-env" is a PSK=<key> line consumed by the
  # wpa_supplicant environmentFile mechanism (psk "@"-substitution); "wifi-psk"
  # keeps the raw key for reference/other uses.
  sops.secrets."wpa-psk-env" = { };
  sops.secrets."wifi-psk" = { };

  # Flake-based updates replace the previous channel-based autoUpgrade.
  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
    flake = "github:chrismilson/udon-flake";
  };

  system.stateVersion = "25.05";
}
