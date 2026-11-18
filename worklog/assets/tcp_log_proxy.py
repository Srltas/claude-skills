"""Record the bytes of a real TCP conversation, so a note can show measured packets.

    tcp_log_proxy.py run --listen 127.0.0.1:33099 --target 127.0.0.1:33000 --log capture.jsonl [--conns 1]
    tcp_log_proxy.py dump capture.jsonl [--cas-function 27]

run   Accepts --conns connections on --listen, forwards each to --target, and writes one JSON
      line per chunk read: {"seq", "conn", "dir": "c2s" or "s2c", "hex"}. It ends when every
      connection has closed. Point the client at the --listen port instead of the server.
dump  Prints each connection as exchanges: one client chunk, then the server bytes that follow
      it until the next client chunk. --cas-function N keeps only CUBRID CAS requests whose
      function code (byte 8 of the request) is N, such as 27 for PARAMETER_INFO.

A CUBRID broker hands the client's socket to a CAS, so one connection through the proxy
carries the broker handshake and every CAS request after it. Runs on Python 3.6 or later.
"""
import argparse
import json
import socket
import threading


def hexs(data):
    return " ".join("%02x" % b for b in data)


def address(text):
    host, port = text.rsplit(":", 1)
    return host, int(port)


def run(args):
    log = open(args.log, "a")
    lock = threading.Lock()
    seq = [0]

    def pipe(src, dst, conn, direction):
        try:
            while True:
                data = src.recv(65536)
                if not data:
                    break
                with lock:
                    seq[0] += 1
                    log.write(json.dumps({"seq": seq[0], "conn": conn, "dir": direction, "hex": data.hex()}) + "\n")
                    log.flush()
                dst.sendall(data)
        except OSError:
            pass
        finally:
            try:
                dst.shutdown(socket.SHUT_WR)
            except OSError:
                pass

    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(address(args.listen))
    server.listen(8)
    print("listening on %s, forwarding to %s" % (args.listen, args.target), flush=True)
    threads = []
    for conn in range(args.conns):
        client, _ = server.accept()
        upstream = socket.create_connection(address(args.target))
        for src, dst, direction in ((client, upstream, "c2s"), (upstream, client, "s2c")):
            t = threading.Thread(target=pipe, args=(src, dst, conn, direction), daemon=True)
            t.start()
            threads.append(t)
    for t in threads:
        t.join(args.timeout)
    server.close()
    log.close()


def dump(args):
    chunks = [json.loads(line) for line in open(args.log) if line.strip()]
    for conn in sorted({c["conn"] for c in chunks}):
        seq = sorted((c for c in chunks if c["conn"] == conn), key=lambda c: c["seq"])
        print("== connection %d" % conn)
        for i, c in enumerate(seq):
            if c["dir"] != "c2s":
                continue
            request = bytes.fromhex(c["hex"])
            if args.cas_function is not None and (len(request) < 9 or request[8] != args.cas_function):
                continue
            reply = b""
            for d in seq[i + 1:]:
                if d["dir"] == "c2s":
                    break
                reply += bytes.fromhex(d["hex"])
            print("-> %d bytes: %s" % (len(request), hexs(request)))
            print("<- %d bytes: %s" % (len(reply), hexs(reply)))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command")
    p = sub.add_parser("run", help="proxy and record")
    p.add_argument("--listen", required=True, help="host:port the client connects to")
    p.add_argument("--target", required=True, help="host:port of the real server")
    p.add_argument("--log", required=True, help="JSON lines file to append to")
    p.add_argument("--conns", type=int, default=1, help="connections to accept before stopping")
    p.add_argument("--timeout", type=float, default=120, help="seconds to wait for each connection to close")
    p = sub.add_parser("dump", help="print the recorded exchanges")
    p.add_argument("log", help="JSON lines file written by run")
    p.add_argument("--cas-function", type=int, help="keep only CAS requests with this function code")
    args = parser.parse_args()
    if args.command == "run":
        run(args)
    elif args.command == "dump":
        dump(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
