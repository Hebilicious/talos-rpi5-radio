# Test boot on a Raspberry Pi 5 running Raspberry Pi OS

Boots a Talos build once on a Pi 5 without changing its disks, and returns it to
Raspberry Pi OS. It uses the firmware's `tryboot`: one reboot reads `tryboot.txt`
instead of `config.txt`, and the reboot after that is a normal one.

During the test boot:

- The firmware boots Talos's kernel and initramfs straight from the boot partition
  (`/boot/firmware/talos-tryboot/`), with the `rpi_5` overlay's device trees.
- `tryboot-overlay.dts` hides the SD card controller, so Talos sees no disk. The
  Wi-Fi controller stays enabled.
- Talos runs from RAM in maintenance mode.
- The kernel sends its console over UDP from early boot (netconsole), and Talos
  streams its kernel log (`talos.logging.kernel`).

## Steps

On this machine, which must be on the Pi's Ethernet network:

```sh
# 1. Receive the logs (UDP 6666 and 5140; allow them in the firewall).
python3 -I hack/tryboot/receive-logs.py <log dir>

# 2. Stage the CI artifacts and the overlay's device trees on the Pi.
hack/tryboot/stage.sh <artifacts dir> <dtb dir> <ssh host> <this machine's IP>

# 3. Boot Talos once.
ssh <ssh host> "sudo systemctl reboot --reboot-argument='0 tryboot'"

# 4. Read the results from <log dir>/netconsole.txt (or talosctl dmesg --insecure).

# 5. Back to Raspberry Pi OS. Only while the SD card is hidden: the kernel log
#    must have no "mmc0: new ... SD" line.
hack/tryboot/recover.sh <the Pi's IP>

# 6. Remove the staged files.
hack/tryboot/unstage.sh <ssh host>
```

`<dtb dir>` holds the overlay's device trees, for example extracted from
`ghcr.io/siderolabs/sbc-raspberrypi:<version>` at `artifacts/rpi_5/`.

## Things learned the hard way

- systemd no longer accepts the reboot argument positionally: `reboot '0 tryboot'`
  reboots normally. Use `--reboot-argument`.
- The firmware loads overlays from the top-level `overlays/`, even with `os_prefix`.
- The firmware prepends the device tree's `/chosen/bootargs` to the command line.
  They include `cgroup_disable=memory`, which stops Talos ("failed to create
  cgroup"). `stage.sh` clears them in its copies of the device trees; a real
  install boots through U-Boot and GRUB and never sees them.
- Maintenance mode refuses `Reboot` without credentials ("not authorized"), hence
  `recover.sh`.
