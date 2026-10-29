#!/usr/bin/env bash
# Stages a one-shot RAM boot of a Talos build on a Raspberry Pi 5 that runs
# Raspberry Pi OS, through the firmware's tryboot: the next
# `systemctl reboot --reboot-argument='0 tryboot'`
# boots Talos once, and any reboot after that boots Raspberry Pi OS again.
#
# The test boot changes nothing on the Pi's disks: a device-tree overlay hides
# the SD card controller from the kernel (tryboot-overlay.dts), and Talos runs from RAM in
# maintenance mode.
#
# usage: stage.sh <artifacts dir> <dtb dir> <ssh host> <log ip>
#   artifacts dir: the CI artifact: kernel-arm64, initramfs-metal-arm64.xz and
#                  cmdline-metal-arm64, each optionally zstd-compressed (.zst)
#   dtb dir:       the rpi_5 overlay's bcm2712*.dtb (artifacts/rpi_5 in the overlay image)
#   log ip:        this machine's address on the Pi's Ethernet network. The kernel
#                  sends its console there from boot (netconsole, UDP 6666), and
#                  Talos streams its kernel log there (UDP 5140); receive-logs.py
#                  listens on both.
set -euo pipefail

artifacts=$1
dtbs=$2
host=$3
log_ip=$4

# netconsole needs the Pi's Ethernet address and this machine's MAC address
pi_ip=$(ssh "$host" "ip -4 -o addr show eth0" | awk '{ split($4, a, "/"); print a[1] }')
log_device=$(ip -o route get "$pi_ip" | sed -nE 's/.* dev ([^ ]+).*/\1/p')
log_mac=$(cat "/sys/class/net/$log_device/address")

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# the imager compresses its outputs with zstd
asset() {
  if [[ -f $artifacts/$1.zst ]]; then
    zstd -q -d -c "$artifacts/$1.zst" > "$2"
  else
    cp "$artifacts/$1" "$2"
  fi
}

asset kernel-arm64 "$work/vmlinuz"
asset initramfs-metal-arm64.xz "$work/initramfs.xz"
asset cmdline-metal-arm64 "$work/cmdline-metal-arm64"

python3 -I "$here/extract-image.py" "$work/vmlinuz" "$work/Image"
rm "$work/vmlinuz"
cp "$dtbs"/bcm2712*.dtb "$work/"
cp "$here/tryboot-overlay.dts" "$work/"

# Talos's own kernel arguments, plus the two log streams and a reboot on panic.
echo "$(cat "$work/cmdline-metal-arm64") talos.logging.kernel=udp://${log_ip}:5140" \
  "netconsole=6665@${pi_ip}/eth0,6666@${log_ip}/${log_mac} panic=30" > "$work/cmdline.txt"

cat > "$work/tryboot.txt" <<'TXT'
# One-shot test boot of talos-rpi5-radio (hack/tryboot/stage.sh).
[all]
arm_64bit=1
arm_boost=1
os_prefix=talos-tryboot/
kernel=Image
initramfs initramfs.xz followkernel
cmdline=cmdline.txt
dtoverlay=talos-tryboot
TXT

ssh "$host" 'rm -rf /tmp/talos-tryboot && mkdir -p /tmp/talos-tryboot'
scp -q "$work"/* "$host:/tmp/talos-tryboot/"

ssh "$host" 'set -e
  cd /tmp/talos-tryboot
  dtc -q -@ -I dts -O dtb -o talos-tryboot.dtbo tryboot-overlay.dts
  sudo rm -rf /boot/firmware/talos-tryboot
  sudo mkdir -p /boot/firmware/talos-tryboot
  # The firmware prepends the device trees /chosen/bootargs to the command line.
  # They include cgroup_disable=memory, which stops Talos; a real install boots
  # through U-Boot and GRUB, which pass only Talos arguments. Clear them in the
  # test copies (an overlay is applied too late for this).
  for dtb in bcm2712*.dtb; do fdtput -t s "$dtb" /chosen bootargs ""; done
  sudo cp Image initramfs.xz cmdline.txt bcm2712*.dtb /boot/firmware/talos-tryboot/
  # the firmware loads overlays from the top-level overlays/ even with os_prefix
  sudo cp talos-tryboot.dtbo /boot/firmware/overlays/talos-tryboot.dtbo
  sudo cp tryboot.txt /boot/firmware/tryboot.txt
  rm -rf /tmp/talos-tryboot
  ls -la /boot/firmware/talos-tryboot /boot/firmware/tryboot.txt /boot/firmware/overlays/talos-tryboot.dtbo'

echo "staged; boot it once with: ssh $host \"sudo systemctl reboot --reboot-argument='0 tryboot'\""
