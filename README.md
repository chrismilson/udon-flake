# udon-flake

Shared NixOS configuration for the Japan k3s pair (`kamatama` = k3s server /
cluster-init, `niku` = agent). The OS layer is deliberately minimal — it
provides the networking/storage baseline and boots the cluster; everything
else (workloads, volumes) lives in k3s, managed from the home cluster.

## Layout

- `flake.nix` — `nixosConfigurations.kamatama` / `niko`
- `hosts/<name>/` — hardware scan + small per-host bits
- `modules/base.nix` — baseline: sshd, tailscale, admin user + SSH keys, sops
  plumbing, flake-based auto-upgrade
- `modules/k3s-{server,agent}.nix` — k3s roles (cluster traffic stays on the
  LAN, never the tailnet)
- `secrets/` — sops-encrypted (`secrets/japan.yaml`), recipient list in
  `.sops.yaml`

## Secrets

Decrypted by [sops-nix](https://github.com/Mic92/sops-nix) at activation.
No `age.keyFile` is configured: sops-nix derives each host's age key from its
existing `/etc/ssh/ssh_host_ed25519_key`. To edit secrets, decrypt/edit with
`sops secrets/japan.yaml` from any machine that holds one of the recipient
keys (i.e., from either host after first activation, or locally after adding
your own key to `.sops.yaml`).

Current keys: `k3s-token` (the shared cluster token; changing it means
rejoining `niku`), `wifi-psk` (rendered into a `wpa-psk-file` template that
`networking.wireless` consumes).

## Bootstrap (first install / migration)

1. Bring the host onto the flake:
   ```sh
   sudo nixos-rebuild switch --flake 'github:chrismilson/udon-flake#kamatama'
   ```
   (Run once with the local checkout while migrating, so the first `switch`
   pulls secrets; later `system.autoUpgrade` tracks the repo directly.)
2. The activation decrypts `secrets/japan.yaml` using the host SSH host key
   and writes `/run/secrets/*`.

## Updating

`system.autoUpgrade` (with `allowReboot`) pulls this flake on a schedule.
Push to `main` and hosts follow.

## Notes

- The flake-defined admin `authorizedKeys` replaces whatever is in
  `~/.ssh/authorized_keys` at rebuild time; include any manual key additions
  in `modules/base.nix` before switching or they will be lost.
- TODO: re-enable/tighten `networking.firewall` (both hosts currently run
  with it fully disabled, preserved from the local configs).
