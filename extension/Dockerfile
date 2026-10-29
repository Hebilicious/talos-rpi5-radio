# Builds the rpi5-radio system extension (PRD R2).
#
# KERNEL_IMAGE: our kernel (ghcr.io/hebilicious/talos-rpi5-radio/kernel:<tag>).
# LINUX_FIRMWARE_IMAGE: Sidero's linux-firmware at the pkgs commit Talos pins.
ARG KERNEL_IMAGE
ARG LINUX_FIRMWARE_IMAGE
ARG ALPINE_IMAGE=alpine:3.22@sha256:2e0b81d60597f449baa56dc25d355367869d2dca4cd57e866f1e2b52af3eb55f

FROM ${KERNEL_IMAGE} AS kernel
FROM ${LINUX_FIRMWARE_IMAGE} AS linux-firmware

FROM ${ALPINE_IMAGE} AS build
ARG VERSION
RUN apk add --no-cache wpa_supplicant=2.11-r2
COPY --from=kernel /usr/lib/modules /kernel/usr/lib/modules
COPY --from=linux-firmware /usr/lib/firmware/cypress /linux-firmware/usr/lib/firmware/cypress
COPY --from=linux-firmware /usr/lib/firmware/brcm /linux-firmware/usr/lib/firmware/brcm
COPY . /src
RUN /src/assemble.sh \
  && sed "s/@VERSION@/${VERSION}/" /src/manifest.yaml > /manifest.yaml

FROM scratch
COPY --from=build /rootfs /rootfs
COPY --from=build /manifest.yaml /manifest.yaml
