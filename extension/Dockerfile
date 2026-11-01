# Builds the rpi5-radio system extension (PRD R2).
#
# KERNEL_IMAGE: our kernel (ghcr.io/hebilicious/talos-rpi5-radio/kernel:<tag>).
# LINUX_FIRMWARE_IMAGE: Sidero's linux-firmware at the pkgs commit Talos pins.
ARG KERNEL_IMAGE
ARG LINUX_FIRMWARE_IMAGE
ARG ALPINE_IMAGE=alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

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
