# Udon: the Japan cluster's shared NixOS configuration
#
# hosts/{kamatama,niku} + modules/{base,k3s-server}.nix. Secrets via sops
# (secrets/japan.yaml, age keys derived from each host's SSH host key).
#
# ## Migrating a host onto this flake (small-ESP hosts)
#
# The hosts have small EFI partitions and they fill up with channel-era
# boot files. The NixOS sd-boot installer writes the new generation's
# kernel/initrd BEFORE pruning, so a full ESP makes the first
# `nixos-rebuild boot` fail mid-write (this is exactly how niku went down
# on 2026-11-09). The prune must happen while the OLD generation is
# still running:
#
#   1. Boot the host (old generation; a power cycle usually lands there).
#   2. Get the flake on the host (git clone, or nix run from the remote).
#   3. Verified ESP prune + space assertion (backs the ESP up first):
#        sudo nix --extra-experimental-features 'nix-command flakes' \
#          run /root/udon-flake#esp-prune
#      Abort conditions: any entry referencing missing files, or less than
#      160 MiB free after pruning (in which case the ESP is restored from
#      the backup the script just took). Adjust with ESP_MIN_FREE_MIB.
#   4. `sudo nixos-rebuild boot --flake /root/udon-flake#<host>`
#   5. Reboot. Expect the flake generation; roll back with the
#      generation-N entry the installer left for the old system if needed.
#   6. After trust is established, re-enable `allowReboot` (currently off
#      in modules/base.nix on purpose).
#
# If a rebuild still ENOSPCs the ESP, the machine may need hands-on
# recovery: restore the ESP from /var/backups/esp or /boot-bak and run
# `bootctl install` (see the cluster repo's docs/niku-outage.md runbook).
{
  description = "Udon: the Japan cluster's shared NixOS configuration";

  inputs = {
    # Same channel the hosts' original autoUpgrade tracked (26.05-pre, Yarara);
    # sops-nix tracks it via follows so only one nixpkgs closure is built.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , sops-nix
    , ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      espPrune = pkgs.writeShellScriptBin "esp-prune"
        (builtins.readFile ./scripts/esp-prune.sh);
    in
    {
      # Migration/maintenance tool: verified ESP prune for hosts with small
      # EFI partitions (run on the OLD generation, before the first
      # `nixos-rebuild boot --flake`; see README "Migrating a host").
      packages.${system} = {
        esp-prune = espPrune;
        default = espPrune;
      };

      nixosConfigurations = {
        kamatama = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            sops-nix.nixosModules.sops
            ./hosts/kamatama/configuration.nix
          ];
        };
        niku = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            sops-nix.nixosModules.sops
            ./hosts/niku/configuration.nix
          ];
        };
      };
    };
}
