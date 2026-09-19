#!/usr/bin/env bash
# Bootstraps this repo onto a fresh NixOS install.
#
# Usage (run as your normal user, from a TTY after the base NixOS install
# is done and this repo has been cloned):
#
#   ./install.sh
#
# What it does:
#   1. Generates hardware-configuration.nix for this machine (if missing).
#   2. Stages it in git so the flake (which only sees tracked files) can see it.
#   3. Points /etc/nixos at this repo (backing up whatever was there).
#   4. Runs `nixos-rebuild switch --flake`.
#
# After it finishes, log in and run `passwd` to set your account password.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTNAME="nixosStream" # must match the hostname key in flake.nix

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user (it will call sudo itself), not as root." >&2
  exit 1
fi

if ! command -v git >/dev/null; then
  echo "git not found on PATH. Something is very wrong on a fresh NixOS install." >&2
  exit 1
fi

cd "$REPO_DIR"

if [[ ! -f hardware-configuration.nix ]]; then
  echo "==> Generating hardware-configuration.nix for this machine..."
  sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
else
  echo "==> hardware-configuration.nix already present, leaving it alone."
fi

echo "==> Staging hardware-configuration.nix in git (flakes only see tracked files)..."
git add hardware-configuration.nix

if [[ -e /etc/nixos && ! -L /etc/nixos ]]; then
  BACKUP="/etc/nixos.bak.$(date +%s)"
  echo "==> Backing up existing /etc/nixos to $BACKUP"
  sudo mv /etc/nixos "$BACKUP"
fi

if [[ -L /etc/nixos ]]; then
  echo "==> /etc/nixos is already a symlink, replacing it with one to $REPO_DIR"
  sudo rm /etc/nixos
fi

echo "==> Linking /etc/nixos -> $REPO_DIR"
sudo ln -s "$REPO_DIR" /etc/nixos

echo "==> Running nixos-rebuild switch (this will take a while on first run)..."
sudo nixos-rebuild switch --flake "$REPO_DIR#$HOSTNAME"

echo "==> Done. Log in, then run 'passwd' to set your account password if you haven't already."
