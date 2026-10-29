"""Extracts the raw arm64 Image from an EFI zboot kernel (Talos's vmlinuz).

The Raspberry Pi firmware boots a raw Image, not an EFI application.
usage: python3 -I extract-image.py <vmlinuz> <Image>
"""

import gzip
import lzma
import shutil
import struct
import subprocess
import sys

source, destination = sys.argv[1], sys.argv[2]

with open(source, "rb") as kernel:
    data = kernel.read()

# zboot header: "MZ" at 0, "zimg" at 4, payload offset and size at 8 and 12,
# compression type at 24 (see drivers/firmware/efi/libstub/zboot-header.S)
if data[4:8] != b"zimg":
    sys.exit(f"{source} is not an EFI zboot image")

offset, size = struct.unpack_from("<II", data, 8)
compression = data[24:32].rstrip(b"\0").decode()
payload = data[offset:offset + size]

if compression == "gzip":
    image = gzip.decompress(payload)
elif compression in ("xz", "lzma"):
    image = lzma.decompress(payload)
elif compression == "zstd":
    if shutil.which("zstd") is None:
        sys.exit("zstd is needed to decompress this kernel")
    image = subprocess.run(["zstd", "-d", "-c"], input=payload, capture_output=True, check=True).stdout
else:
    sys.exit(f"unsupported zboot compression {compression!r}")

# arm64 Image header: magic "ARM\x64" at offset 56
if image[56:60] != b"ARM\x64":
    sys.exit("the payload is not an arm64 Image")

with open(destination, "wb") as output:
    output.write(image)

print(f"{destination}: {len(image)} bytes ({compression})")
