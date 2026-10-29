# PRD: Talos Linux with Wi-Fi and Bluetooth on the Raspberry Pi 5

Status: draft, 29 October 2026, audited against Talos v1.14.5. Milestone 1 is done (section 5);
nothing else is built yet. This is the spec to build from.

## 1. Problem

The Raspberry Pi 5 has a Cypress/Infineon CYW43455 radio: Wi-Fi on an SDIO bus, Bluetooth on a
UART. The stock Talos Linux kernel for arm64 has neither stack. In
[siderolabs/pkgs `kernel/build/config-arm64`](https://github.com/siderolabs/pkgs/blob/main/kernel/build/config-arm64),
`CONFIG_CFG80211`, `CONFIG_WLAN`, `CONFIG_BT`, `CONFIG_RFKILL` and `CONFIG_SERIAL_DEV_BUS` are
unset, and [siderolabs/extensions](https://github.com/siderolabs/extensions) has no Wi-Fi,
Bluetooth or Broadcom firmware extension. A Pi 5 running Talos is therefore wired-only, with no
Bluetooth.

Upstream is not going to add it: Sidero Labs declined Wi-Fi in Talos in
[siderolabs/talos#14224](https://github.com/siderolabs/talos/issues/14224) (September 2026),
because the wireless stack is a large attack surface and Wi-Fi can't be configured before the
machine config arrives. That issue's forks (Intel Wi-Fi on amd64, with Talos source changes) have
`wpa-supplicant` and `wireless-regdb` package recipes worth reusing; this project changes no Talos
source.

Who needs the radio:

- **Workloads that talk to Bluetooth LE devices** (sensors, speakers, home appliances) from the
  cluster itself, without a separate Bluetooth proxy on the network.
- **Placement:** with Wi-Fi, the node can run away from a network socket once it is installed.

## 2. Goals

1. A Talos installer for the Pi 5 identical to the official one except for the radio: the same
   Talos version, the same `rpi_5` overlay at the version Sidero pins for that release, and any
   official extension the user adds that ships no kernel modules (see R7).
2. Wi-Fi joins a WPA2 network, and a WPA3 network if the CYW43455 firmware supports it (verified
   in milestone 3), with credentials from the machine config, and gets its address from DHCP like
   Ethernet.
3. Bluetooth LE is usable from a pod: scan, connect, read, write, notify.
4. Every stable Talos release on the newest minor line (no alphas, betas or release candidates) is
   rebuilt automatically at the same tag; upgrading a node is one `talosctl upgrade`.
5. Reproducible from this repository: the kernel options, the firmware versions, the extension, the
   Bluetooth pod and the CI workflow.

## 3. Non-goals

- Other boards, and Talos in virtual machines (a USB adapter passed to the VM, or a Bluetooth proxy
  on the network, covers those).
- Wi-Fi as an access point, Bluetooth audio, Classic Bluetooth profiles.
- A first install over Wi-Fi alone: the first boot uses Ethernet (section 5, "First install").
- Official extensions that ship kernel modules (zfs, drbd, nvidia, …): they are signed for Sidero's
  kernel and won't load on this one (R7).
- Older Talos minor lines and pre-releases.
- Any change to Talos's source, and any kernel change beyond the options below.

## 4. Requirements

| # | Requirement |
|---|---|
| R1 | The kernel is Sidero Labs' kernel at the `siderolabs/pkgs` commit the Talos release pins (`PKGS` in Talos's `Makefile`, e.g. `v1.14.0-48-gf4bda77` for v1.14.5; it is a commit, not a tag), with only these options added. As modules (`=m`): `CONFIG_RFKILL`, `CONFIG_CFG80211`, `CONFIG_BRCMFMAC`, `CONFIG_BT`, `CONFIG_BT_HCIUART`. Built in (`=y`): `CONFIG_WLAN`, `CONFIG_WLAN_VENDOR_BROADCOM`, `CONFIG_BRCMFMAC_SDIO`, `CONFIG_BT_LE`, `CONFIG_BT_HCIUART_BCM`, `CONFIG_SERIAL_DEV_BUS`, `CONFIG_SERIAL_DEV_CTRL_TTYPORT`. Plus whatever `make olddefconfig` pulls in (`CONFIG_BT_BCM`, `CONFIG_BT_HCIUART_SERDEV`, the signed-regdb options). CI fails if any listed option is missing from the final config. |
| R2 | One system extension, `rpi5-radio`, carries: the radio's kernel modules, copied from the same kernel build (so they're signed with its key); the firmware under `/usr/lib/firmware`; and `wpa_supplicant`, run as an extension service. Firmware: `brcm/brcmfmac43455-sdio.bin` and `.clm_blob`, `brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.txt`, `brcm/BCM4345C0.hcd`, and `regulatory.db` with `regulatory.db.p7s`. |
| R3 | The Wi-Fi network name, password and country code reach `wpa_supplicant` through the machine config (an `ExtensionServiceConfig` document for the `wpa_supplicant` service), never through the image or this repository. |
| R4 | Talos's network configuration runs DHCP on the Wi-Fi link once it associates. The link is selected with a `deviceSelector` on `driver: brcmfmac`, never by an assumed name such as `wlan0`. Ethernet stays the preferred route when both are up (a higher route metric on Wi-Fi). |
| R5 | BlueZ runs in a privileged pod on the host network, because the kernel only creates Bluetooth sockets in the host's network namespace. Talos has no system D-Bus, so the pod runs its own `dbus-daemon` beside `bluetoothd` and shares the D-Bus socket with the pods that use it through a `hostPath` under `/var`. A workload may instead talk HCI directly, with `hostNetwork` and `NET_ADMIN`/`NET_RAW`. The image and manifests live in this repository. |
| R6 | CI in this repository rebuilds the kernel, the extension, the installer and the SD card image for each release in scope (Goal 4), on GitHub's arm64 runners, and publishes them as public images on GitHub Container Registry. |
| R7 | Nothing else about Talos changes: same Talos source, same kernel command line (including `module.sig_enforce=1`), same upgrade and rollback behaviour. Only the kernel image differs. Because each kernel build signs its modules with a key it then throws away, official extensions that ship kernel modules don't load on this kernel; that is accepted and documented in the README. |

## 5. Design

```
talos @ release tag ── Makefile PKGS ──▶ pkgs commit
pkgs @ that commit ──(+ radio fragment, olddefconfig, check)──▶ kernel image
talos @ release tag ──(PKG_KERNEL = our kernel)──▶ installer-base, imager
our kernel's radio modules + firmware + wpa_supplicant ──▶ rpi5-radio extension
ghcr.io/siderolabs/overlays:<release> ──▶ pinned rpi_5 overlay (sbc-raspberrypi)
imager: installer-base + rpi_5 overlay + rpi5-radio (+ official extensions) ──▶ installer, SD image
talosctl upgrade --image ghcr.io/hebilicious/talos-rpi5-radio/installer:<release>
```

### Repository layout

```
talos-version                   the Talos release built (Renovate bumps it)
kernel/config-radio.fragment    the options of R1
kernel/check-config.sh          fails if an option of the fragment is missing after olddefconfig
extension/manifest.yaml         the rpi5-radio extension metadata
extension/Dockerfile            builds the extension: modules from our kernel, firmware, wpa_supplicant
extension/wpa_supplicant.yaml   the extension service
extension/firmware/             firmware files, their licences, and SOURCES (origin, commit, sha256)
bluetooth/Dockerfile            the BlueZ image (dbus-daemon + bluetoothd)
bluetooth/daemonset.yaml        the BlueZ pod (R5)
examples/machine-config.yaml    Wi-Fi, route metrics and the module load, with placeholder credentials
.github/workflows/build.yaml    kernel, extension, installer and SD image per release
renovate.json                   a pull request on each stable Talos release
PRD.md                          this document
```

### Building

- **Pins:** read `talos-version`, check out siderolabs/talos at that tag, and take the pkgs commit
  from the hash in its `PKGS` (`v1.14.0-48-gf4bda77` → `f4bda77`). Read the `rpi_5` overlay image
  and digest from `overlays.yaml` in `ghcr.io/siderolabs/overlays:<release>` (v1.14.5:
  `ghcr.io/siderolabs/sbc-raspberrypi:v0.2.2@sha256:af82d9f9…`), and official extensions from
  `ghcr.io/siderolabs/extensions:<release>`.
- **Kernel config:** pkgs builds with the committed config as is; its build runs no
  `olddefconfig`. So append the fragment to `kernel/build/config-arm64`, run `olddefconfig`
  through pkgs (`make local-kernel-build TARGET_ARGS="--build-arg=KERNEL_TARGET=olddefconfig"
  PLATFORM=linux/arm64 DEST=kernel/build`, the arm64 half of `make kernel-olddefconfig`), then run
  `kernel/check-config.sh`.
- **Kernel:** `make kernel PLATFORM=linux/arm64 REGISTRY=ghcr.io
  USERNAME=hebilicious/talos-rpi5-radio PUSH=true`. The build runs Sidero's
  `kernel-hardening-checker` filter; the new options must pass it unchanged.
- **Talos:** `make installer-base imager PLATFORM=linux/arm64 INSTALLER_ARCH=targetarch
  PKG_KERNEL=<our kernel image> REGISTRY=ghcr.io USERNAME=hebilicious/talos-rpi5-radio PUSH=true`.
  `INSTALLER_ARCH` defaults to `all`, which would also build amd64 boot assets from a kernel we
  publish only for arm64. Nothing else is overridden.
- **Extension:** copy from our kernel image's `/usr/lib/modules/<version>/kernel/` the modules of
  `net/rfkill`, `net/wireless`, `net/bluetooth`, `drivers/net/wireless/broadcom/brcm80211` and
  `drivers/bluetooth` that the R1 options produce, with their dependencies. Add the firmware, and
  `wpa_supplicant` built from a pinned release with the `nl80211` driver and SAE. The imager runs
  `depmod` over extension modules. Talos's own image keeps only the modules listed in its
  `hack/modules-arm64.txt`, so this is how the modules get onto the node without changing Talos.
- **Installer:** run our imager with the overlay (`--overlay-image`, `--overlay-name rpi_5`) and
  `--system-extension-image` for `rpi5-radio`, once for the SD card image (first install) and once
  for the installer image (upgrades).
- **CI runners:** GitHub's arm64 runners (`ubuntu-24.04-arm`), free for public repositories, build
  natively. Development builds run there too: on an x86_64 machine the arm64 kernel builds under
  QEMU, which takes hours.
- **Registry:** GitHub Container Registry, public packages, so nodes pull with no credentials. The
  workflow pushes images with `GITHUB_TOKEN` (`packages: write`). It opens no pull requests and
  pushes no tags; if that changes, it uses the `heb-release` GitHub App's token.

### The device tree (milestone 1, done)

The `rpi_5` overlay ([siderolabs/sbc-raspberrypi](https://github.com/siderolabs/sbc-raspberrypi))
builds its device trees from the Raspberry Pi kernel (`raspberrypi/linux`, `stable_20260724` in
v0.2.2) with ten patches. The Pi firmware loads them from the boot partition and U-Boot passes
them on. The overlay also ships Raspberry Pi's full set of device-tree overlays, including
`enable-bt-pi5`, `disable-bt-pi5` and `disable-wifi-pi5`.

Decompiling `bcm2712-rpi-5-b.dtb` and `bcm2712d0-rpi-5-b.dtb` (D0 stepping, e.g. Rev 1.1 boards)
from v0.2.2 shows both radios enabled, identically in both files:

| Radio | Node | Kernel 6.18 driver (pinned config) |
|---|---|---|
| Wi-Fi controller | `mmc@1100000`, `brcm,bcm2712-sdhci`, `non-removable`, powered by `wl-on-reg` (`regulator-fixed`, GPIO) | `sdhci-brcmstb` (`=m`, in Talos's image), `REGULATOR_FIXED_VOLTAGE=y` |
| Wi-Fi chip | `wifi@1`, `brcm,bcm4329-fmac` | `brcmfmac` (R1) |
| Bluetooth UART | `serial@7d50c000`, `brcm,bcm7271-uart` (an 8250 UART, not PL011) | `SERIAL_8250_BCM7271=y` |
| Bluetooth chip | its child `bluetooth`, `brcm,bcm43438-bt`, `shutdown-gpios` | `hci_uart` with `BT_HCIUART_BCM` (R1), `GPIO_BRCMSTB=y` |

No device-tree overlay is needed. If one were ever needed, it couldn't come from the extension:
extensions land in the root filesystem, while the Pi firmware reads overlays from the boot
partition, which the overlay's installer writes (it accepts extra `config.txt` lines through its
`configTxtAppend` option).

### Modules, not built in

Extension files appear only after Talos's init mounts the extension layers. Anything that runs
during kernel boot can't see them.

- **Bluetooth:** the UART driver is built in. A built-in `hci_uart` would register the controller
  and run its setup, including loading the `BCM4345C0` firmware patch, during kernel boot. The
  patch wouldn't be found, and the chip would stay on its ROM firmware.
- **cfg80211:** if built in, it looks for `regulatory.db` during kernel boot, before the file is
  there.
- **Modules** are loaded by udev from their device aliases after the extensions are mounted, so
  the firmware is in place. The serial-bus options are booleans and stay built in. That only
  creates the Bluetooth device; its driver loads later.
- **Modules the kernel asks for:** a modular `brcmfmac` asks the kernel for its vendor module
  (`brcmfmac-wcc` for the 43455) with `request_module()`. The kernel is built with
  `CONFIG_MODPROBE_PATH=""`, but Talos sets `kernel.modprobe` to its own helper at run time, which
  loads requests by plain module name (it doesn't resolve aliases). So `brcmfmac-wcc` loads on
  demand; milestone 2 checks that it does.

The kernel asks for these firmware names, board-specific first:
`brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.{bin,clm_blob,txt}`, then
`brcm/brcmfmac43455-sdio.{bin,clm_blob,txt}`. For Bluetooth it asks for
`brcm/BCM4345C0.raspberrypi,5-model-b.hcd`, then `brcm/BCM4345C0.hcd`. The extension ships the
generic `.bin`, `.clm_blob` and `.hcd` and the Pi 5 `.txt`.

### Firmware sources

| Files | Source | Licence |
|---|---|---|
| `brcmfmac43455-sdio.bin`, `.clm_blob` | linux-firmware `cypress/cyfmac43455-sdio.*`, at the version pkgs pins | `LICENCE.cypress` |
| `brcmfmac43455-sdio.raspberrypi,5-model-b.txt` | linux-firmware; upstream it is a link to the Pi 4 board file, shipped here as a regular file | as `WHENCE` states for it |
| `BCM4345C0.hcd` | [RPi-Distro/bluez-firmware](https://github.com/RPi-Distro/bluez-firmware) `debian/firmware/broadcom/`, at a pinned commit (not in linux-firmware) | `LICENSE.cypress` there |
| `regulatory.db`, `regulatory.db.p7s` | wireless-regdb, at a pinned release (not in linux-firmware) | wireless-regdb `LICENSE` |

`extension/firmware/SOURCES` records the origin, commit and sha256 of every file.

### First install

The Wi-Fi credentials arrive with the machine config, and the machine config is applied over the
network, so the first boot uses Ethernet:

1. Flash the SD card image and boot the Pi on Ethernet.
2. Apply a machine config with the `wpa_supplicant` `ExtensionServiceConfig`, the Wi-Fi link's DHCP
   settings (`examples/machine-config.yaml`).
3. Once Wi-Fi has an address, Ethernet can be unplugged.

Talos's `talos.config.inline` and `talos.config.early` kernel arguments could carry the
credentials for a Wi-Fi-only first boot, but that puts them on the boot media; it is out of scope.

### Upgrades

1. Renovate opens a pull request bumping `talos-version` when a stable Talos release appears on the
   newest minor line.
2. CI builds the pull request; merging it publishes the installer at the same version.
3. Users upgrade with `talosctl upgrade --image ghcr.io/hebilicious/talos-rpi5-radio/installer:<release>`.
   The upgrade keeps the kernel command line, including `module.sig_enforce`.
4. Talos keeps the previous version on its other boot entry. If the new version boots but Talos
   fails before the machine reaches Running, Talos switches back to the previous entry itself.
   If the kernel hangs, or the node boots but is unreachable (for example Wi-Fi doesn't come up),
   nothing switches back automatically: recover over Ethernet with `talosctl rollback`, or pick
   the previous entry in GRUB from a keyboard and screen.

### Licences

This repository's own files are under MPL-2.0, like Talos and siderolabs/pkgs. The kernel and its
modules are GPL-2.0. `wpa_supplicant` is BSD-3-Clause and BlueZ is GPL-2.0; each image carries its
licence. The firmware files keep their own redistributable licences (table above), copied next to
them in `extension/firmware/`.

## 6. Milestones

Hardware tests use a Pi 5 booted from an SD card set aside for this project, with Ethernet
connected.

1. **Device tree.** Done: section 5.
2. **Kernel boots.** Our kernel with the options, built on GitHub's arm64 runners, and the
   extension, booted from an SD card: `talosctl dmesg` shows `brcmfmac` loading its firmware and
   `hci0` loading `BCM4345C0.hcd` ("Patch").
3. **Wi-Fi.** The extension's `wpa_supplicant` associates with a WPA2 network, and with a WPA3
   network if the firmware supports it (otherwise the README says WPA2 only). The Wi-Fi link gets
   an address, and with Ethernet unplugged the node stays reachable. The link's real name is
   recorded in the README.
4. **Bluetooth.** The BlueZ pod scans and reads a GATT characteristic of a nearby device, and a
   second pod does the same through the shared D-Bus socket.
5. **CI and upgrades.** The workflow builds a release end to end from a Renovate pull request; one
   upgrade on a real Pi 5, and one recovery by the manual procedure of section 5, "Upgrades".

## 7. Done when

- A Pi 5 runs the published installer at the current Talos release, with Wi-Fi and Bluetooth
  working after a reboot.
- A new stable Talos release reaches users through a merged pull request, with no manual build.
- Nothing else about Talos changed, and no credential is in the image or the repository.

## 8. Risks

| Risk | Mitigation |
|---|---|
| The Wi-Fi and Bluetooth stacks add attack surface to the node (Sidero's reason for declining them) | Only nodes that run this installer carry them; the README says so |
| A future overlay drops or changes the radio nodes | CI decompiles the pinned overlay's Pi 5 device trees and fails if the nodes of section 5 are missing |
| The firmware loads before the extension is mounted | Radio stacks are modules (R1); milestone 2 checks the "Patch" line |
| `brcmfmac` can't load its vendor module | Talos's helper loads it by name; milestone 2 checks it, and a `KernelModuleConfig` for `brcmfmac-wcc` is the fallback |
| An upgrade leaves the node hung or unreachable | Manual recovery over Ethernet or the GRUB menu (section 5, "Upgrades") |
| Users add an official extension with kernel modules | Non-goal; README lists it; the module fails signature checks and Talos reports it |
| A new option fails Sidero's hardening check, or `olddefconfig` drops one | `kernel/check-config.sh` and the build fail loudly; users stay on the previous release |
| Talos changes its build between releases | Pinned tags and commits; CI fails loudly and users stay on the previous release |
| WPA3 doesn't work on the CYW43455 with the mainline driver | Tested in milestone 3; WPA2 is the documented fallback |
| The Wi-Fi link's name is not `wlan0` | Selected by driver, never by name (R4) |
| Wi-Fi and Ethernet both up confuse routing | Route metrics in the machine config; Ethernet first |
| Bluetooth LE devices accept one connection at a time, shared with phones | Workloads connect briefly and disconnect |
