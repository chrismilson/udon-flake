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
    {
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
