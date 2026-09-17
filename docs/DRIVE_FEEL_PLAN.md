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

---

# Nachtrag Welle 2 (gültig ab jetzt)

## 0. Godot nur noch über den Wrapper starten

Godot schreibt beim Laufen in `.godot/`. Zwei Instanzen auf demselben Projekt
gleichzeitig lesen dann einen halb geschriebenen Cache; das erzeugt Fehler wie
`Nonexistent function 'new' in base 'GDScript'` und **falsche PASS-Zeilen**
(gemessen am 17.09.: `test_lap_drive` meldete PASS, obwohl Player und AI nie
erzeugt wurden). Deshalb:

```
powershell -NoProfile -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/test_x.gd
```

Der Wrapper nimmt eine Dateisperre; parallele Agents warten automatisch. Jeder
Agent benutzt ausschließlich diesen Aufruf.

## 1. Zusätzliches Datei-Eigentum

| Datei | Eigentümer |
|---|---|
| `tools/g29_ffb.py` | ROOT |
| `Apex Circuit FFB starten.cmd` | ROOT |
| `godot_f1/scripts/wheel_feedback.gd` (UDP-Senke) | CRASH |
| `godot_f1/tests/test_lap_drive.gd`, `test_gameplay_input.gd`, `test_car_orientation.gd` | ROOT |
| `godot_f1/tests/test_feel_gate.gd` | ROOT |

## 2. Lenkrad-Feedback (G29) — verbindliche Schnittstelle

Godot selbst kann am G29 **kein** Force Feedback erzeugen (kein FF-API, keine
Rumble-Motoren, `Input.start_joy_vibration` ist dort wirkungslos). Der G29 hängt
aber als DirectInput-Gerät am PC, also übernimmt ein kleiner Helfer
`tools/g29_ffb.py` (DirectInput über `ctypes`) die echte Kraft. Damit beide
Seiten unabhängig arbeiten können, ist das Protokoll fix:

* `wheel_feedback.gd` schickt **pro Physik-Tick** ein UDP-Paket an
  `127.0.0.1:5601` (`PacketPeerUDP`), UTF-8-JSON, ein Objekt pro Paket:

  ```json
  {"v":1,"force":0.0,"damp":0.0,"fric":0.0,"rumble":0.0,"pulse":0.0,
   "event":"shift","speed":42.5,"surface":"Asphalt","damage":0.0}
  ```

  * `force`  −1.0 … +1.0, Grundkraft (untersteuert = leicht, Aufprall = hart)
  * `damp`   0 … 1, geschwindigkeitsabhängige Dämpfung
  * `fric`   0 … 1, Reibung (Kerb, Kies, Gras)
  * `rumble` 0 … 1, hochfrequentes Rütteln (Kerb/Ausritt)
  * `pulse`  0 … 1, einmaliger Stoß (Schaltvorgang, Aufprall)
  * `event`  Text für die Diagnose, frei wählbar

* Der Sender darf **niemals** blockieren und niemals crashen, wenn der Helfer
  nicht läuft (`PacketPeerUDP` ist von sich aus verbindungslos → in Ordnung).
* Der Helfer ist optional. Ist er nicht gestartet, darf das Spiel keinen
  Unterschied zeigen außer „kein Kraft-Rückkanal“.
* Die Diagnose steht unter `user://ffb_state.json` (bereits vorhanden) weiter
  zur Verfügung.

## 3. Harte Abnahmekriterien je Punkt (jeweils mit Messung belegt)

**CRASH**

1. Wandkontakt über 3 m/s Verlust erzeugt `crashed` + Schaden > 0; ein
   Streifer über 8 m bleibt unter dem Schwellwert (kein Dauer-Crash).
2. Neben der Strecke: GRASS/Kies kostet messbar Zeit — dasselbe Manöver (gleiche
   Lenkung, gleiches Gas) ist auf Kies mindestens 25 % langsamer als auf
   Asphalt, gemessen über 3 s.
3. Ein Aufprall bei 200 km/h wirft den Wagen sichtbar quer (Gierrate > 0.3 rad/s)
   und Schaden steigt monoton; die Rundenzeit-Relevanz ist im HUD sichtbar.
4. `wheel_feedback.strength` steigt bei Kerb, Kies, Gras, Schlupf und Aufprall
   messbar an — jeweils eigener Messwert, nicht nur „> 0“.

**LINE**

1. Ideallinie ist **nicht** die Mittellinie: mittlerer Abstand der Ideallinie zur
   Mittellinie > 0,8 m, maximaler Queroffset ≤ 4,8 m (Straßenbreite 6 m).
2. Ideallinie ist glatter als die Mittellinie: Gesamtkrümmung mindestens 12 %
   kleiner; keine Selbstüberschneidung.
3. Geschwindigkeitsprofil ist physikalisch konsistent: Bremsphase endet vor dem
   Scheitel, Beschleunigungsphase folgt ihm, und die nötige Verzögerung zwischen
   zwei Punkten überschreitet nie `brake_decel` (Rückwärtspass).
4. Sichtbares Band liegt auf dem Asphalt (nicht in der Luft, kein Z-Fighting),
   grün/gelb/rot an den richtigen Stellen; Beweis: Screenshot aus der
   Cockpit-Perspektive + Draufsicht.

**GEARBOX**

1. 8 Gänge, Hochschalten nur in Richtung höherer Gang, kein Gangsprung.
2. Schaltvorgang: Drehmoment fällt für die Schaltzeit aus (0 N), Drehzahl
   springt auf die Drehzahl des neuen Gangs (`rpm_after ≈ rpm_before * ratio_new
   / ratio_old`, Toleranz 8 %).
3. Herunterschalten wird verweigert, wenn die Zieldrehzahl über der Grenze
   liegt (`DOWN_PROTECT_RPM`) — inklusive Testfall.
4. Mit ausgeschalteter Automatik schaltet das Spiel **nie** von selbst.
5. Bei konstantem Gas steigt die Geschwindigkeit über die Gänge hinweg monoton
   (kein Einbruch, kein Steckenbleiben in einem Gang).

## 4. Beweise

Jeder Agent legt seinen Nachweis in `docs/evidence/<thema>/` ab: Roh-Log der
Messung, Screenshot(s) wo sichtbar, und einen kurzen Absatz mit dem, was
gemessen wurde und was dabei herauskam. Erst damit gilt ein Punkt als
abgenommen.

---

# Runde 2 — der aktuell gueltige Auftrag

Runde 1 hat die Module angelegt, aber drei davon sind noch Gerippe:

* `ideal_line.gd` kopiert die **Mittellinie** (`offsets` ist ueberall 0.0) und
  hat damit weder Einlenkpunkt noch Scheitel — es ist keine Ideallinie.
* `racing_line_display.gd` malt dieses Gerippe als flaches Band.
* `gearbox.gd` schaltet bei 9.000 rpm hoch (Serienauto-Drehzahl), hat keinen
  Schaltmoment-Aussetzer, keine Runterschalt-Sperre und kein Schleppmoment.
* `tyre_model.gd` liest `steer_angle`, `lateral_speed` und `traction_control`
  aus `ctx`, aber `car_controller.gd` fuellt genau diese Schluessel **nicht**,
  also rechnet das Reifenmodell mit Lenkwinkel 0 und Quergeschwindigkeit 0.
* `wheel_feedback.gd` schreibt seine Werte nur in eine JSON-Datei, die
  niemand liest: am G29 kommt kein Kraftaufwand an.

## Ziele dieser Runde

1. **Crashen und Kontakt** (Agent CRASH): Wand- und Autokontakt mit
   Aufprallhaerte, Schaden, Verlust von Anpressdruck/Leistung, HUD-Warnung,
   Kamera-Ruetteln, Lenkrad-Rueckmeldung. Neben der Strecke: Kerb/Kies/Gras
   verlangsamen und geben Feedback.
2. **Ideallinie** (Agent LINE): eine echte Ideallinie (Scheitel innen, weiter
   Bogen aussen), Gruen = Gas, Gelb = lupfen, Rot = bremsen, samt
   Bremsabstand, der zur Physik passt.
3. **Schalten** (Agent GEARBOX): 8 Gaenge, Hochschalten ~11.500 rpm,
   Schaltzeit mit Drehmoment-Aussetzer, Runterschalten nur wenn die Drehzahl
   danach unter den Begrenzer passt, Schleppmoment, kein Fremdschalten wenn
   der Automatik-Assi aus ist.
4. **Fahrgefuehl** (ROOT): Traktion, Anpressdruck, Gewichtsverlagerung,
   Bremsbalance, Unter-/Uebersteuern — und die Verdrahtung, ohne die die
   Module ihr Wissen nicht anwenden.

## Eigentum Runde 2

| Datei | Eigentuemer |
|---|---|
| `scripts/surfaces.gd`, `crash.gd`, `barriers.gd`, `wheel_feedback.gd` | CRASH |
| `scripts/hud.gd` | CRASH |
| `tests/test_crash_surfaces.gd`, `tools/ffb_bridge.py`, `tools/ffb_probe.py` | CRASH |
| `scripts/ideal_line.gd`, `racing_line_display.gd`, `line_hud.gd` | LINE |
| `scripts/racing_line.gd` (nur neue Helfer) | LINE |
| `tests/test_racing_line.gd` | LINE |
| `scripts/gearbox.gd` | GEARBOX |
| `tests/test_gearbox.gd` | GEARBOX |
| `scripts/car_controller.gd`, `main.gd`, `tyre_model.gd`, `menu.gd`, `track_loader.gd` | ROOT |

Niemand ausser ROOT aendert `car_controller.gd`, `main.gd` oder `menu.gd`.
Wer dort etwas braucht, schickt ROOT eine Nachricht mit Datei, Zweck und dem
gewuenschten Aufruf (Signatur). ROOT verdrahtet am Ende.

## Schnittstellen Runde 2 (verbindlich)

```gdscript
# ideal_line.gd (LINE)
func build(line, overrides: Dictionary = {}) -> bool
var points / offsets / curvature / target_speed / phase
func sample_ahead(pos: Vector3, look: float, hint: int = -1) -> Dictionary
func brake_distance_from(index: int) -> float   # m bis zum Bremsbeginn
func offset_limit() -> float                    # Korridorbreite (m)

# line_hud.gd (LINE)
extends CanvasLayer
func setup(car, ideal, line) -> void
var visible_now: bool

# gearbox.gd (GEARBOX)
func update(delta: float, ctx: Dictionary) -> Dictionary
#   ctx wie Runde 1, plus {"redline": float} optional
#   return plus {"torque_cut": float, "engine_brake": float,
#                "shift_time_left": float, "blocked_downshift": bool,
#                "auto_shift": bool}

# crash.gd (CRASH)
func update(delta: float, surface: Dictionary, forward_speed: float,
            lateral_speed: float = 0.0) -> void
var damage / last_impact_ms / crash_count / last_kind / scraping
signal crashed(severity: float, kind: String)

# wheel_feedback.gd (CRASH)
func update(delta: float, ctx: Dictionary) -> void
var strength: float        # 0..1, jetzt inkl. Fahrbahn/Ruckeln/Aufprall
var torque_nm: float       # Zielkraft fuer das echte Lenkrad (falls Bruecke)
func poke(kind: String, severity: float) -> void
```

## Abnahme Runde 2

Jeder Bau-Agent liefert:

1. eigenen Headless-Test (`tests/test_<bereich>.gd`), der echtes Verhalten in
   der Szene misst (nicht nur Existenz von Nodes), Ausgabe `... PASS`.
2. die drei Bestandstests gruen:
   `test_car_orientation.gd`, `test_gameplay_input.gd`, `test_lap_drive.gd`.
3. mindestens eine Zahl/Screenshot als Beweis (captures/).

Danach folgt die Pruefwelle: ein **fremder** Pruef-Agent liest den Code,
faehrt die Szene headless mit eigenen Messungen, sucht Fehler und schreibt
eine Liste reproduzierbarer Maengel. Erst wenn kein Mangel mehr offen ist,
gilt der Punkt als fertig. ROOT exportiert erst danach.
