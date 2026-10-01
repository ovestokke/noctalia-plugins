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

    def test_pairing_code_is_visible_and_normalized(self):
        self.pair_in_tty(["abcde-fghjk"])

    def test_malformed_code_reprompts_without_network_request(self):
        self.pair_in_tty(["wrong", "A" * 64, "abcde-fghjk"], invalid_inputs=2)

    def test_rejected_code_reprompts(self):
        for status in (400, 401):
            with self.subTest(status=status):
                self.pair_in_tty(["abcde-fghjk", "pqrst-uvwxy"], statuses=[status])

    def test_previously_saved_bad_code_can_be_corrected(self):
        self.pair_in_tty(["abcde-fghjk"], statuses=[400], saved_bad_code=True)

    def test_uncertain_or_temporary_failure_preserves_exact_retry(self):
        for status in (0, 429, 503, 409):
            with self.subTest(status=status):
                self.pair_in_tty(["abcde-fghjk"], statuses=[status], retry_retained=True)

    def pair_in_tty(self, codes, statuses=(), invalid_inputs=0, saved_bad_code=False, retry_retained=False):
        # Fake keyring and loopback server only; never contact a real account.
        # Each scenario has its own state and keyring, including subtests.
        self.state = Path(tempfile.mkdtemp(dir=self.root, prefix="state-"))
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
        keyring = Path(tempfile.mkdtemp(dir=self.root, prefix="keyring-"))
        self.env["FAKE_KEYRING"] = str(keyring)
        previous = {"code": "wrong", "deviceId": "dev_old", "requestId": "req_old", "credentialSecret": "A" * 43}
        if saved_bad_code:
            (keyring / "pending").write_text(json.dumps(previous))
        requests = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                requests.append((self.path, body))
                if len(requests) <= len(statuses):
                    status = statuses[len(requests) - 1]
                    if status == 0:
                        self.close_connection = True  # Lost response: outcome unknown.
                        return
                    self.send_response(status)
                    self.end_headers()
                    self.wfile.write(b'{"code":"invalid_pairing"}' if status == 401 else b'{"error":"rejected"}')
                    return
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
        submitted = 0
        sent_at = None
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
                if output.count(b"Pairing code: ") > submitted and sent_at is None:
                    self.assertLess(submitted, len(codes), output)
                    sent_at = len(output)
                    os.write(fd, codes[submitted].encode())
                if sent_at is not None and codes[submitted].encode() in output[sent_at:]:
                    os.write(fd, b"\n")
                    submitted += 1
                    sent_at = None
            else:
                self.fail("pairing timed out")
            child, status = os.waitpid(pid, 0)
            self.assertEqual(child, pid, output)
            self.assertEqual(os.waitstatus_to_exitcode(status), 1 if retry_retained else 0, output)
            pid = 0
        finally:
            os.close(fd)
            if pid:
                try:
                    os.kill(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
                except ProcessLookupError:
                    pass
        server.shutdown()
        thread.join()
        # Restart only when exercising an exact retry without any TTY/code prompt.
        if retry_retained:
            retained = json.loads((keyring / "pending").read_text())
            self.assertEqual(retained, requests[0][1])
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            retried = self.run_helper("pair", origin)
            server.shutdown()
            thread.join()
            self.assertEqual(retried.returncode, 0, retried.stdout)
            self.assertEqual(requests[0][1], requests[1][1])
            self.assertNotIn("Pairing code:", retried.stdout + retried.stderr)
            output += retried.stdout.encode()
        self.assertEqual(submitted, len(codes))
        self.assertIn(b'"state":"paired"', output)
        self.assertEqual(output.count(b"Incorrect code. Try again."), invalid_inputs + (0 if retry_retained else len(statuses)))
        self.assertEqual(len(requests), 1 + len(statuses))
        self.assertTrue(all(route == "/auth/pairings/redeem" for route, _ in requests))
        self.assertEqual(requests[-1][1]["code"], codes[-1].upper())
        if saved_bad_code:
            self.assertEqual(requests[0][1], previous)
        if statuses and not retry_retained:
            for field in ("deviceId", "requestId", "credentialSecret"):
                self.assertNotEqual(requests[0][1][field], requests[1][1][field])
        credential = (keyring / "credential").read_text()
        self.assertNotIn(credential.encode(), output)
        self.assertFalse((keyring / "pending").exists())
        for path in self.state.iterdir():
            self.assertNotIn(codes[-1].upper().encode(), path.read_bytes())
            self.assertNotIn(credential.encode(), path.read_bytes())
        self.assertEqual(json.loads((self.state / "profile.json").read_text())["origin"], origin)


if __name__ == "__main__":
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "aarch64", "arm64"):
        raise SystemExit("Bundle execution tests need Linux x86_64 or ARM64")
    unittest.main()
