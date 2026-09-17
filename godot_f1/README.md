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
* **Standardwerte** — zurück auf Lenkachse 0, Gas 1, Bremse 2, Kupplung 3.
* **Lenkrad invertieren** — falls links/rechts vertauscht ist.

Das Ergebnis landet in `user://g29_profile.json` (`%APPDATA%\Godot\app_userdata\Apex Circuit\`) und wird beim nächsten Start automatisch geladen. Vor der ersten Kalibrierung arbeitet das Spiel mit einer automatischen Schätzung, damit man sofort fahren kann.

Wichtig: Das G29 braucht sein **Netzteil**. Hängt nur USB dran, wird das Lenkrad erkannt, liefert aber keine Achsendaten — die Einstellungen zeigen dann den Hinweis „G29 erkannt, aber es kommen keine Achsendaten an“.

## Tests (headless)

```
godot --headless --path godot_f1 --script tests/test_car_orientation.gd
godot --headless --path godot_f1 --script tests/test_input_mapping.gd
godot --headless --path godot_f1 --script tests/test_drive_unit.gd
godot --headless --path godot_f1 --script tests/test_camera_pose.gd
godot --headless --path godot_f1 --script tests/test_lap_drive.gd
```

`test_lap_drive` fährt die echte Szene und prüft, dass Fahrer- und KI-Auto richtig herum fahren und auf der Strecke bleiben.

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
