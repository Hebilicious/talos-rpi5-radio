# talos-rpi5-radio

[Talos Linux](https://www.talos.dev) for the Raspberry Pi 5 with its Wi-Fi and Bluetooth working.
The stock Talos kernel for arm64 has no Wi-Fi or Bluetooth stack; this repository builds the
official kernel with those options added as modules, a system extension with those modules, the
radio's firmware and `wpa_supplicant`, and an installer for each stable Talos release.

[PRD.md](PRD.md) is the specification. Status: the kernel and the extension are built by CI
and boot on a Pi 5 with Wi-Fi and Bluetooth attached (PRD milestone 2); Wi-Fi association,
the Bluetooth pod and releases are not done yet.

## Images

Published for each Talos release, public, for arm64 (`<release>` is e.g. `v1.14.5`; every CI
run also publishes `<release>-<commit>`):

| Image | What it is |
|---|---|
| `ghcr.io/hebilicious/talos-rpi5-radio/installer:<release>` | The installer: our kernel, the `rpi_5` overlay, `rpi5-radio`. For `talosctl upgrade` and the machine config's installer image |
| `ghcr.io/hebilicious/talos-rpi5-radio/imager:<release>` | Talos's imager with our kernel, to build images with more extensions |
| `ghcr.io/hebilicious/talos-rpi5-radio/installer-base:<release>` | The imager's base for installers |
| `ghcr.io/hebilicious/talos-rpi5-radio/rpi5-radio:<release>` | The system extension |

The SD card image (`metal-arm64.raw.zst`) is the `talos-rpi5-radio-<release>-<commit>` artifact
of the CI run.

## Using it

Image Factory can't build these images: its schematics always use Sidero's kernel. Build them
with our imager instead. Its arguments are the schematic's: the `rpi_5` overlay at the version
Sidero pins for the release (`overlays.yaml` in `ghcr.io/siderolabs/overlays:<release>`), our
extension, and any official extensions (from `ghcr.io/siderolabs/extensions:<release>`).
For example, with Tailscale on v1.14.5:

```sh
imager_args=(
  --arch arm64
  --overlay-image ghcr.io/siderolabs/sbc-raspberrypi:v0.2.2@sha256:af82d9f97241fb66c5b660b03e9154fd54ba4560b58ed3b53765bb930d564167
  --overlay-name rpi_5
  --system-extension-image ghcr.io/hebilicious/talos-rpi5-radio/rpi5-radio:v1.14.5
  --system-extension-image ghcr.io/siderolabs/tailscale:1.102.3@sha256:669bcfe20aa99a8c47e890e4819826baca9ad78a807910a757791bb0c86cf9e8
)
imager=ghcr.io/hebilicious/talos-rpi5-radio/imager:v1.14.5

# SD card image for the first install (_out/metal-arm64.raw.zst)
docker run --rm --privileged --platform linux/arm64 -v /dev:/dev -v "$PWD/_out:/out" \
  "$imager" metal "${imager_args[@]}"

# installer for upgrades (_out/installer-arm64.tar; push it to a registry the node can pull)
docker run --rm --platform linux/arm64 -v "$PWD/_out:/out" \
  "$imager" installer "${imager_args[@]}" \
  --base-installer-image ghcr.io/hebilicious/talos-rpi5-radio/installer-base:v1.14.5
```

On an x86_64 machine `--platform linux/arm64` runs the imager under QEMU; the installer above
takes about a minute and a half.

- **Installer image:** point the machine config's installer image at an installer built this way
  (or at `installer:<release>` without extra extensions), and upgrade with
  `talosctl upgrade --image <it>`. An Image Factory installer would bring back Sidero's kernel,
  without the radios.
- **Official extensions:** extensions without kernel modules work (Tailscale was checked:
  it ships none, and the installer above builds). Extensions that ship kernel modules (zfs,
  drbd, nvidia, …) don't load: Talos enforces module signatures, and they are signed for
  Sidero's kernel. Kernel modules Talos itself ships (tun, macvlan, NFS, …) come from our
  kernel build and load as usual.
- **Wi-Fi link:** on the Pi 5 it is named `wld0` (predictable interface names). Select it by
  driver (`brcmfmac`) in the machine config rather than by name.
- **Nothing else changes:** the kernel is Sidero's, at the pkgs commit the release pins, with
  only the options in [kernel/config-radio.fragment](kernel/config-radio.fragment).

Licence: [MPL-2.0](LICENSE) for this repository's files. The kernel is GPL-2.0; firmware files keep
their own licences.
