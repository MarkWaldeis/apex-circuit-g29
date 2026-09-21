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

Das gilt auch für die Messläufe, die **nicht headless** sein können (headless zählt Godot keine Joysticks auf): `tests/probe_ffb_steer.gd`, `tests/probe_axis_read.gd` und `tools/ffb_direction_check.ps1` setzen `APEX_G29_PROFILE` und schreiben damit in eine Diagnosedatei statt in `user://g29_profile.json`. Gemessen am 21.09.2026 schrieb der Richtungstest sonst das echte Profil neu (im Godot-Log: `G29 profile saved: … "throttle_press": -1.88 …`), samt neu gelernter Pedal-Ruheposition. `tests/test_g29_profile_path.gd` (6 Prüfungen) hält fest, dass das echte Profil dabei inhaltlich **und im Zeitstempel** unberührt bleibt.

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

**Rückmeldung.** Am Lenkrad gibt es den Effekt-Kanal (`scripts/ffb_model.gd`
rechnet, `scripts/ffb_link.gd` → UDP 127.0.0.1:5601 → `tools/g29_ffb.py` →
DirectInput). Seit dem Lenkrad-Paket ist das keine grobe Abschätzung mehr,
sondern ein Nachlauf-Modell wie im offiziellen Spiel: die Kraft kommt aus der
Vorderachse (Querlast × Nachlauf), **bricht ein, wenn die Vorderachse
untersteuert oder blockiert**, dreht im tiefen Slide in die
Gegenlenkrichtung, rüttelt auf dem Kerb schnell und auf Kies grob, wird über
einer Kuppe kurz leicht, stößt bei einer Bodenwelle, beim Schalten und beim
Einschlag — und drückt am Lenkanschlag (Soft Lock) zurück. Die Stärke aus dem
Menü wirkt genau einmal (im Modell); der Helfer verstärkt nicht ein zweites Mal.
Der Helfer antwortet außerdem auf jedes Paket mit einem Lebenszeichen
(`{"ack":1,"mode":"wheel"}`); daran erkennt das Spiel, ob überhaupt jemand
zuhört. Ein totes Lenkrad bleibt damit nicht stumm: das HUD schreibt
„LENKRADKRAFT AUS“ (Schalter im Menü), „LENKRADKANAL AUS (APEX_FFB=0)“ oder
„KEIN HELFER — Apex Circuit FFB starten.cmd“ statt einfach 0 %.
Alles zusammen steht in `../docs/FFB_F1_STYLE_PLAN.md`, die Einzelprüfungen in
`tests/test_ffb_model.gd` (34 Checks), die Gegenproben in
`tests/probe_review_root.gd` (18 Checks) und die Messung auf der Strecke in
`tests/probe_ffb.gd`.

Der Kanal hängt an der Hardware: ohne **Netzteil** kann das G29 keine Kraft
erzeugen **und liefert auch keine Achsendaten**, und Godot selbst hat keine
Force-Feedback-Schnittstelle. Die Kette selbst ist ohne Hardware prüfbar:
`tests/test_ffb_link.gd` (14 s echte Fahrt: v2-Pakete, 60 Hz, Kraft im Bogen,
Stoß, Wertebereiche, Lebenszeichen des Helfers), `python tools/g29_ffb.py --check`
(12 Prüfungen ohne Lenkrad: Stärke genau einmal, Rampe, Stoß, Loslassen,
Ereignis/Tempo, Antwort an das Spiel) und
`python tools/g29_ffb.py --dry-run` (Rampe, Wertebereiche am Rad).

Am **echten** Rad ist die Kraft inzwischen ebenfalls gemessen — nur nicht
immer: `python tools/ffb_hw_probe.py --seconds 2.0 --force 0.5` fuhr die Achse
dreimal reproduzierbar von `32767` (Mitte) auf `26` (positive Kraft) und auf
`59525` (negative Kraft), sechs Minuten später dieselbe Messung: keine
Bewegung (`delta=+0`). Das G29 lieferte in diesem Zustand also **zeitweise**
Motor und Achsdaten, zeitweise nicht — dasselbe Bild in Godot
(`tests/probe_axis_read.gd`: `data=false`, später `a1=+1.000 data=true`, und
die gelernten Ruhepositionen der Pedale wechselten zwischen Läufen). Solange
das Rad so unzuverlässig meldet, ist jede „fühlt sich echt an?“-Aussage
wertlos; erst `python tools/hid_probe.py 046d:c24f` mit **laufenden** Reports
schafft eine belastbare Grundlage. Danach:

```
python tools/hid_probe.py 046d:c24f     # laufende Reports = Rad ist bereit
tools\ffb_direction_check.ps1           # dreht das Rad 2x3 s, misst die Richtung
"Apex Circuit FFB starten.cmd" --demo   # Fühltest: Gerade, Bogen, Kerb, Blockieren
```

Beide Mängel, die dieser Test hatte — er startete den Helfer wegen eines
Leerzeichens im Pfad nie und ließ ihn bei einem Fehler belegt zurück —, sind
behoben; er schreibt seine Ausgabe nach `tools/ffb_direction_probe.log`.
`powershell -File tools/ffb_end_to_end.ps1` lässt das **echte Spiel** gegen den
**echten Helfer** fahren (1829 Pakete, Kraftspitze **0,584** — genau der
Modellwert, also verlustfrei —, Rütteln 0,700 @ 42 Hz, Quellen und
Schalt-Ereignis angekommen, 10 Prüfungen, 0 Mängel) — die Naht zwischen beiden
Hälften. Die Spitze kommt aus der `[ffb-peak]`-Zeile des Helfers (Maximum aus
jedem Sample des 200-Hz-Loops); die frühere 2-Sekunden-Stichprobe meldete
denselben Lauf einmal mit 0,560 und einmal mit 0,250.
Im Bild ist die Rückmeldung immer da: das HUD zeigt Kraft, Dämpfung, Rütteln
und die Quelle („AM ANSCHLAG“, wenn es clippt), und der Kopf im Cockpit lehnt
sich in die Kurve, nickt beim Bremsen und rüttelt über Kerbs
(`scripts/cockpit_camera.gd`).

Einstellbar ist alles unter **`Esc` → Einstellungen → Force Feedback**:
Stärke (30–100 %), Dämpfung, Rütteln an/aus, die drei Rüttel-Bänder des
offiziellen Spiels (**On Track / Rumble Strip / Off Track Effects**, je
0–100 % in 10-%-Schritten, getrennt wirksam), Lenkbereich
(360/400/450/900°) und Kraftrichtung. Details und die Quellen aus dem
offiziellen Spiel stehen in `docs/FFB_F1_STYLE_PLAN.md`.

Godot **nie direkt** aufrufen, sondern immer über den gesperrten Starter.
Godot schreibt beim Lauf `.godot/` um; zwei Instanzen am selben Projekt
zerschießen diesen Cache, und ein so beschädigter Lauf meldet Fehler *und
trotzdem* „PASS“. Gemessen am 21.09.2026 um 18:56 liefen zwei Läufe
gleichzeitig: `test_lap_drive.gd` brach mit „Could not preload resource script
res://scripts/ffb_link.gd“ ab, das Auto wurde nie gebaut — und der Test meldete
`LAP_DRIVE PASS`. Genau deshalb wertet der Runner so einen Lauf als Fehler:

```
powershell -File tools/run_all_tests.ps1              # alle 18 headless-Testdateien
powershell -File tools/run_all_tests.ps1 -Filter ffb  # nur die FFB-Dateien
```

Der Runner startet jede Datei über `tools/run_godot.ps1` (die Sperre), legt die
Logs unter `tools/testlogs/` ab und zählt eine Datei nur dann als bestanden,
wenn der Exit-Code 0 ist, **keine** Zeile wie `SCRIPT ERROR`, `Parse Error`,
`Nonexistent function` oder `Failed to load script` vorkommt und mindestens
eine `PASS`-Zeile dasteht. Einzeln geht es so:

```
powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/test_ffb_model.gd
```

`tools/run_godot.ps1` wartet zuerst auf die Sperre, bricht mit Exit 125 ab,
wenn trotzdem eine fremde Godot-Instanz am selben Projekt läuft (erfundene
Messwerte wären schlimmer als ein Abbruch), und beendet seinen Godot nach
`-Timeout` Sekunden wirklich — vorher blieb ein hängender Lauf als Waise
stehen und vergiftete jede weitere Messung.

Geprüft werden 18 Dateien: `test_car_orientation`, `test_input_mapping`,
`test_drive_unit`, `test_camera_pose`, `test_lap_drive`, `test_cockpit_wheel`,
`test_gameplay_input`, `test_pedal_ui`, `test_pedal_span`, `test_racing_line`,
`test_gearbox`, `test_tyre_motion`, `test_crash_surfaces`, `test_ffb_link`,
`test_ffb_model`, `test_ffb_settings`, `test_ffb_edge`,
`test_g29_profile_path`.

Zum Nachmessen des Fahrgefühls (schreibt nur Zahlen, keine Dateien):

```
powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_feel.gd
powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_grip.gd
powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_thrust.gd
powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_scrape.gd
powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_brake_crash.gd
powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_barrier_geometry.gd
powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_ffb.gd
powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_review_root.gd
```

`probe_review_root` ist die **Gegenprobe** zum Lenkrad-Modell: sie sucht
Widersprüche zum Plan (Richtung, Anschlag, Clipping, Rüttelbänder,
Fuzz-Ticks) statt den eigenen Code zu bestätigen. `probe_feel` misst
0–100 km/h, Endgeschwindigkeit, Bremsverzögerung in g und
die Querbeschleunigung der KI. `probe_grip` misst die Grip-Kurve auf einer
leeren Fläche, `probe_thrust` den Zusammenhang zwischen `engine_force` und
echter Beschleunigung (rund Faktor 1,58).

`test_lap_drive` fährt die echte Szene und prüft, dass Fahrer- und KI-Auto richtig herum fahren und auf der Strecke bleiben.

`test_cockpit_wheel` prüft die Lenkrichtung einmal komplett durch: ein positiver Lenkwert (rechts) muss das Lenkrad im Cockpit im Uhrzeigersinn drehen, die sichtbaren Vorderräder nach rechts stellen und das Auto nach rechts (Richtung seiner eigenen -X-Achse) fahren lassen.

`test_gameplay_input` ist der Integrationstest in der echten Szene mit einem Test-Lenkrad: Gas beschleunigt (87 km/h), die Bremse stoppt von 87 auf 1 km/h, rechts lenkt nach rechts, und das Cockpit-Lenkrad dreht mit.

`test_pedal_ui` prüft das Einstellungs-Menü selbst: jede Pedal-Zeile existiert, „Achse ändern“ wandert zum nächsten freien Platz (und überspringt belegte Achsen), „Gas ⟷ Bremse tauschen“ tauscht wirklich, die Anzeige folgt der neuen Zuordnung (getretenes Gaspedal = 100 %, Bremse bleibt 0 %), die Wahl landet im Profil, und jeder Menüweg lässt sich wieder verlassen.

`test_tyre_motion` (18 Prüfungen) prüft, dass sich die sichtbaren Räder wirklich mit dem Tempo drehen. Vorher lief die Rotation des Rades gegen die Rotation, die Godot dem Physik-Knoten selbst gibt, und hob sich exakt auf: auf dem Bildschirm stand das Rad bei 150 km/h still, in den Zahlen war davon nichts zu sehen.

`test_ffb_direction` (19 Prüfungen) prüft die **Selbstmessung der Kraftrichtung**: der Helfer schickt seine Achsenstellung mit jedem Lebenszeichen, das Spiel liest dieselbe Achse über SDL und dreht die Kraft um, wenn sie spiegelverkehrt ankommt. Ohne Achsendaten wird nichts behauptet — dann bleibt die Richtung unentschieden statt geraten.

`test_ffb_edge` (6 Prüfungen) prüft die Randfälle des Lenkrad-Modells: ein einzelner NaN/INF-Tick aus der Physik darf die Glättung nicht dauerhaft vergiften (vorher blieb „nan“ im HUD und das Paket war unlesbar) — das Modell heilt sich selbst.

`test_pedal_span` (9 Prüfungen) prüft die Pedal-Kalibrierung gegen ein verdorbenes Profil: eine unmögliche Spannweite, die das Gas auf 53 % deckelte, wird nicht mehr gespeichert, und Vollgas kommt wieder als 1.00 an.

`test_g29_profile_path` (6 Prüfungen) hält fest, dass ein Diagnoselauf das Lenkrad-Profil des Fahrers inhaltlich **und im Zeitstempel** nicht anfasst — `APEX_G29_PROFILE` leitet ihn auf eine Diagnosedatei um. Ohne das überschrieb `tools/ffb_direction_check.ps1` die von Hand kalibrierte Pedalzuordnung.

Diagnose-Werkzeuge (Fensterlauf, weil headless keine Joysticks sieht):

```
powershell -File tools/run_godot.ps1 --path godot_f1 --resolution 320x200 --script tests/probe_g29_hardware.gd
powershell -File tools/run_godot.ps1 --path godot_f1 --resolution 320x200 --script tests/probe_g29_module.gd
powershell -File tools/run_godot.ps1 --path godot_f1 --resolution 320x200 --script tests/probe_g29_profile.gd
powershell -File tools/run_godot.ps1 --path godot_f1 --resolution 1920x1080 --script tests/probe_fps.gd
powershell -File tools/run_godot.ps1 --path godot_f1 --resolution 1280x720 --script tests/shot_game.gd
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
