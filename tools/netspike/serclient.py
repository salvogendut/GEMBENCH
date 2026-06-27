#!/usr/bin/env python3
"""Host side of the serial spike: connect to 1984's USIFAC tcp listener, send a banner,
then echo whatever the CPC sends. 1984 listens (usifac_backend=tcp), so we are the
client and retry until it is up. Usage: serclient.py [port]"""
import socket, time, sys
port = int(sys.argv[1]) if len(sys.argv) > 1 else 4001
s = None
for _ in range(120):
    try:
        s = socket.create_connection(("localhost", port), timeout=1)
        break
    except OSError:
        time.sleep(0.5)
if s is None:
    print("serclient: could not connect to localhost:%d" % port); sys.exit(1)
print("serclient: connected to :%d" % port)
s.sendall(b"SERIAL HELLO from host\r\n")
s.settimeout(60)
try:
    while True:
        d = s.recv(256)
        if not d:
            break
        print("serclient rx:", d)
        s.sendall(d)            # echo back to the CPC
except OSError:
    pass
