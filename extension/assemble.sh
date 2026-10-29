#!/bin/sh
# Assembles the rpi5-radio extension's rootfs in /rootfs. Runs inside the
# extension's build stage (extension/Dockerfile).
#
# Inputs: /kernel (our kernel image), /linux-firmware (Sidero's linux-firmware
# image at the pkgs commit Talos pins), /src (this directory).
set -eu

rootfs=/rootfs
firmware=$rootfs/usr/lib/firmware

# Kernel modules: the radio stacks of kernel/config-radio.fragment, from the same
# kernel build, so they are signed with its key.
kernel_version=$(ls /kernel/usr/lib/modules)
modules=/kernel/usr/lib/modules/$kernel_version

for dir in kernel/net/rfkill kernel/net/wireless kernel/net/bluetooth \
  kernel/drivers/net/wireless/broadcom kernel/drivers/bluetooth; do
  mkdir -p "$rootfs/usr/lib/modules/$kernel_version/$dir"
  cp -R "$modules/$dir/." "$rootfs/usr/lib/modules/$kernel_version/$dir/"
done

# Wi-Fi firmware. Sidero's linux-firmware image ships no symlinks, so the
# Cypress files are copied to the brcm/ names the driver asks for, and the
# Pi 5 board file is linux-firmware's Pi 4 one (upstream it is a link to it).
mkdir -p "$firmware/brcm" "$firmware/licences"
cp /linux-firmware/usr/lib/firmware/cypress/cyfmac43455-sdio.bin "$firmware/brcm/brcmfmac43455-sdio.bin"
cp /linux-firmware/usr/lib/firmware/cypress/cyfmac43455-sdio.clm_blob "$firmware/brcm/brcmfmac43455-sdio.clm_blob"
cp "/linux-firmware/usr/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt" \
  "$firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.txt"

# Bluetooth firmware and the regulatory database, committed in firmware/.
cp /src/firmware/BCM4345C0.hcd "$firmware/brcm/BCM4345C0.hcd"
cp /src/firmware/regulatory.db /src/firmware/regulatory.db.p7s "$firmware/"
cp /src/firmware/LICENCE.cypress /src/firmware/GPL-2.0 /src/firmware/LICENSE.wireless-regdb \
  /src/firmware/SOURCES "$firmware/licences/"

# The wpa_supplicant extension service: its definition, and a minimal rootfs
# with wpa_supplicant, its libraries and the busybox applets the start script uses.
mkdir -p "$rootfs/usr/local/etc/containers"
cp /src/wpa_supplicant.yaml "$rootfs/usr/local/etc/containers/wpa_supplicant.yaml"

container=$rootfs/usr/local/lib/containers/wpa_supplicant
mkdir -p "$container/bin" "$container/usr/local/bin" "$container/etc/wpa_supplicant" "$container/run"

for binary in "$(command -v wpa_supplicant)" "$(command -v wpa_cli)" /bin/busybox; do
  cp "$binary" "$container/bin/"

  # copy the shared libraries each binary loads, at the same paths
  ldd "$binary" | awk '/=>/ { print $3 } /^\t\// { print $1 }' | while read -r library; do
    mkdir -p "$container$(dirname "$library")"
    cp -L "$library" "$container$library"
  done
done

for applet in sh basename readlink sleep mkdir; do
  ln -s busybox "$container/bin/$applet"
done

cp /src/start-wpa-supplicant "$container/usr/local/bin/start-wpa-supplicant"

# the ExtensionServiceConfig file is bind-mounted here; the rootfs is read-only,
# so the mount target must exist
touch "$container/etc/wpa_supplicant/wpa_supplicant.conf"

# Talos rejects extensions with world-writable files.
chmod -R go-w "$rootfs"
