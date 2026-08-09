#!/usr/bin/env python3
"""Minimal BlenderMCP addon client (raw TCP, stdlib only).

Talks directly to the BlenderMCP addon socket server (localhost:9876),
bypassing the MCP layer. Usage:

    python3 tools/bmcp.py info                 # get_scene_info
    python3 tools/bmcp.py run <script.py>      # execute a bpy script file inside Blender
    python3 tools/bmcp.py shot <out.png>       # save a viewport screenshot
    python3 tools/bmcp.py code "<python>"      # execute an inline snippet
"""
import json
import os
import socket
import sys

HOST = os.environ.get("BLENDER_HOST", "localhost")
PORT = int(os.environ.get("BLENDER_PORT", "9876"))


def send(cmd_type: str, params: dict | None = None, timeout: float = 120.0) -> dict:
    payload = json.dumps({"type": cmd_type, "params": params or {}}).encode()
    with socket.create_connection((HOST, PORT), timeout=timeout) as sock:
        sock.sendall(payload)
        buf = b""
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
            try:
                return json.loads(buf.decode())
            except json.JSONDecodeError:
                continue
    raise RuntimeError(f"connection closed with incomplete response: {buf[:200]!r}")


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    cmd = args[0]
    if cmd == "info":
        resp = send("get_scene_info")
    elif cmd == "run":
        path = os.path.abspath(args[1])
        code = f"exec(compile(open({path!r}).read(), {path!r}, 'exec'))"
        resp = send("execute_code", {"code": code})
    elif cmd == "code":
        resp = send("execute_code", {"code": args[1]})
    elif cmd == "shot":
        out = os.path.abspath(args[1])
        resp = send("get_viewport_screenshot", {"max_size": 1024, "filepath": out, "format": "png"})
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        return 2
    print(json.dumps(resp, indent=2, default=str))
    return 0 if resp.get("status") == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
