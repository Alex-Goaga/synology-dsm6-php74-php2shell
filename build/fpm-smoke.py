"""Minimal FastCGI client: smoke-test php74-fpm with GET and multipart POST."""
import socket
import struct
import sys

def rec(t, rid, content):
    return struct.pack("!BBHHBx", 1, t, rid, len(content), 0) + content

def params(d):
    out = b""
    for k, v in d.items():
        k, v = k.encode(), v.encode()
        for x in (k, v):
            out += struct.pack("!B", len(x)) if len(x) < 128 else struct.pack("!I", len(x) | 0x80000000)
        out += k + v
    return out

def request(host, port, env, body=b""):
    s = socket.create_connection((host, port), timeout=10)
    s.sendall(rec(1, 1, struct.pack("!HB5x", 1, 0)))
    p = params(env)
    s.sendall(rec(4, 1, p) + rec(4, 1, b""))
    for i in range(0, len(body), 65535):
        s.sendall(rec(5, 1, body[i:i + 65535]))
    s.sendall(rec(5, 1, b""))
    out = b""
    while True:
        h = s.recv(8, socket.MSG_WAITALL)
        if len(h) < 8:
            break
        _, t, _, ln, pad = struct.unpack("!BBHHBx", h)
        c = s.recv(ln + pad, socket.MSG_WAITALL)[:ln] if ln + pad else b""
        if t == 6:
            out += c
        if t == 3:
            break
    return out.decode("utf-8", "replace")

script = sys.argv[1]
base = {"SCRIPT_FILENAME": script, "REQUEST_METHOD": "GET", "QUERY_STRING": "a=1",
        "SERVER_PROTOCOL": "HTTP/1.1", "GATEWAY_INTERFACE": "CGI/1.1", "REQUEST_URI": "/t.php"}
print("GET  ->", request("127.0.0.1", 9074, base).split("\r\n\r\n", 1)[-1])
b = "----x"
body = (f"--{b}\r\nContent-Disposition: form-data; name=\"f\"; filename=\"a.txt\"\r\n"
        f"Content-Type: text/plain\r\n\r\nhello\r\n--{b}\r\nContent-Disposition: form-data; name=\"v\"\r\n\r\n42\r\n--{b}--\r\n").encode()
post = dict(base, REQUEST_METHOD="POST", CONTENT_TYPE=f"multipart/form-data; boundary={b}", CONTENT_LENGTH=str(len(body)))
print("POST ->", request("127.0.0.1", 9074, post, body).split("\r\n\r\n", 1)[-1])
