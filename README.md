# talos-rpi5-radio

[Talos Linux](https://www.talos.dev) for the Raspberry Pi 5 with its Wi-Fi and Bluetooth working.
The stock Talos kernel for arm64 has no Wi-Fi or Bluetooth stack; this repository builds the
official kernel with those options added as modules, a system extension with those modules, the
radio's firmware and `wpa_supplicant`, and an installer for each stable Talos release. Official
extensions that ship kernel modules don't load on this kernel.

[PRD.md](PRD.md) is the specification. Status: the kernel and the extension are built by CI
and boot on a Pi 5 with Wi-Fi and Bluetooth attached (PRD milestone 2); Wi-Fi association,
the Bluetooth pod and releases are not done yet.

On the Pi 5 the Wi-Fi link is named `wld0` (predictable interface names); select it by driver
(`brcmfmac`) in the machine config rather than by name.

Licence: [MPL-2.0](LICENSE) for this repository's files. The kernel is GPL-2.0; firmware files keep
their own licences.
