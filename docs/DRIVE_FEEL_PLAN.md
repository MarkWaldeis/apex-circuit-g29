# Apex Circuit — Fahrgefühl-Paket (Auftrag #2)

Dieses Dokument ist der **verbindliche Vertrag** für die parallele Arbeit am
Fahrgefühl. Jeder Agent hält sich an sein Datei-Eigentum und an die hier
definierten Schnittstellen. Der Root-Agent integriert `car_controller.gd`,
`main.gd`, `track_loader.gd` und `cockpit_camera.gd` und ist der einzige, der
diese vier Dateien ändert.

## Auftrag (Kurzfassung des Wunsches)

1. **Crashen**: Wand/Barriere berühren = Crash. Neben der Strecke = Gras/
   Kies, das langsamer macht, mit Rückmeldung (HUD + Lenkrad/Feedback).
2. **Ideallinie**: wie in F1-Spielen eine Linie, grün = Gas, gelb = lupfen,
   rot = bremsen, und sie zeigt die *optimale* Linie, nicht die Mittellinie.
3. **Schalten**: realistischer (8 Gänge, Drehzahl, Schaltzeit, kein
   Fremdschalten von selbst, Herunterschalten mit Schutz).
4. **Fahrgefühl**: Kurven wie in der Formel 1 — Abtrieb, Grip-Abfall,
   Bremsbalance, Gewichtsverlagerung, Traktion.

## Harte Leitplanken

* **Die bestehenden Tests müssen weiter grün sein.** Die Abnahme läuft mit:

  ```
  godot --headless --path godot_f1 --script tests/test_car_orientation.gd
  godot --headless --path godot_f1 --script tests/test_gameplay_input.gd
  godot --headless --path godot_f1 --script tests/test_lap_drive.gd
  ```

  `test_lap_drive` prüft: Spieler fährt vorwärts, KI folgt der Linie
  (Fortschritt > 200 Punkte in 26,7 s), **KI bleibt < 10 m von der
  Mittellinie**, niemand fällt unter y = -4 m.
  `test_gameplay_input` prüft: Gas -> > 40 km/h nach 2,2 s, Bremse halbiert
  die Geschwindigkeit in 1,33 s, rechts lenken dreht den Wagen nach rechts.

* **Physik-Konstanten der Strecke** (aus `blender/scripts/05_build_track.py`):
  Fahrbahnbreite 12,0 m (halbe Breite 6,0), Kerb 0,85 m (6,00…6,85),
  Runoff 10,0 m (6,85…16,85), Barriere bei 16,0 m Offset, 1,15 m hoch.

* **Vorzeichen-Konvention**: `racing_line.offset_at()` liefert positiv, wenn
  das Auto **links** der Fahrtrichtung steht.

* Kein Agent startet einen Export oder einen `git`-Schreibbefehl. Das macht
  der Root-Agent nach der Abnahme.

## Datei-Eigentum

| Datei | Eigentümer |
|---|---|
| `scripts/surfaces.gd` | CRASH |
| `scripts/crash.gd` | CRASH |
| `scripts/barriers.gd` | CRASH |
| `scripts/wheel_feedback.gd` | CRASH |
| `scripts/hud.gd` | CRASH |
| `tests/test_crash_surfaces.gd` | CRASH |
| `scripts/ideal_line.gd` | LINE |
| `scripts/racing_line_display.gd` | LINE |
| `tests/test_racing_line.gd` | LINE |
| `scripts/racing_line.gd` (nur Erweiterungen) | LINE |
| `scripts/gearbox.gd` | GEARBOX |
| `scripts/drivetrain.gd` | GEARBOX |
| `tests/test_gearbox.gd` | GEARBOX |
| `scripts/tyre_model.gd` | ROOT |
| `scripts/car_controller.gd` | ROOT |
| `scripts/main.gd` | ROOT |
| `scripts/track_loader.gd` | ROOT |
| `scripts/cockpit_camera.gd` | ROOT |
| `scripts/menu.gd` | ROOT |
| `scripts/racing_line.gd` (Basisfunktionen) | ROOT |

Ein Agent, der eine Änderung außerhalb seines Eigentums braucht, schickt dem
Root eine Nachricht mit Datei, Zeile und Vorschlag.

## Schnittstellen

### `racing_line.gd` (Basisfunktionen, ROOT — von allen benutzbar)

```gdscript
func closest_index_near(pos: Vector3, hint: int, span: int = 64) -> int
func flat_tangent(i: int) -> Vector3          # normiert, y = 0
func left_at(i: int) -> Vector3               # links der Fahrtrichtung
func offset_at(pos: Vector3, i: int) -> float # + = links der Linie
func frame_at(pos: Vector3, hint: int) -> Dictionary
#   {"index": int, "offset": float, "tangent": Vector3, "left": Vector3,
#    "s": float}
```

### `surfaces.gd` (CRASH)

```gdscript
extends RefCounted
const ASPHALT := 0; const KERB := 1; const RUNOFF := 2; const GRASS := 3
const BARRIER_OFFSET := 16.0
func setup(line) -> void
func sample(pos: Vector3, hint: int = -1) -> Dictionary
#   {"surface": int, "name": String, "offset": float, "index": int,
#    "grip": float,    # 1.0 = Asphalt, kleiner = weniger Grip
#    "drag": float,    # zusätzliche Bremskraft in Newton bei Schrittgeschwindigkeit
#    "rumble": float,  # 0..1 Rückmeldung (Kerb/Ausritt)
#    "rough": float}   # 0..1 für Kamera-Rütteln
func is_outside_corridor(offset: float) -> bool   # jenseits der Barriere
```

### `crash.gd` (CRASH)

```gdscript
extends RefCounted
signal crashed(severity: float, kind: String)   # kind: "wall"/"car"
func setup(car, surfaces) -> void
func update(delta: float, surface: Dictionary, forward_speed: float) -> void
var damage: float          # 0..1
var last_impact_ms: float  # m/s des letzten Aufpralls
var crash_count: int
func reset() -> void
```

### `wheel_feedback.gd` (CRASH)

```gdscript
extends RefCounted
func setup(car, wheel_input) -> void
func update(delta: float, ctx: Dictionary) -> void
#   ctx: {"speed": float, "surface": Dictionary, "slip": float,
#         "lateral_g": float, "crash": float, "shift": float}
var strength: float                # 0..1 Zielintensität
var last_event: String
func poke(kind: String, severity: float) -> void
```

### `ideal_line.gd` (LINE)

```gdscript
extends RefCounted
func build(line, params: Dictionary) -> bool
var points: PackedVector3Array      # Ideallinie (Godot-Koordinaten)
var offsets: PackedFloat32Array     # Queroffset zur Mittellinie, + = links
var curvature: PackedFloat32Array   # 1/m, vorzeichenbehaftet
var target_speed: PackedFloat32Array# m/s
var phase: PackedInt32Array         # 0 = Gas, 1 = lupfen, 2 = bremsen
func sample_ahead(pos: Vector3, look: float, hint: int) -> Dictionary
#   {"point": Vector3, "index": int, "tangent": Vector3,
#    "target_speed": float, "phase": int}
func braking_distance(index: int) -> float
```

### `racing_line_display.gd` (LINE)

```gdscript
extends Node3D
func build(line, ideal) -> void
func set_enabled(on: bool) -> void
func is_enabled() -> bool
var visible_segments: int   # für Tests
```

### `gearbox.gd` (GEARBOX)

```gdscript
extends RefCounted
const MAX_GEAR := 8
func setup(seed_rpm: float) -> void
func request_shift(up: bool) -> bool
func update(delta: float, ctx: Dictionary) -> Dictionary
#   ctx: {"speed": float (m/s, vorwärts), "throttle": float, "brake": float,
#         "clutch": float, "auto": bool, "surface_grip": float}
#   return {"engine_force": float, "rpm": float, "gear": int,
#           "shift_event": int}   # 0 = nichts, 1 = hoch, -1 = runter
var gear: int
var rpm: float
func ratio(g: int) -> float
func force_gear(g: int) -> void
func reset() -> void
```

### `tyre_model.gd` (ROOT)

```gdscript
extends RefCounted
func setup(car, line) -> void
func update(delta: float, ctx: Dictionary) -> Dictionary
#   ctx: {"speed": float, "forward_speed": float, "steer": float,
#         "throttle": float, "brake": float, "surface": Dictionary,
#         "slip_angle": float, "yaw_rate": float}
#   return {"front_grip": float, "rear_grip": float, "slip": float,
#           "understeer": float, "oversteer": float,
#           "downforce": float, "drag": float, "lateral_g": float}
```

## Anbindung im Spiel (ROOT, bereits verdrahtet)

* `main.gd` baut die Barrieren (`barriers.gd::build`) und die Ideallinie
  (`ideal_line.gd` + `racing_line_display.gd`) und hängt den Führungs-Node an.
* `car_controller.gd` ruft `surfaces.sample()`, `gearbox.update()`,
  `tyre_model.update()`, `crash.update()` und `wheel_feedback.update()` in
  genau dieser Reihenfolge pro Physik-Tick.
* Tasten: `L` schaltet die Linie, `F` schaltet die Fahrhilfen.

## Abnahme pro Agent

1. Eigener Test (`tests/test_*.gd`) läuft headless grün und prüft echtes
   Verhalten in der Szene, nicht nur Existenz von Nodes.
2. Die drei Bestandstests bleiben grün.
3. `docs/`-Eintrag: kurzer Absatz in `godot_f1/README.md`? **Nein** — README
   gehört dem Root. Stattdessen Kommentar im eigenen Modul.
4. Mindestens ein Screenshot/Telemetrie-Beweis für sichtbares Verhalten
   (`tests/capture_*.gd` Muster benutzen).

## Kritische Prüfung (Welle 2)

Jeder Prüf-Agent sucht Fehler, nicht Bestätigung: Er liest den Code, fährt die
Szene headless mit eigenen Messungen, vergleicht gegen die F1-Realität und
gegen die drei Bestandstests, und schreibt eine Liste mit reproduzierbaren
Mängeln. Erst wenn er ohne Einwände ist, gilt der Punkt als fertig.
