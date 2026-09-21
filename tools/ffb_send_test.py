"""Send a square-wave force command to tools/g29_ffb.py (test only).

Dieser Sender schickt bewusst das ALTE Protokoll v1 (`force`, `damp`, `fric`):
so bleibt belegt, dass ein alter Sender den neuen Helfer nicht lahmlegt.
Das Spiel selbst sendet v2 (`torque`, `damper`, `friction`, `rumble_hz`).

Used by tools/ffb_live_check.ps1 to prove, on the real wheel, that force
feedback and the game's own steering readout work at the same time.

    python tools/ffb_send_test.py [seconds] [force]
"""

import json
import socket
import sys
import time

PORT = 5601


def main() -> int:
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 4.0
    force = float(sys.argv[2]) if len(sys.argv) > 2 else 0.35
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    end = time.time() + seconds
    phase = 0
    while time.time() < end:
        phase += 1
        f = force if (phase // 60) % 2 == 0 else -force
        payload = {
            "v": 1, "force": f, "damp": 0.2, "fric": 0.1,
            "rumble": 0.0, "pulse": 0.0, "spring": 0.0,
            "event": "test", "speed": 40.0, "surface": "Asphalt", "damage": 0.0,
        }
        sock.sendto(json.dumps(payload).encode("utf-8"), ("127.0.0.1", PORT))
        time.sleep(1.0 / 60.0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
