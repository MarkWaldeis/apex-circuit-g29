# Apex Circuit

Formel-1-Spiel für **Godot 4.7** mit **Logitech G29** (Lenkrad + Pedale). Tastatur funktioniert als Fallback.

Beim Start erscheint ein Menü. Der Wagen wartet auf dem Startplatz, bis Gas kommt — `Enter` schaltet den Auto-Pilot ein, wenn du nur zuschauen willst.

## Steuern

| Eingabe | Aktion |
|---|---|
| G29-Lenkrad | Lenken (das Lenkrad im Cockpit dreht mit) |
| G29-Gas / -Bremse | Beschleunigen / Bremsen |
| G29-Kupplung | Kupplung (optional) |
| `W` / Pfeil hoch | Gas |
| `S` / Pfeil runter | Bremse |
| `A`/`D` oder Pfeile | Lenken |
| G29-Paddles | Gang hoch / runter |
| `Q` / `E` | Gang runter / hoch |
| `Enter` | Auto-Pilot ein/aus |
| `R` | Reset auf die Startaufstellung |
| `C` | Kamera (Cockpit / Verfolger / Helikopter) |
| `L` | Ideallinie an/aus |
| `F` | Fahrhilfen: Automatik + Traktionskontrolle an/aus |
| `Esc` | Menü auf/zu (Pause, Einstellungen, Kalibrierung) |
| `Ctrl`+`Q` | Spiel beenden |

Sobald das G29 über den Totbereich hinaus bewegt wird, schaltet der Auto-Pilot ab.

## Menü, Kalibrierung und gemerktes Mapping

`Esc` öffnet das Pausenmenü, aus dem du immer wieder ins Rennen zurückkommst. Unter **Einstellungen** siehst du links die Live-Werte der Achsen a0…a7 und rechts die Buttons:

* **Gas kalibrieren** — drücken, dann das Gaspedal voll durchtreten. Das Spiel erkennt die Achse und merkt sie sich.
* **Bremse / Kupplung kalibrieren** — dasselbe für die anderen Pedale.
* **Lenkrad kalibrieren** — Lenkrad loslassen, dann ganz nach rechts drehen; daraus erkennt das Spiel Achse und Drehrichtung.
* **Alles kalibrieren** — Gas, Bremse und Kupplung hintereinander.
* **Gas ⟷ Bremse tauschen** — ein Klick, wenn die beiden Pedale vertauscht ankommen (der klassische „ich trete Gas und die Bremse leuchtet“-Fall). Schreibt die neue Zuordnung sofort in das Profil.
* **Achse aN ändern** — neben jeder Pedal-Zeile. Wandert zum nächsten Achsenplatz (a0…a7) und überspringt dabei alles, was schon belegt ist (Lenkrad, andere Pedale). Damit lässt sich eine falsch erkannte Achse von Hand korrigieren, ohne die ganze Kalibrierung zu wiederholen.
* **Kalibrierung zurücksetzen** — verwirft die gelernten Werte; die erkannten Achsen bleiben erhalten (wichtig, weil beim G29 Gas/Bremse/Kupplung nicht auf 1/2/3 liegen), und die Zuordnung schätzt sich neu.
* **Lenkrad invertieren** — falls links/rechts vertauscht ist.

Die Zeilen **Gas / Bremse / Kupplung** unter den Achsenbalken zeigen jederzeit, was das Spiel wirklich als Gas, Bremse und Kupplung verwendet — die Prozentwerte dort füllen sich genau dann, wenn du das jeweilige Pedal trittst. Deshalb steht in der Zeile „Was im Spiel ankommt“ auch die Diagnose für den häufigsten Fehler: Trittst du Gas und es füllt sich die Bremse, dann tausche die beiden oder stelle die Achse von Hand um.

Die Zuordnung lernt außerdem mit: Wird ein Pedal im Rennen weiter durchgetreten (oder das Lenkrad weiter gedreht) als beim Kalibrieren, erweitert das Spiel den Bereich automatisch und speichert ihn. Eine unplausible Kalibrierung wird verworfen statt übernommen.

Die Lenkrichtung ist im ganzen Spiel einheitlich: **positiv = rechts**. Das G29 meldet nach dem Kalibrieren „ganz nach rechts“ als +1, `D` / Pfeil rechts sind +1, das Cockpit-Lenkrad dreht im Uhrzeigersinn und die Physik lenkt das Auto nach rechts. Alle vier Punkte prüft `tests/test_cockpit_wheel.gd`.

Das Ergebnis landet in `user://g29_profile.json` (`%APPDATA%\Godot\app_userdata\Apex Circuit\`) und wird beim nächsten Start automatisch geladen. Vor der ersten Kalibrierung arbeitet das Spiel mit einer automatischen Schätzung, damit man sofort fahren kann.

In dieses Profil schreibt nur das echte Spiel mit echtem Lenkrad: Testläufe, Diagnose-Skripte und alles, was mit simulierten Achswerten arbeitet, werden am Speichern gehindert (`save_profile()` weigert sich im Simulationsmodus), damit erfundene Werte die von Hand kalibrierte Zuordnung nicht kaputtmachen können.

Wichtig: Das G29 braucht sein **Netzteil**. Hängt nur USB dran, meldet sich das Lenkrad zwar am PC an, sendet aber **keinen einzigen Eingabe-Report** — es kommen also keine Achsendaten an. Das Spiel zeigt das ehrlich an: In den Einstellungen steht dann „G29 verbunden (…), aber noch keine Achsendaten — Lenkrad oder Pedal einmal bewegen; sonst Netzteil und Pedalkabel prüfen“, die Achsenbalken und Pedal-Zeilen zeigen `—` statt erfundener Nullwerte, und das HUD meldet „G29 ohne Achsendaten“.

Das lässt sich unabhängig nachmessen, ohne Godot zu starten:

```
python tools/hid_probe.py 046d:c24f
```

Das Skript liest die rohen HID-Reports direkt über die Windows-HID-Schnittstelle (ohne SDL, DirectInput oder Godot dazwischen). Bei einem betriebsbereiten G29 kommen laufend Reports an; ohne Netzteil läuft jede Abfrage in einen Timeout. Erwartete Ausgabe im Fehlerfall: `report timeout ... (no data)` auf allen drei Schnittstellen, obwohl `usage_page=0x0001 usage=0x0004 input_len=13 values=7` genau die Joystick-Schnittstelle mit sieben Achsen beschreibt.

## Tests (headless)

## Fahrgefühl: crashen, Ideallinie, schalten, Kurven

Seit dem Fahrgefühl-Paket fährt sich der Wagen wie ein Formel-Wagen statt wie
ein Spielzeug. Alles unten ist gemessen, nicht behauptet — die Messwerkzeuge
stehen in `tests/` und lassen sich einzeln starten.

**Crashen und Ausritte.** Die Strecke hat jetzt echte Wände: 476
Barriere-Boxen in 16 m Abstand zur Ideallinie, 1,15 m hoch, auf der ganzen
Runde. Wer sie trifft, verliert Tempo, bekommt Schaden (`crash.damage`) und
wird sichtbar langsamer — das Auto fährt nie durch die Mauer. Wände, die auf
einem anderen Streckenteil gelandet wären (die T9-Ausfahrt läuft direkt neben
der Start-Ziel-Geraden), werden beim Bauen verworfen.

Ein Streifer ist kein Crash, und ein Crash ist nicht eine Vollbremsung.
`scripts/crash.gd` misst die Geschwindigkeitsabgabe deshalb über ein Fenster
von 0,15 s und zieht vorher ab, was der Wagen ohnehin verloren hätte
(Bremsen, Luftwiderstand, Untergrund-Zug). Nur der Rest — die Abgabe, die
das Auto sich nicht erklären kann — zählt als Einschlag. Gemessen
(`tests/test_crash_surfaces.gd`, `tests/probe_scrape.gd`):

| Fall | Unerklärte Abgabe im Fenster | Crash? |
|---|---|---|
| Streifer an der Wand, 104 Kontakt-Ticks | 0,0 m/s (pro Tick −0,7) | nein |
| Frontal in die Barriere, 107 km/h | 27,1 m/s | ja, Schaden 0,22 |
| Vollbremsung 190 → 20 km/h auf Asphalt | bis 5,6 m/s | nein |

Beim Streifer wird die Abgabe pro Tick sogar **negativ** (−0,7 m/s): das Auto
verliert weniger, als Bremsen, Luftwiderstand und Untergrund-Zug vorhersagen,
weil in dieser Rechnung die Wand die Arbeit macht. Für die Frage „war das ein
Crash?“ ist das die sichere Richtung — die Zahl bleibt unter der Schwelle.

Die Schwelle liegt bei 3,0 m/s unerklärter Abgabe — 9-facher Abstand unter
einem echten Einschlag. Ein Crash ist aber nicht „die Zahl ist groß“, sondern
„die Zahl ist groß **und** der Tub berührt etwas“: beim harten Bremsen steigt
die unerklärte Abgabe auf 5,6 m/s, ohne dass irgendwo eine Wand ist, deshalb
bleibt sie folgenlos (gemessen: 0 Crashs bei 190 → 20 km/h Vollbremsung).

Der Untergrund unter den Reifen wird aus dem Querabstand zur Ideallinie
bestimmt (Asphalt 12 m breit, Kerb 0,85 m, Runoff 10 m, dahinter Gras):

| Untergrund | Grip | Längsverzögerung | Rückmeldung |
|---|---|---|---|
| Asphalt | 100 % | — | — |
| Kerb | 94 % | 1,2 m/s² | starkes Rütteln |
| Kies | 46 % | 7,5 m/s² | mittel |
| Gras | 30 % | 10,0 m/s² | leicht, aber rutschig |

Auf Gras und Kies wird das Auto also nicht nur langsamer, es schiebt auch über
die Vorderräder — ein Ausritt kostet echt Zeit. Das HUD zeigt Untergrund, Grip,
Schaden und einen Crash-Hinweis (`scripts/status_hud.gd`).

**Ideallinie.** Die angezeigte Linie ist eine echte Ideallinie, nicht die
Mittellinie: `scripts/ideal_line.gd` zieht die Punkte in den Korridor
(max. 2,08 m Querabstand von der Mitte) und senkt die Krümmungsenergie von
0,407 auf 0,322 — gemessen 0,82 s schneller als die Mittellinie auf 1634 m.
Jeder Punkt bekommt eine Phase:

* **grün** — Gas
* **gelb** — lupfen
* **rot** — bremsen (8 Bremszonen, die kürzeste 26 m)

Die KI fährt dieselbe Linie und bremst mit einem Bremshorizont
(`_ideal_speed_limit()`), also vor der Kurve statt in ihr. `L` blendet die
Anzeige aus, im Pausenmenü geht es auch.

**Schalten.** `scripts/gearbox.gd` ist ein sequenzielles 8-Gang-Getriebe:
geometrische Übersetzungen von 3,60 (1. Gang, traktionsbegrenzt) bis 0,87
(8. Gang), Drehmomentkurve mit Maximum bei 11.000/min, Schaltzeit 50 ms hoch /
70 ms runter mit Drehmomentschnitt, Motorbremse und Runterschalt-Sperre gegen
Überdrehen. Gemessen (`tests/test_gearbox.gd`): 0–100 km/h in 2,29 s, Spitze
312 km/h im 8. Gang, geschaltet wird bei 11.500/min.

Mit `F` (oder im Menü) schaltet man die **Fahrhilfen** um: Automatik und
Traktionskontrolle an oder aus. Ohne Automatik schaltet nur der Fahrer
(Paddles, `Q`/`E`, oder das HUD zeigt „MANUELL“), und der Drehzahlbegrenzer
hält den Wagen, statt heimlich hochzuschalten.

**Kurven.** Die Reifen haben eine echte Grip-Kurve (`scripts/tyre_model.gd`):
Radlast-abhängiger Abtrieb (rund 3,5-faches Wagengewicht bei 300 km/h),
Schräglaufwinkel je Achse aus einem Einspurmodell, Grip-Abfall hinter dem
Maximum, Bremsen und Lenken teilen sich denselben Reifen (Friction Circle),
Leistungsübersteuern bei niedriger Geschwindigkeit und Traktionskontrolle.
Gemessen auf der echten Strecke: 0–100 km/h in 3,1 s, maximal 3,5 g
Querbeschleunigung in den schnellen Kurven, kein Frame über 5 g.

Die Aerodynamik bremst auch: `F = 0,5 · ρ · CdA · v²` mit CdA = 1,15 m² wird
als echte Kraft aufgebracht, deshalb ist die Spitze eine Zahl und nicht
„so schnell das Getriebe eben zieht“.

**Rückmeldung.** Am Lenkrad gibt es den Effekt-Kanal (`scripts/ffb_link.gd` →
UDP 127.0.0.1:5601 → `tools/g29_ffb.py` → DirectInput). Die Kette ist
messtechnisch belegt (`tests/test_ffb_link.gd`, Mitschnitt: 1245 Pakete, 0
kaputt). Ob am Ende wirklich Kraft am Lenkrad ankommt, hängt an der Hardware:
ohne **Netzteil** kann das G29 keine Kraft erzeugen, und Godot selbst hat keine
Force-Feedback-Schnittstelle. Im Bild ist die Rückmeldung immer da: das HUD
zeigt sie, und der Kopf im Cockpit lehnt sich in die Kurve, nickt beim Bremsen
und rüttelt über Kerbs (`scripts/cockpit_camera.gd`).

```
godot --headless --path godot_f1 --script tests/test_car_orientation.gd
godot --headless --path godot_f1 --script tests/test_input_mapping.gd
godot --headless --path godot_f1 --script tests/test_drive_unit.gd
godot --headless --path godot_f1 --script tests/test_camera_pose.gd
godot --headless --path godot_f1 --script tests/test_lap_drive.gd
godot --headless --path godot_f1 --script tests/test_cockpit_wheel.gd
godot --headless --path godot_f1 --script tests/test_gameplay_input.gd
godot --headless --path godot_f1 --script tests/test_pedal_ui.gd
godot --headless --path godot_f1 --script tests/test_racing_line.gd
godot --headless --path godot_f1 --script tests/test_gearbox.gd
godot --headless --path godot_f1 --script tests/test_crash_surfaces.gd
godot --headless --path godot_f1 --script tests/test_ffb_link.gd
```

Zum Nachmessen des Fahrgefühls (schreibt nur Zahlen, keine Dateien):

```
godot --headless --path godot_f1 --script tests/probe_feel.gd
godot --headless --path godot_f1 --script tests/probe_grip.gd
godot --headless --path godot_f1 --script tests/probe_thrust.gd
godot --headless --path godot_f1 --script tests/probe_scrape.gd
godot --headless --path godot_f1 --script tests/probe_brake_crash.gd
godot --headless --path godot_f1 --script tests/probe_barrier_geometry.gd
```

`probe_feel` misst 0–100 km/h, Endgeschwindigkeit, Bremsverzögerung in g und
die Querbeschleunigung der KI. `probe_grip` misst die Grip-Kurve auf einer
leeren Fläche, `probe_thrust` den Zusammenhang zwischen `engine_force` und
echter Beschleunigung (rund Faktor 1,58).

`test_lap_drive` fährt die echte Szene und prüft, dass Fahrer- und KI-Auto richtig herum fahren und auf der Strecke bleiben.

`test_cockpit_wheel` prüft die Lenkrichtung einmal komplett durch: ein positiver Lenkwert (rechts) muss das Lenkrad im Cockpit im Uhrzeigersinn drehen, die sichtbaren Vorderräder nach rechts stellen und das Auto nach rechts (Richtung seiner eigenen -X-Achse) fahren lassen.

`test_gameplay_input` ist der Integrationstest in der echten Szene mit einem Test-Lenkrad: Gas beschleunigt (87 km/h), die Bremse stoppt von 87 auf 1 km/h, rechts lenkt nach rechts, und das Cockpit-Lenkrad dreht mit.

`test_pedal_ui` prüft das Einstellungs-Menü selbst: jede Pedal-Zeile existiert, „Achse ändern“ wandert zum nächsten freien Platz (und überspringt belegte Achsen), „Gas ⟷ Bremse tauschen“ tauscht wirklich, die Anzeige folgt der neuen Zuordnung (getretenes Gaspedal = 100 %, Bremse bleibt 0 %), die Wahl landet im Profil, und jeder Menüweg lässt sich wieder verlassen.

Diagnose-Werkzeuge (Fensterlauf, weil headless keine Joysticks sieht):

```
godot --path godot_f1 --resolution 320x200 --script tests/probe_g29_hardware.gd
godot --path godot_f1 --resolution 320x200 --script tests/probe_g29_module.gd
godot --path godot_f1 --resolution 320x200 --script tests/probe_g29_profile.gd
godot --path godot_f1 --resolution 1920x1080 --script tests/probe_fps.gd
godot --path godot_f1 --resolution 1280x720 --script tests/shot_game.gd
python tools/hid_probe.py 046d:c24f
```

## Starten

Am einfachsten: **Apex Circuit** auf dem Desktop doppelklicken.

Godot 4.7+:

```
godot --path godot_f1
```

oder den Ordner `godot_f1` in Godot importieren.

## Inhalt

- `assets/cars/` — 6 Low-Poly-Lackierungen, Reifen als eigene Meshes (`car_rig.json`)
- `assets/track/` — Apex Circuit (~1,66 km), Kerbs, Runoff, Barriers, Tribünen
- `assets/props/` — importierte und nachtexturierte GLBs
- `../blender/` — Blend-Datei, Scripts, Source-GLBs

Die Strecke und die Autos wurden in Blender 5.2 gebaut und als glTF (Y-up) exportiert.
