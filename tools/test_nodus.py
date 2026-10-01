#!/usr/bin/env python3
"""Exercise the shipped Nodus bundle without Go or an installed user helper."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import pty
import select
import shutil
import signal
import struct
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "nodus/bin"


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="nodus bundle ' ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.state = self.root / "state"
        self.state.mkdir(mode=0o700)
        self.bin = self.root / "path"
        self.bin.mkdir()
        # Intentionally no go, compiler, or ~/.local/bin on PATH.
        for name in ("uname", "dirname"):
            (self.bin / name).symlink_to(shutil.which(name))
        self.env = os.environ | {"PATH": str(self.bin)}

    def run_helper(self, *args):
        return subprocess.run(
            ["/bin/sh", str(BUNDLE / "nodus-noctalia"), "--data-dir", str(self.state), *args],
            env=self.env, text=True, capture_output=True, timeout=5,
        )

    def test_bundle_checksums_and_static_architectures(self):
        lines = (BUNDLE / "SHA256SUMS").read_text().splitlines()
        self.assertEqual(len(lines), 2)
        for line in lines:
            checksum, name = line.split()
            binary = BUNDLE / name
            data = binary.read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), checksum)
            self.assertEqual(binary.stat().st_mode & 0o111, 0o111)
            self.assertEqual(data[:6], b"\x7fELF\x02\x01")  # ELF64, little endian
            machine = struct.unpack_from("<H", data, 18)[0]
            self.assertEqual(machine, 62 if name.endswith("amd64") else 183)
            phoff = struct.unpack_from("<Q", data, 32)[0]
            size, count = struct.unpack_from("<HH", data, 54)
            for index in range(count):
                self.assertNotEqual(struct.unpack_from("<I", data, phoff + size * index)[0], 3, "dynamic interpreter required")

    def test_unpaired_install_runs_without_go(self):
        result = self.run_helper("status")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Pair this device from the Nodus plugin", json.loads(result.stdout)["message"])

    def test_other_operation_does_not_block_panel(self):
        with (self.state / "lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = self.run_helper("sync", "0")
            self.assertEqual(result.returncode, 1)
            self.assertEqual(json.loads(result.stdout)["state"], "busy")
            self.assertFalse((self.state / "profile.json").exists())

    def test_launcher_selection_and_argument_boundaries(self):
        bundle = self.root / "plugin's bin"
        bundle.mkdir()
        shutil.copy2(BUNDLE / "nodus-noctalia", bundle / "nodus-noctalia")
        for machine, arch in (("x86_64", "amd64"), ("aarch64", "arm64"), ("arm64", "arm64")):
            uname = self.bin / "uname"
            uname.unlink()
            uname.write_text(f'#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo {machine};; esac\n')
            uname.chmod(0o755)
            binary = bundle / f"nodus-noctalia-linux-{arch}"
            binary.write_text('#!/bin/sh\nprintf "%s\\n" "$0" "$@"\n')
            binary.chmod(0o755)
            result = subprocess.run(
                ["/bin/sh", str(bundle / "nodus-noctalia"), "pair", "https://example.com/'$(false)"],
                env=self.env, text=True, capture_output=True, check=True,
            )
            self.assertEqual(result.stdout.splitlines(), [str(binary), "pair", "https://example.com/'$(false)"])

    def test_missing_binary_and_unsupported_machine(self):
        launcher = self.root / "nodus-noctalia"
        shutil.copy2(BUNDLE / "nodus-noctalia", launcher)
        result = subprocess.run(["/bin/sh", str(launcher)], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("update or reinstall", json.loads(result.stdout)["message"])
        uname = self.bin / "uname"
        uname.unlink()
        uname.write_text('#!/bin/sh\necho unsupported\n')
        uname.chmod(0o755)
        result = self.run_helper("status")
        self.assertEqual(result.returncode, 1)
        self.assertIn("x86_64 and ARM64 only", json.loads(result.stdout)["message"])

    def test_pairing_code_is_hidden_in_real_tty(self):
        # Fake keyring and loopback server only; never contact a real account.
        secret_tool = self.bin / "secret-tool"
        secret_tool.write_text(
            '#!/usr/bin/python3\n'
            'import os, pathlib, sys\n'
            'action = sys.argv[1]\n'
            'kind = sys.argv[sys.argv.index("kind") + 1]\n'
            'path = pathlib.Path(os.environ["FAKE_KEYRING"]) / kind\n'
            'if action == "store": path.write_text(sys.stdin.read())\n'
            'elif action == "clear": path.unlink(missing_ok=True)\n'
            'elif path.exists(): print(path.read_text())\n'
            'else: sys.exit(1)\n'
        )
        secret_tool.chmod(0o755)
        keyring = self.root / "keyring"
        keyring.mkdir(mode=0o700)
        self.env["FAKE_KEYRING"] = str(keyring)
        requests = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                requests.append((self.path, body))
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps({"tokenId": "token_test", "credential": "token_test." + body["credentialSecret"]}).encode())

            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"contractVersion":"2.0","realmId":"realm_test"}')

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        origin = f"http://127.0.0.1:{server.server_port}"
        pid, fd = pty.fork()
        if pid == 0:
            os.execve("/bin/sh", ["/bin/sh", str(BUNDLE / "nodus-noctalia"), "--data-dir", str(self.state), "pair", origin], self.env)
        thread.start()
        output = b""
        sent = False
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if not select.select([fd], [], [], 0.1)[0]:
                    continue
                try:
                    chunk = os.read(fd, 4096)
                except OSError:
                    break  # PTY closes with EIO on Linux.
                if not chunk:
                    break
                output += chunk
                if b"Pairing code: " in output and not sent:
                    os.write(fd, b"ABCDE-FGHIJ\n")
                    sent = True
            else:
                self.fail("pairing timed out")
            child, status = os.waitpid(pid, 0)
            self.assertEqual(child, pid, output)
            self.assertEqual(os.waitstatus_to_exitcode(status), 0, output)
            pid = 0
        finally:
            os.close(fd)
            if pid:
                try:
                    os.kill(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
                except ProcessLookupError:
                    pass
        self.assertTrue(sent)
        self.assertNotIn(b"ABCDE-FGHIJ", output)
        self.assertIn(b'"state":"paired"', output)
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0][0], "/auth/pairings/redeem")
        self.assertEqual(requests[0][1]["code"], "ABCDE-FGHIJ")
        credential = (keyring / "credential").read_text()
        self.assertNotIn(credential.encode(), output)
        self.assertFalse((keyring / "pending").exists())
        for path in self.state.iterdir():
            self.assertNotIn(b"ABCDE-FGHIJ", path.read_bytes())
            self.assertNotIn(credential.encode(), path.read_bytes())
        self.assertEqual(json.loads((self.state / "profile.json").read_text())["origin"], origin)


if __name__ == "__main__":
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "aarch64", "arm64"):
        raise SystemExit("Bundle execution tests need Linux x86_64 or ARM64")
    unittest.main()
