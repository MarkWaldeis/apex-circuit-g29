"""Messung am echten Lenkrad: bewegt die Kraft die Achse - und wohin?

Der Helfer kann Kraft senden (`--sign-check`), aber dessen Messung vergleicht
eine Ruheposition mit der Position *nach* einer Kraft. Ein G29 ohne
Zentrierfeder bleibt dort stehen, wo die Kraft es hingeschoben hat: die zweite
Messung startet also von der verschobenen Position. Dieses Werkzeug liest die
Achse deshalb *waehrend* jeder Phase mit und berichtet die Bewegung je Phase.

    python tools/ffb_hw_probe.py [--force 0.5] [--seconds 2.0] [--invert]
"""

import argparse
import importlib.util
import pathlib
import sys
import time


def _load_helper():
    path = pathlib.Path(__file__).with_name("g29_ffb.py")
    spec = importlib.util.spec_from_file_location("apex_g29_ffb", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _phase(wheel, name, force, seconds, invert, period=0.05):
    values = []
    missing = 0
    deadline = time.time() + seconds
    while time.time() < deadline:
        wheel.apply(force, 0.05, 0.05, 0.0, 0.0, invert)
        raw = wheel.read_axis()
        if raw is None:
            missing += 1
        else:
            values.append(raw)
        time.sleep(period)
    total = len(values) + missing
    if not values:
        print(f"PHASE {name:<5} gueltig=0/{total}  keine Achsendaten")
        return None, None, 0, total
    first, last = values[0], values[-1]
    print(f"PHASE {name:<5} gueltig={len(values)}/{total}"
          f"  von={first} bis={last}  min={min(values)} max={max(values)}"
          f"  delta={last - first:+d}")
    return first, last, len(values), total


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", type=float, default=0.5)
    parser.add_argument("--seconds", type=float, default=2.0)
    parser.add_argument("--invert", action="store_true")
    parser.add_argument("--name", default=None)
    args = parser.parse_args()

    module = _load_helper()
    try:
        wheel = module.G29ForceFeedback(name_filter=args.name, exclusive=True)
    except module.WheelError as exc:
        print(f"HW_PROBE FAIL: {exc}")
        return 1
    if not wheel.effects_created:
        print("HW_PROBE FAIL: keine Effekte geladen")
        wheel.close()
        return 1

    print(f"Geraet     : {wheel.name}")
    print(f"Kraft      : +-{args.force:.2f} fuer je {args.seconds:.1f} s, "
          f"invert={args.invert}")
    try:
        rest_first, rest_last, rest_ok, rest_total = _phase(
            wheel, "ruhe", 0.0, args.seconds, args.invert)
        plus_first, plus_last, plus_ok, plus_total = _phase(
            wheel, "plus", args.force, args.seconds, args.invert)
        _phase(wheel, "ruhe", 0.0, args.seconds, args.invert)
        minus_first, minus_last, minus_ok, minus_total = _phase(
            wheel, "minus", -args.force, args.seconds, args.invert)
    finally:
        wheel.apply(0.0, 0.0, 0.0, 0.0, 0.0, args.invert)
        time.sleep(0.2)
        wheel.close()

    total = rest_total + plus_total + minus_total
    valid = rest_ok + plus_ok + minus_ok
    if valid == 0:
        print("HW_PROBE TEILWEISE: die Achse liefert keine Daten (Netzteil?) - "
              "ob eine Kraft ankommt, ist so nicht messbar")
        return 2
    if plus_first is None or plus_last is None or minus_first is None or minus_last is None:
        print("HW_PROBE TEILWEISE: eine Phase ohne Achsendaten - Messung "
              "unvollstaendig")
        return 2

    d_plus = plus_last - plus_first
    d_minus = minus_last - minus_first
    if abs(d_plus) < 200 and abs(d_minus) < 200:
        print(f"HW_PROBE FAIL: die Kraft bewegt das Lenkrad nicht (plus "
              f"{d_plus:+d}, minus {d_minus:+d}) - Netzteil? Rad festgehalten?")
        return 3
    if d_plus > 0 and d_minus < 0:
        print(f"HW_PROBE PASS: Kraft bewegt das Lenkrad, positive Kraft dreht "
              f"die Achse nach + ({d_plus:+d} / {d_minus:+d}) - dieselbe "
              f"Richtung wie 'rechts = +1' im Spiel.")
        return 0
    if d_plus < 0 and d_minus > 0:
        print(f"HW_PROBE ANDERS: Kraft bewegt das Lenkrad, aber positive Kraft "
              f"dreht die Achse nach - ({d_plus:+d} / {d_minus:+d}) - der "
              f"Helfer braucht --invert (oder das Spiel dreht das Vorzeichen).")
        return 3
    print(f"HW_PROBE UNKLAR: Bewegung ohne klares Vorzeichen (plus {d_plus:+d}, "
          f"minus {d_minus:+d}; gueltige Achsenwerte {valid}/{total})")
    return 4


if __name__ == "__main__":
    sys.exit(main())
