#!/usr/bin/env bash
# Removes what stage.sh put on the Pi's boot partition.
# usage: unstage.sh <ssh host>
set -euo pipefail

ssh "$1" 'sudo rm -rf /boot/firmware/talos-tryboot /boot/firmware/tryboot.txt /boot/firmware/overlays/talos-tryboot.dtbo && echo unstaged'
