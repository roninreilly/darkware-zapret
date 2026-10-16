#!/usr/bin/env python3
"""End-to-end SOCKS + verified local TLS. No external traffic or system settings."""
import argparse
import http.server
import pathlib
import socket
import ssl
import subprocess
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"darkware-local-tls-ok\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_):
        pass


def receive(sock, count):
    result = b""
    while len(result) < count:
        part = sock.recv(count - len(result))
        if not part:
            raise RuntimeError("Unexpected SOCKS EOF")
        result += part
    return result


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def probe(port, destination, context, rejects_local=False):
    with socket.create_connection(("127.0.0.1", port), timeout=4) as sock:
        sock.sendall(b"\x05\x01\x00")
        assert receive(sock, 2) == b"\x05\x00", "SOCKS5 authentication handshake failed"
        sock.sendall(b"\x05\x01\x00\x01\x7f\x00\x00\x01" + destination.to_bytes(2, "big"))
        header = receive(sock, 4)
        if rejects_local:
            # tpws deliberately blocks all loopback destinations to prevent proxy loops.
            assert header[:2] == b"\x05\x02", f"tpws local destination protection failed: {header!r}"
            return
        assert header[:2] == b"\x05\x00", f"SOCKS5 CONNECT failed: {header!r}"
        size = {1: 4, 4: 16}.get(header[3])
        if header[3] == 3:
            size = receive(sock, 1)[0]
        assert size is not None, "Invalid SOCKS reply address"
        receive(sock, size + 2)
        with context.wrap_socket(sock, server_hostname="localhost") as secure:
            secure.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
            response = b""
            while True:
                part = secure.recv(65536)
                if not part:
                    break
                response += part
            assert response.startswith(b"HTTP/1.0 200"), response[:100]
            assert b"darkware-local-tls-ok" in response, "TLS response body mismatch"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("engines", nargs="?", type=pathlib.Path, default=ROOT / ".build/engines")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="darkware-tls-") as directory:
        directory = pathlib.Path(directory)
        config = directory / "openssl.cnf"
        config.write_text("[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=localhost\n[ext]\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=critical,CA:TRUE\n")
        key, cert = directory / "key.pem", directory / "cert.pem"
        subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-keyout", str(key), "-out", str(cert), "-config", str(config)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(cert, key)
        server.socket = tls.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        client_tls = ssl.create_default_context(cafile=str(cert))
        cases = {
            "tpws": [[], ["--split-pos=1,midsld", "--disorder"], ["--tlsrec=sniext", "--split-pos=1,midsld", "--disorder"], ["--tlsrec=midsld", "--split-pos=midsld", "--disorder"], ["--tlsrec=sniext", "--split-pos=1,midsld", "--oob"]],
            "ciadpi": [[], ["-d", "1"], ["-d", "1+s"], ["-d", "1", "--oob", "1"], ["-A", "torst", "-d", "1"]],
        }
        count = 0
        try:
            for engine, variants in cases.items():
                for variant in variants:
                    port = free_port()
                    bind = ["--socks", "--bind-addr=127.0.0.1", f"--port={port}"] if engine == "tpws" else ["--ip", "127.0.0.1", "--port", str(port)]
                    with tempfile.TemporaryFile() as log:
                        process = subprocess.Popen([str(args.engines / engine)] + bind + variant, stdin=subprocess.DEVNULL, stdout=log, stderr=log)
                        try:
                            deadline = time.monotonic() + 4
                            while True:
                                if process.poll() is not None:
                                    log.seek(0)
                                    raise RuntimeError(f"{engine} exited: {log.read().decode(errors='replace')}")
                                try:
                                    ready = socket.create_connection(("127.0.0.1", port), timeout=0.1)
                                    ready.close()
                                    break
                                except OSError:
                                    if time.monotonic() > deadline:
                                        raise RuntimeError(f"{engine} did not start")
                                    time.sleep(0.05)
                            probe(port, server.server_port, client_tls, rejects_local=engine == "tpws")
                            count += 1
                        finally:
                            if process.poll() is None:
                                process.terminate()
                            try:
                                process.wait(timeout=2)
                            except subprocess.TimeoutExpired:
                                process.kill()
                                process.wait(timeout=2)
            print(f"PASS: {count} local engine scenarios (5 ByeDPI SOCKS-to-verified-TLS; 5 tpws SOCKS/local-loop rejection); no system settings changed.")
        finally:
            server.shutdown()
            server.server_close()

if __name__ == "__main__":
    main()
