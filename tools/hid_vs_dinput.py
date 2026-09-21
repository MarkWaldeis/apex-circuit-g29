"""Beide Lesepfade des Lenkrads gleichzeitig messen: HID und DirectInput.

Hintergrund (gemessen am 21.09.2026): Godot/SDL meldet **alle** Achsen des G29
als 0.000 (`tests/probe_axis_read.gd`, Fensterlauf, mit und ohne Fokus, mit und
ohne laufende G HUB, mit und ohne Helfer), `tools/hid_probe.py` laeuft auf allen
drei HID-Schnittstellen in einen Timeout - waehrend `tools/ffb_hw_probe.py`
ueber DirectInput eine lebende Achse liest (24/24 gueltige Werte) und die Kraft
den Motor dreht. Die bisherige Erklaerung "Netzteil/Kabel" passt dazu nicht.

Dieses Werkzeug klaert die letzte Luecke: kommen rohe HID-Reports an, *waehrend*
das Rad sich nachweislich bewegt? Es oeffnet beide Wege im selben Prozess:

  * die HID-Joystick-Schnittstelle (mi_00, usage 0x01/0x04) wird gelesen - in
    einem eigenen Thread, damit das blockierende ReadFile die Kraft nicht stoppt,
  * die Lenkachse laeuft ueber DirectInput, und die Kraft setzt
    `tools/g29_ffb.py` (dieselbe Datei, die auch im Spiel wirkt).

Ausgabe je Phase: DirectInput-Spanne und Zahl der HID-Reports.

    python tools/hid_vs_dinput.py [--vid-pid 046d:c24f] [--seconds 2.0] [--force 0.4]

Urteil:
  * HID meldet Reports, waehrend DirectInput die Achse bewegt -> der HID-Pfad
    lebt, das Problem liegt in Godot/SDL.
  * HID bleibt stumm, waehrend DirectInput die Achse bewegt -> das Rad liefert
    seine Eingabe-Reports nur noch an den Treiberpfad (DirectInput). Dann hilft
    im Spiel kein Code: das Rad muss einmal ab- und wieder angesteckt werden
    (oder der Rechner neu gestartet).
"""

import argparse
import ctypes
import importlib.util
import pathlib
import sys
import threading
import time
from ctypes import wintypes


def _load(name: str):
    path = pathlib.Path(__file__).with_name(name)
    spec = importlib.util.spec_from_file_location("apex_" + name[:-3], path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class HidReader(threading.Thread):
    """Liest rohe HID-Reports, ohne das Kraft-Senden zu blockieren.

    Nutzt die Strukturen und Aufrufe aus `tools/hid_probe.py` (dort sind die
    Argtypes korrekt gesetzt) - ein zweiter, eigener Aufruf-Satz war bereits
    die Quelle von Fehlmessungen.
    """

    def __init__(self, probe, path: str, timeout_ms: int = 300):
        super().__init__(daemon=True)
        self.probe = probe
        self.kernel32 = probe.kernel32
        self.path = path
        self.timeout_ms = timeout_ms
        self.count = 0
        self.first = None
        self.last = None
        self.opened = False
        self.open_error = 0
        self._stop = threading.Event()

    def run(self) -> None:
        k = self.kernel32
        handle = k.CreateFileW(self.path,
                               self.probe.GENERIC_READ | self.probe.GENERIC_WRITE,
                               self.probe.FILE_SHARE_READ | self.probe.FILE_SHARE_WRITE,
                               None, self.probe.OPEN_EXISTING,
                               self.probe.FILE_FLAG_OVERLAPPED, None)
        if not handle or handle == self.probe.INVALID_HANDLE_VALUE:
            self.open_error = ctypes.get_last_error()
            return
        self.opened = True
        size = 64
        buf = ctypes.create_string_buffer(size)
        while not self._stop.is_set():
            ov = self.probe.OVERLAPPED()
            ov.hEvent = k.CreateEventW(None, True, False, None)
            read = wintypes.DWORD(0)
            ok = k.ReadFile(handle, buf, size, ctypes.byref(read),
                            ctypes.byref(ov))
            if not ok:
                if ctypes.get_last_error() == 997:  # ERROR_IO_PENDING
                    rc = k.WaitForSingleObject(ov.hEvent, self.timeout_ms)
                    if rc == self.probe.WAIT_TIMEOUT:
                        k.CancelIo(handle)
                        k.CloseHandle(ov.hEvent)
                        continue
                    k.GetOverlappedResult(handle, ctypes.byref(ov),
                                          ctypes.byref(read), False)
                else:
                    k.CloseHandle(ov.hEvent)
                    time.sleep(0.05)
                    continue
            k.CloseHandle(ov.hEvent)
            if read.value > 0:
                data = bytes(buf.raw[:read.value])
                self.count += 1
                if self.first is None:
                    self.first = data
                self.last = data
        k.CloseHandle(handle)

    def stop(self) -> None:
        self._stop.set()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vid-pid", default="046d:c24f")
    parser.add_argument("--seconds", type=float, default=2.0)
    parser.add_argument("--force", type=float, default=0.4)
    parser.add_argument("--trace", type=float, default=0.0,
                        help="Sekunden zwischen zwei Spurzellen (0 = aus)")
    parser.add_argument("--square", type=float, default=0.0,
                        help="statt der Phasen so lange ein Rechteck fahren (s)")
    args = parser.parse_args()

    hid_probe = _load("hid_probe.py")
    vid, pid = (int(x, 16) for x in args.vid_pid.split(":"))
    paths = hid_probe.device_paths(vid, pid)
    joystick = [p for p in paths if "mi_00" in p.lower()]
    if not joystick:
        print("HID_VS FAIL: keine Joystick-Schnittstelle (mi_00) gefunden")
        return 2
    path = joystick[0]
    print(f"HID-Schnittstelle : {path}")

    reader = HidReader(hid_probe, path)
    reader.start()
    time.sleep(0.5)
    print(f"HID geoeffnet     : {reader.opened} (Fehler {reader.open_error})")
    if not reader.opened:
        print("HID_VS FAIL: die Schnittstelle laesst sich nicht oeffnen")
        reader.stop()
        return 1

    helper = _load("g29_ffb.py")
    try:
        wheel = helper.G29ForceFeedback(exclusive=True)
    except helper.WheelError as exc:
        print(f"HID_VS FAIL: DirectInput: {exc}")
        reader.stop()
        return 1
    print(f"DirectInput       : {wheel.name}, "
          f"Effekte {sorted(wheel.effects_created)}")

    if args.square > 0.0:
        # Rechteck: alle 3 s das Vorzeichen. Damit laesst sich in der Spur
        # sehen, *wann* die Kraft aufhoert zu wirken - z. B. in dem Moment, in
        # dem ein fremdes Programm (das Spiel) das Lenkrad oeffnet.
        phases = []
        t = 0.0
        sign = 1.0
        while t < args.square:
            phases.append((f"{sign:+.1f}", sign * args.force))
            sign = -sign
            t += 3.0
    else:
        phases = [("ruhe", 0.0), ("plus", args.force), ("ruhe", 0.0),
                  ("minus", -args.force), ("aus", 0.0)]
    print(f"{'Phase':<6} {'DI gueltig':>11} {'DI-Spanne':>26} {'HID-Reports':>12}")
    hid_reports = 0
    started = time.time()
    next_trace = started + args.trace if args.trace > 0 else None
    last_seen = None
    try:
        for label, force in phases:
            values = []
            before = reader.count
            deadline = time.time() + args.seconds
            while time.time() < deadline:
                wheel.apply(force, 0.05, 0.05, 0.0, 0.0, False)
                raw = wheel.read_axis()
                if raw is not None:
                    values.append(raw)
                if args.square > 0.0 and next_trace and time.time() >= next_trace:
                    now = time.time()
                    flag = ""
                    if last_seen is not None and raw is not None:
                        if raw == last_seen:
                            flag = "  <-- Achse steht still"
                    if raw is not None:
                        last_seen = raw
                    print(f"  t={now - started:6.1f}s Soll={force:+.2f} "
                          f"DI={raw if raw is not None else '-':>6} "
                          f"HID={reader.count}{flag}")
                    next_trace = now + args.trace
                time.sleep(0.03)
            span = f"{min(values)}..{max(values)}" if values else "(keine)"
            got = reader.count - before
            hid_reports += got
            print(f"{label:<6} {len(values):>11} {span:>26} {got:>12}")
    finally:
        wheel.apply(0.0, 0.0, 0.0, 0.0, 0.0, False)
        time.sleep(0.2)
        wheel.close()
        reader.stop()

    print(f"\nHID-Reports insgesamt: {hid_reports} "
          f"(erstes {reader.first.hex(' ') if reader.first else '-'})")
    if hid_reports == 0:
        print("HID_VS ERGEBNIS: die HID-Schnittstelle liefert **keinen** Report, "
              "auch waehrend die Achse ueber DirectInput nachweislich laeuft.")
    else:
        print("HID_VS ERGEBNIS: die HID-Schnittstelle liefert Reports - der "
              "Rohpfad lebt, das Problem liegt oberhalb (Godot/SDL).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
