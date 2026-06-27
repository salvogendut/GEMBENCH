import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 2323)); s.listen(1)
sys.stderr.write("SERVER listening on 127.0.0.1:2323\n"); sys.stderr.flush()
while True:
    c, a = s.accept()
    sys.stderr.write("CLIENT connected from %s\n" % str(a)); sys.stderr.flush()
    c.sendall(b"HELLO FROM HOST\r\n")
    try:
        while True:
            d = c.recv(64)
            if not d: break
            sys.stderr.write("RECVD: %r\n" % d); sys.stderr.flush()
            c.sendall(b"ECHO:" + d)
    except Exception as e:
        sys.stderr.write("ERR %s\n"%e)
    c.close()
    sys.stderr.write("CLIENT closed\n"); sys.stderr.flush()
