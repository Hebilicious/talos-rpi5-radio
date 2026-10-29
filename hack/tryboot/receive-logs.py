"""Receives the logs of a tryboot test boot (stage.sh).

- UDP 6666: the kernel console, sent by netconsole from early boot (plain text).
- UDP 5140: Talos's kernel log stream, talos.logging.kernel (JSON lines).

Prints every line and appends it to <output dir>/netconsole.txt or kmsg.jsonl.
usage: python3 -I receive-logs.py <output dir>
"""

import json
import os
import selectors
import socket
import sys

output = sys.argv[1]
streams = {6666: "netconsole.txt", 5140: "kmsg.jsonl"}

selector = selectors.DefaultSelector()

for port, name in streams.items():
    listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    listener.bind(("0.0.0.0", port))
    selector.register(listener, selectors.EVENT_READ, open(os.path.join(output, name), "a", buffering=1))

while True:
    for key, _ in selector.select():
        packet = key.fileobj.recv(65535).decode(errors="replace")
        key.data.write(packet if packet.endswith("\n") else packet + "\n")

        for line in packet.splitlines():
            try:
                line = json.loads(line).get("msg", line)
            except json.JSONDecodeError:
                pass

            print(line, flush=True)
