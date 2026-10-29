#!/usr/bin/env bash
# Sends a Pi in a tryboot test boot (Talos maintenance mode) back to Raspberry Pi OS.
#
# Maintenance mode doesn't allow a reboot without credentials, so this applies a
# throwaway worker config with no install document. Talos runs its install step,
# which fails because the test boot sees no disk (tryboot-overlay.dts hides the SD
# card), and Talos reboots; the firmware then boots Raspberry Pi OS again.
# Only use it while the SD card is hidden: check that the kernel log has no
# "mmc0: new ... SD" line first.
#
# usage: recover.sh <talos ip>
set -euo pipefail

ip=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

talosctl() {
  docker run --rm --network host --user "$(id -u):$(id -g)" -v "$work:/work" -w /work \
    ghcr.io/siderolabs/talosctl:v1.14.5 "$@"
}

talosctl gen config tryboot-recovery https://127.0.0.1:6443 --output-types worker --output /work/worker.yaml >/dev/null

# drop the install document, so nothing selects a disk
awk 'BEGIN { RS = "\n---\n"; ORS = "\n---\n" } !/(^|\n)kind: UnattendedInstallConfig\n/' \
  "$work/worker.yaml" > "$work/recovery.yaml"

talosctl apply-config --insecure -n "$ip" -e "$ip" --file /work/recovery.yaml
echo "applied; Talos reboots once its install step fails (about 50 seconds)"
