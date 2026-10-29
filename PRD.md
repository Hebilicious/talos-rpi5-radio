# PRD: Talos Linux with Wi-Fi and Bluetooth on the Raspberry Pi 5

Status: draft, 29 October 2026. Nothing is built yet; this is the spec to build from.

## 1. Problem

The Raspberry Pi 5 has a Cypress/Infineon CYW43455 radio: Wi-Fi on an SDIO bus, Bluetooth on a
UART. The stock Talos Linux kernel for arm64 has neither stack. In
[siderolabs/pkgs `kernel/build/config-arm64`](https://github.com/siderolabs/pkgs/blob/main/kernel/build/config-arm64),
`CONFIG_CFG80211`, `CONFIG_WLAN`, `CONFIG_BT`, `CONFIG_RFKILL` and `CONFIG_SERIAL_DEV_BUS` are
unset, and [siderolabs/extensions](https://github.com/siderolabs/extensions) has no Wi-Fi,
Bluetooth or Broadcom firmware extension. A Pi 5 running Talos is therefore wired-only, with no
Bluetooth.

Who needs the radio:

- **Workloads that talk to Bluetooth LE devices** (sensors, speakers, home appliances) from the
  cluster itself, without a separate Bluetooth proxy on the network.
- **Placement:** with Wi-Fi, the node can run away from a network socket.

## 2. Goals

1. A Talos installer for the Pi 5 identical to the official one except for the radio: the same
   Talos version, the same `rpi_5` overlay, and any official extension the user adds.
2. Wi-Fi joins a WPA2/WPA3 network with credentials from the machine config, and gets its address
   from DHCP like Ethernet.
3. Bluetooth LE is usable from a pod: scan, connect, read, write, notify.
4. Every Talos release is rebuilt automatically at the same tag; upgrading a node is one
   `talosctl upgrade`.
5. Reproducible from this repository: the kernel options, the firmware versions, the extension and
   the CI workflow.

## 3. Non-goals

- Other boards, and Talos in virtual machines (a USB adapter passed to the VM, or a Bluetooth proxy
  on the network, covers those).
- Wi-Fi as an access point, Bluetooth audio, Classic Bluetooth profiles.
- Any kernel change beyond the options below.

## 4. Requirements

| # | Requirement |
|---|---|
| R1 | The kernel is Sidero Labs' kernel at the `siderolabs/pkgs` tag the Talos release pins, with only these options added, all built in (`=y`) so that no new module needs signing: `CONFIG_RFKILL`, `CONFIG_CFG80211`, `CONFIG_WLAN`, `CONFIG_BRCMFMAC`, `CONFIG_BRCMFMAC_SDIO`, `CONFIG_BT`, `CONFIG_BT_LE`, `CONFIG_BT_HCIUART`, `CONFIG_BT_HCIUART_SERDEV`, `CONFIG_BT_HCIUART_BCM`, `CONFIG_BT_BCM`, `CONFIG_SERIAL_DEV_BUS`, plus whatever `make olddefconfig` pulls in. |
| R2 | One system extension, `rpi5-radio`, carries the firmware (`brcmfmac43455-sdio.bin`, `.clm_blob`, the Pi 5's `.txt` board file, `BCM4345C0.hcd`, and `regulatory.db` with its signature) and runs `wpa_supplicant` as an extension service. |
| R3 | The Wi-Fi network name, password and country code reach `wpa_supplicant` through the machine config (an `ExtensionServiceConfig` file), never through the image. |
| R4 | Talos's network configuration runs DHCP on `wlan0` once it associates; Ethernet stays the preferred route when both are up. |
| R5 | BlueZ runs in a privileged pod on the host network (Bluetooth sockets aren't network-namespaced) and exposes D-Bus to the pods that use it; or the workload talks HCI directly. |
| R6 | CI in this repository rebuilds the kernel, the extension and the installer for each Talos release, and publishes them as public images on GitHub Container Registry. |
| R7 | Nothing else about Talos changes: same security settings, same upgrade and rollback behaviour. |

## 5. Design

```
siderolabs/pkgs @ the release's pkgs tag  ──(+ radio options)──────────▶ kernel image
siderolabs/talos @ the release tag        ──(PKG_KERNEL = our kernel)──▶ installer-base, imager
rpi5-radio extension (firmware, wpa_supplicant)
imager: installer-base + rpi_5 overlay + rpi5-radio (+ any official extension) ──▶ installer image
talosctl upgrade --image ghcr.io/hebilicious/talos-rpi5-radio/installer:<release>
```

### Repository layout

```
kernel/config-radio.fragment   the options of R1
extension/manifest.yaml        the rpi5-radio extension
extension/firmware/            firmware files and their licences
extension/wpa_supplicant.yaml  the extension service
.github/workflows/build.yaml   kernel, extension, installer and SD image per Talos release
renovate.json                  a pull request on each Talos release
PRD.md                         this document
```

### Building

- **Kernel:** check out siderolabs/pkgs at the tag the Talos release pins, append the fragment to
  `kernel/build/config-arm64`, and build the kernel target with Sidero's `bldr` tooling
  (`make kernel PLATFORM=linux/arm64`).
- **Talos:** check out siderolabs/talos at the release tag and build `installer-base` and `imager`
  with `PKG_KERNEL` pointing at our kernel image.
- **Installer:** run our imager with the `rpi_5` overlay and the `rpi5-radio` extension, for an SD
  card image (first install) and an installer image (upgrades).
- **CI runners:** GitHub's arm64 runners, free for public repositories, build natively.
- **Registry:** GitHub Container Registry, public packages, so nodes pull with no credentials.

### The device tree (to check first)

The `rpi_5` overlay ([siderolabs/sbc-raspberrypi](https://github.com/siderolabs/sbc-raspberrypi))
ships device trees built from the upstream kernel with a set of patches, plus overlays. Its only
Bluetooth overlay (`enable-bt-overlay.dts`) targets the Pi 4 (`brcm,bcm2711`). Whether its
`bcm2712-rpi-5-b.dtb` enables the SDIO controller wired to the radio, and the Bluetooth UART with
its `brcm,bcm43455-bt` child, is the first thing to check (`dtc -I dtb -O dts` on the overlay's
artifact). If either is missing, the extension adds a device-tree overlay for the Pi 5, applied
through the overlay's `config.txt`.

### Upgrades

1. Renovate opens a pull request when Talos releases.
2. CI builds and publishes the installer at the same version.
3. Users upgrade with `talosctl upgrade --image ghcr.io/hebilicious/talos-rpi5-radio/installer:<release>`.
4. If a node doesn't come back, Talos boots the previous version (A/B boot).

### Licences

This repository's own files are under MPL-2.0, like Talos and siderolabs/pkgs. The kernel is
GPL-2.0. The firmware files keep their own redistributable licences from linux-firmware
(Broadcom/Cypress) and wireless-regdb, copied next to them in `extension/firmware/`.

## 6. Milestones

1. **Device tree.** Decompile the overlay's Pi 5 device tree; list what is present for SDIO and
   the Bluetooth UART.
2. **Kernel boots.** Our kernel with the options, built locally, booted from an SD card:
   `talosctl dmesg` shows brcmfmac loading its firmware and the Bluetooth controller attaching.
3. **Wi-Fi.** The extension's `wpa_supplicant` associates; `wlan0` gets an address; with Ethernet
   unplugged the node stays reachable.
4. **Bluetooth.** A BlueZ pod scans and reads a GATT characteristic of a nearby device.
5. **CI and upgrades.** The workflow builds a release end to end; one upgrade and one rollback on a
   real Pi 5.

## 7. Done when

- A Pi 5 runs the published installer at the current Talos release, with Wi-Fi and Bluetooth
  working after a reboot.
- A new Talos release reaches users through a merged pull request, with no manual build.
- Nothing else about Talos changed, and no credential is in the image or the repository.

## 8. Risks

| Risk | Mitigation |
|---|---|
| The Pi 5 device tree lacks the radio nodes | Milestone 1 finds out first; a device-tree overlay in the extension |
| Kernel hardening (module signing, lockdown) rejects the drivers | Everything built in (R1), so no module loads at run time |
| Talos changes its build between releases | Pinned tags; CI fails loudly and users stay on the previous release |
| Wi-Fi and Ethernet both up confuse routing | Route metrics in the machine config; Ethernet first |
| Bluetooth LE devices accept one connection at a time, shared with phones | Workloads connect briefly and disconnect |
