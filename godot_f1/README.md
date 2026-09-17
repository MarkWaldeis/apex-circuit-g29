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

Wichtig: Das G29 braucht sein **Netzteil**. Hängt nur USB dran, meldet sich das Lenkrad zwar am PC an, sendet aber **keinen einzigen Eingabe-Report** — es kommen also keine Achsendaten an. Das Spiel zeigt das ehrlich an: In den Einstellungen steht dann „G29 verbunden (…), aber noch keine Achsendaten — Lenkrad oder Pedal einmal bewegen; sonst Netzteil und Pedalkabel prüfen“, die Achsenbalken und Pedal-Zeilen zeigen `—` statt erfundener Nullwerte, und das HUD meldet „G29 ohne Achsendaten“.

Das lässt sich unabhängig nachmessen, ohne Godot zu starten:

```
python tools/hid_probe.py 046d:c24f
```

Das Skript liest die rohen HID-Reports direkt über die Windows-HID-Schnittstelle (ohne SDL, DirectInput oder Godot dazwischen). Bei einem betriebsbereiten G29 kommen laufend Reports an; ohne Netzteil läuft jede Abfrage in einen Timeout. Erwartete Ausgabe im Fehlerfall: `report timeout ... (no data)` auf allen drei Schnittstellen, obwohl `usage_page=0x0001 usage=0x0004 input_len=13 values=7` genau die Joystick-Schnittstelle mit sieben Achsen beschreibt.

## Tests (headless)

```
godot --headless --path godot_f1 --script tests/test_car_orientation.gd
godot --headless --path godot_f1 --script tests/test_input_mapping.gd
godot --headless --path godot_f1 --script tests/test_drive_unit.gd
godot --headless --path godot_f1 --script tests/test_camera_pose.gd
godot --headless --path godot_f1 --script tests/test_lap_drive.gd
godot --headless --path godot_f1 --script tests/test_cockpit_wheel.gd
godot --headless --path godot_f1 --script tests/test_gameplay_input.gd
godot --headless --path godot_f1 --script tests/test_pedal_ui.gd
```

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
