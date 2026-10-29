#!/usr/bin/env bash
# Resolves what a Talos release pins, for the build (PRD section 5, "Building").
#
# usage: pins.sh <talos version>
# Prints KEY=value lines: TALOS, PKGS, PKGS_COMMIT, OVERLAY_IMAGE.
set -euo pipefail

talos=$1

pkgs=$(curl -fsSL "https://raw.githubusercontent.com/siderolabs/talos/${talos}/Makefile" \
  | sed -nE 's/^PKGS \?= (.+)$/\1/p')

if [[ -z $pkgs ]]; then
  echo "no PKGS in Talos ${talos}'s Makefile" >&2
  exit 1
fi

# v1.14.0-48-gf4bda77 -> f4bda77; a plain tag stays a tag
if [[ $pkgs =~ -g([0-9a-f]+)$ ]]; then
  pkgs_commit=${BASH_REMATCH[1]}
else
  pkgs_commit=$pkgs
fi

# The rpi_5 overlay Sidero pins for this release, from ghcr.io/siderolabs/overlays:<release>.
container=$(docker create "ghcr.io/siderolabs/overlays:${talos}" /none)
overlays=$(docker cp "${container}:/overlays.yaml" - | tar -xO)
docker rm "${container}" >/dev/null

# entries are "- name:", "image:" and "digest:" lines
overlay=$(awk '
  $1 == "-" && $2 == "name:" { name = $3 }
  name == "rpi_5" && $1 == "image:" { image = $2 }
  name == "rpi_5" && $1 == "digest:" { print image "@" $2; exit }
' <<<"$overlays")

if [[ -z $overlay ]]; then
  echo "no rpi_5 overlay in ghcr.io/siderolabs/overlays:${talos}" >&2
  exit 1
fi

echo "TALOS=${talos}"
echo "PKGS=${pkgs}"
echo "PKGS_COMMIT=${pkgs_commit}"
echo "OVERLAY_IMAGE=${overlay}"
