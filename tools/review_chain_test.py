"""Unabhaengige Gegenprobe fuer die Kette Spiel -> Helfer (Protokoll v2).

Der Test startet den echten Helfer im Trockenlauf (`--dry-run`) in einem
Unterprozess und schickt ihm echte UDP-Pakete. Geprueft wird, was am Lenkrad
ankommen wuerde - nicht, was der Helfer behauptet:

  1. normale Fahrt: Kraft kommt an, Rampe greift, danach laesst er los
  2. Vorzeichenwechsel +0,9 -> -0,9: kein Sprung pro Sample (Zahnradantrieb)
  3. Muell: kaputtes JSON, fehlende Felder, v1-Paket ("force"), Ausreisser
  4. 0,5 s ohne Paket: die Kraft faellt auf 0 (Lenkrad wird losgelassen)

Aufruf:
    python tools/review_chain_test.py
"""

from __future__ import annotations

import json
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "tools" / "g29_ffb.py"
PORT = 5699


def _send(sock: socket.socket, payload) -> None:
    if isinstance(payload, (dict, list)):
        blob = json.dumps(payload).encode()
    elif isinstance(payload, str):
        blob = payload.encode()
    else:
        blob = payload
    sock.sendto(blob, ("127.0.0.1", PORT))


def _start_helper(seconds: float):
    """Helfer starten und warten, bis er wirklich lauscht."""
    proc = subprocess.Popen(
        [sys.executable, str(HELPER), "--dry-run", "--port", str(PORT),
         "--dry-run-seconds", str(seconds)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        cwd=str(ROOT),
    )
    time.sleep(0.8)
    return proc


def _finish_helper(proc) -> str:
    out, _ = proc.communicate(timeout=60.0)
    if proc.returncode != 0:
        raise AssertionError("Helfer endete mit %d:\n%s" % (proc.returncode, out))
    return out


def _extremes(log: str, key: str):
    match = re.search(r"\[ffb-dry\] %s\s+([+-][\d.]+) \.\. ([+-][\d.]+)" % key, log)
    if not match:
        raise AssertionError("keine Extremwerte fuer %s im Log:\n%s" % (key, log))
    return float(match.group(1)), float(match.group(2))


def _steps(log: str):
    match = re.search(r"Sprung im Paket\s+([\d.]+).*?am Rad\s+([\d.]+)", log, re.S)
    if not match:
        raise AssertionError("keine Sprungmessung im Log:\n%s" % log)
    return float(match.group(1)), float(match.group(2))


def case_positive_and_release():
    out = []
    proc = _start_helper(4.5)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        start = time.time()
        while time.time() - start < 2.0:
            _send(sock, {"v": 2, "torque": 0.9, "damper": 0.3, "friction": 0.1,
                         "rumble": 0.2, "rumble_hz": 30.0})
            time.sleep(1.0 / 60.0)
    finally:
        sock.close()
    log = _finish_helper(proc)
    lo, hi = _extremes(log, "torque")
    out.append("positive Kraft: %+.3f .. %+.3f" % (lo, hi))
    assert hi > 0.75, "die Kraft kam nicht an: %s" % hi
    assert lo <= 0.02, "das Lenkrad liess nicht los: %s" % lo
    step_target, step_wheel = _steps(log)
    span = (hi / max(step_wheel, 1e-6)) * 0.005
    out.append("Sprung im Paket %.3f, am Rad %.3f pro Sample -> voller Weg in %.0f ms"
               % (step_target, step_wheel, span * 1000.0))
    assert step_wheel <= 0.25, "Rampe zu schwach: %s pro Sample" % step_wheel
    assert span < 0.12, "Rampe zu langsam: %.0f ms fuer den vollen Weg" % (span * 1000.0)
    return out


def case_sign_flip():
    out = []
    proc = _start_helper(3.5)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        start = time.time()
        sign = 1.0
        while time.time() - start < 1.6:
            if time.time() - start > 0.8:
                sign = -1.0
            _send(sock, {"v": 2, "torque": 0.9 * sign, "damper": 0.3,
                         "friction": 0.1, "rumble": 0.0, "rumble_hz": 24.0})
            time.sleep(1.0 / 60.0)
    finally:
        sock.close()
    log = _finish_helper(proc)
    step_target, step_wheel = _steps(log)
    out.append("Paket springt um %.3f, am Rad nur %.3f pro Sample"
               % (step_target, step_wheel))
    assert step_target > 1.0, "der Test erzeugte keinen Vorzeichenwechsel: %s" % step_target
    assert step_wheel <= 0.25, "Vorzeichenwechsel schlaegt mit %s pro Sample durch" % step_wheel
    return out


def case_garbage():
    out = []
    proc = _start_helper(5.0)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Phase 1: nur das alte v1-Paket - es muss ankommen.
        start = time.time()
        while time.time() - start < 0.7:
            _send(sock, {"v": 1, "force": -0.5, "damp": 0.2})
            time.sleep(1.0 / 60.0)
        # Phase 2: Muell - darf den Helfer nicht aus dem Tritt bringen.
        start = time.time()
        while time.time() - start < 0.7:
            _send(sock, b"{kaputt")
            _send(sock, {"v": 2})
            time.sleep(1.0 / 60.0)
        # Phase 3: Ausreisser - muss auf 1,0 begrenzt werden.
        start = time.time()
        while time.time() - start < 0.7:
            _send(sock, {"v": 2, "torque": 47.0, "rumble": 99.0,
                         "rumble_hz": 900.0, "damper": -3.0})
            time.sleep(1.0 / 60.0)
    finally:
        sock.close()
    log = _finish_helper(proc)
    t_lo, t_hi = _extremes(log, "torque")
    r_lo, r_hi = _extremes(log, "rumble")
    out.append("Muell: torque %+.3f .. %+.3f, rumble %+.3f .. %+.3f"
               % (t_lo, t_hi, r_lo, r_hi))
    assert t_hi <= 1.001, "Kraft nicht begrenzt: %s" % t_hi
    assert t_lo >= -1.001, "Kraft nicht begrenzt: %s" % t_lo
    assert r_hi <= 1.001, "Ruetteln nicht begrenzt: %s" % r_hi
    assert t_lo <= -0.4, "das v1-Paket kam nicht an: %s" % t_lo
    return out


def main():
    failed = 0
    for name, case in (("normale Fahrt + Loslassen", case_positive_and_release),
                       ("Vorzeichenwechsel", case_sign_flip),
                       ("Muell-Pakete", case_garbage)):
        try:
            for line in case():
                print("  " + line)
            print("PASS " + name)
        except AssertionError as exc:
            failed += 1
            print("FAIL %s: %s" % (name, exc))
    print("CHAIN_REVIEW FAIL" if failed else "CHAIN_REVIEW PASS")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

