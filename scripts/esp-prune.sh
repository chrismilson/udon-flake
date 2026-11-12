#!/usr/bin/env bash
# esp-prune: verified ESP maintenance for small-EFI-partition hosts (udon).
#
# Why this exists: the NixOS sd-boot installer writes the new generation's
# kernel/initrd BEFORE it prunes anything it can no longer reference. On a
# small, full ESP (both Japan hosts have tiny ESPs, and they fill up over
# channel-era generations) the first flake-based `nixos-rebuild boot` hits
# ENOSPC mid-write, leaving a half-written ESP that cannot boot any
# generation. The prune must therefore happen while the old generation is
# still running, before the flake rebuild.
#
# What it does, in order:
#   1. Verify every existing boot entry's linux/initrd files exist on the
#      ESP (the "verified boot files" rule). Aborts if not.
#   2. Back the whole ESP up to the root filesystem (default
#      /var/backups/esp/esp-<timestamp>), so every step is reversible.
#   3. Delete files under <ESP>/EFI/nixos that no entry references.
#   4. Assert the ESP now has >= MIN_FREE_MIB free; if not, RESTORE the ESP
#      from the backup and abort. No half-states, ever.
#
# Run this on the old (currently booting) generation, before the first
# `nixos-rebuild boot --flake ...#<host>`. Also safe to run any time the
# ESP gets tight (e.g. kamatama at 100% full).
#
# Env overrides:
#   ESP_MIN_FREE_MIB  minimum free MiB to assert (default 160)
#   ESP_BACKUP_DIR    backup base dir (default /var/backups/esp)

set -euo pipefail

ESP_MIN_FREE_MIB="${ESP_MIN_FREE_MIB:-160}"
ESP_BACKUP_DIR="${ESP_BACKUP_DIR:-/var/backups/esp}"
BOOT_DIR="/boot"

say() { printf 'esp-prune: %s\n' "$*"; }
die() { printf 'esp-prune: FATAL: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root (sudo)"
[ -d "$BOOT_DIR/loader/entries" ] || die "$BOOT_DIR does not look like a systemd-boot ESP (no loader/entries)"
findmnt "$BOOT_DIR" >/dev/null || die "$BOOT_DIR is not mounted"
fs_type="$(findmnt -n -o FSTYPE "$BOOT_DIR")"
[ "$fs_type" = "vfat" ] || die "$BOOT_DIR is not vfat (got: $fs_type) — refusing"

free_mib() { df -Pm --output=avail "$BOOT_DIR" | tail -1 | tr -dc '0-9'; }

# --- 1. verify every entry's referenced files exist -----------------------
entries=$(find "$BOOT_DIR/loader/entries" -name '*.conf' | sort)
[ -n "$entries" ] || die "no boot entries found — nothing to verify"
missing=0
for conf in $entries; do
  for key in linux initrd devicetree; do
    for ref in $(grep -E "^$key[[:space:]]" "$conf" 2>/dev/null | awk '{print $2}'); do
      if [ ! -e "$BOOT_DIR$ref" ]; then
        say "MISSING: $conf references $ref (not on ESP)"
        missing=1
      fi
    done
  done
done
[ "$missing" = 0 ] || die "one or more entries reference missing files; do NOT prune.
  Restore the ESP from a known-good backup first (e.g. /boot-bak, see
  docs/niku-outage.md) and re-verify before pruning."

# --- 2. full ESP backup to the root filesystem ----------------------------
mkdir -p "$ESP_BACKUP_DIR"
ts=$(date +%Y%m%d-%H%M%S)
bak="$ESP_BACKUP_DIR/esp-$ts"
mkdir -p "$bak"
say "backing up ESP to $bak ..."
cp -a "$BOOT_DIR/." "$bak/"
say "backup complete ($(du -sh "$bak" | cut -f1))"

# --- 3. delete unreferenced files under EFI/nixos -------------------------
referenced=$(mktemp)
for conf in $entries; do
  grep -E '^(linux|initrd|devicetree)[[:space:]]' "$conf" | awk '{print $2}' >> "$referenced"
done
freed_bytes=0
freed_files=0
find "$BOOT_DIR/EFI/nixos" -mindepth 1 -maxdepth 1 -type f | while read -r f; do
  base=$(basename "$f")
  if ! grep -qF -- "$base" "$referenced"; then
    sz=$(stat -c '%s' "$f")
    rm -f -- "$f"
    printf 'removed %s (%s bytes)\n' "$base" "$sz"
  fi
done
rm -f "$referenced"

# --- 4. assert free space; restore + abort if unmet ------------------------
now_free=$(free_mib)
if [ "$now_free" -lt "$ESP_MIN_FREE_MIB" ]; then
  say "only ${now_free}MiB free (< ${ESP_MIN_FREE_MIB}MiB) — restoring ESP from backup"
  cp -a "$bak/." "$BOOT_DIR/"
  die "could not free ${ESP_MIN_FREE_MIB}MiB on the ESP; ESP restored from $bak.
  Options: delete a full backup dir on the ESP if any (none expected),
  grow the ESP partition (needs hands-on session), or investigate what
  else is consuming the ESP: sudo du -ah --max-depth=2 /boot | sort -rh"
fi

avail=$(df -h "$BOOT_DIR" | awk 'NR==2{print $4}')
say "done: ESP now has $avail free (>= ${ESP_MIN_FREE_MIB}MiB), backup kept at $bak"

# --- 5. report-only: non-NixOS content on the ESP -------------------------
other=$(find "$BOOT_DIR/EFI" -mindepth 1 -maxdepth 1 -type d \
        ! -name nixos ! -name BOOT ! -name systemd)
if [ -n "$other" ]; then
  say "NOTE: non-NixOS directories on the ESP (not touched, review manually):"
  for d in $other; do say "  $d ($(du -sh "$d" 2>/dev/null | cut -f1))"; fi
fi

say "next: nixos-rebuild boot --flake <flake>#<host>, then reboot, then verify."
