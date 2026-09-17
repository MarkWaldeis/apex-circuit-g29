# Apex Circuit — G29 Formel-1

Eigenes Formel-1-Spiel für **Logitech G29** (Lenkrad + Pedale), gebaut mit **Blender 5.2** und **Godot 4.7**.

GitHub: https://github.com/MarkWaldeis/apex-circuit-g29

## Was das Spiel kann

* **Startmenü** mit *Fahren*, *Einstellungen* und *Beenden*; `Esc` öffnet jederzeit das Pausenmenü und führt immer wieder zurück ins Rennen.
* **Pedale selbst anlernen**: unter *Einstellungen* Gas, Bremse und Kupplung einzeln kalibrieren — Taste drücken, Pedal durchtreten, das Spiel erkennt die Achse und merkt sie sich (`user://g29_profile.json`). Die Zuordnung verbessert sich danach von selbst, wenn du im Rennen härter trittst.
* **Lenkrad-Kalibrierung** inklusive Drehrichtung.
* **Cockpit-Ansicht**, in der sich das Lenkrad im Spiel mit dem echten G29 mitdreht, mit Schaltblitzen und Pedalanzeige im HUD.
* Der Wagen fährt vorwärts in die richtige Richtung (Nase = Fahrtrichtung), Vorderräder lenken sichtbar mit, Hinterräder treiben an.
* **Lenkrichtung stimmt**: rechts am Lenkrad ist rechts im Spiel — Cockpit-Lenkrad, sichtbare Vorderräder und die Fahrphysik drehen alle in dieselbe Richtung (`godot_f1/tests/test_cockpit_wheel.gd`).

## Schnellstart

Doppelklick auf **Apex Circuit** auf dem Desktop, oder auf `Apex Circuit starten.lnk` im Projektordner.

Die eigentlichen Dateien liegen in:

- Desktop: `Apex Circuit\Apex Circuit.exe` (+ `.pck`, muss daneben liegen)
- Projekt: `ApexCircuit\ApexCircuit.exe` (+ `.pck`)

Falls die Datei noch nicht da ist, in Godot 4.7 den Ordner `godot_f1` öffnen und **Projekt → Exportieren → Windows Desktop**, oder:

```
export_windows.cmd
```

1. Godot 4.7 öffnen und den Ordner `godot_f1` importieren, oder:

```
godot --path godot_f1
```

2. G29 anschließen (optional, **Netzteil nicht vergessen**). Ohne Lenkrad: `WASD` / Pfeiltasten.
3. Im Menü *Fahren* wählen — der Wagen wartet auf dem Startplatz auf dein Gas. `Enter` schaltet den Auto-Pilot ein.
4. Wenn Gas und Bremse vertauscht sind: `Esc` → *Einstellungen* → *Gas kalibrieren*.

## Projektstruktur

| Ordner | Inhalt |
|---|---|
| `godot_f1/` | Spiel (Godot 4.7) |
| `godot_f1/scripts/` | Fahrphysik, G29-Eingabe, Menü, HUD, Kameras |
| `godot_f1/tests/` | Headless-Tests (Ausrichtung, Eingabe, Fahrphysik, Runde) |
| `godot_f1/assets/shaders/` | Lack-Shader (die GLBs enthalten keine Lackfarbe) |
| `blender/` | Blend-Datei, Python-Scripts, Source- und Export-GLBs |
| `blender/source_assets/` | Original-Modelle |
| `blender/exports/cars/` | 6 Low-Poly-Lackierungen, Reifen getrennt |
| `blender/exports/track/` | Apex Circuit + Racing Line |
| `tools/glb_probe.py` | Diagnose: schneidet ein GLB entlang Z (welches Ende ist die Nase?) |
| `tools/hid_probe.py` | Diagnose: liest rohe HID-Reports des G29 (Netzteil-/Kabel-Check ohne Godot) |
| `docs/` | Inventar (Excel) |

## Wenn das Lenkrad nicht reagiert

Windows erkennt das G29 auch dann, wenn es **keine** Daten liefert — typisch, wenn das Netzteil nicht angeschlossen ist. Prüfen:

```
python tools/hid_probe.py 046d:c24f
```

Kommt nur `report timeout ... (no data)`, obwohl die Joystick-Schnittstelle mit sieben Achsen beschrieben wird, dann sendet das Lenkrad selbst nichts: Netzteil prüfen, Pedalkabel am Lenkrad festziehen, anderes USB-Port (möglichst direkt hinten am PC, kein Hub) probieren, Modusschalter am Lenkrad auf **PC** stellen. Danach im Spiel `Esc` → *Einstellungen* → *Gas kalibrieren*.

Einfacher geht es per Doppelklick im Projektordner: **`Lenkrad pruefen.cmd`** startet dieselbe Prüfung und zeigt die Checkliste an.

## Steuerung

Siehe `godot_f1/README.md`.
