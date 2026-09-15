# Apex Circuit

Formel-1-Spiel für **Godot 4.7** mit **Logitech G29** (Lenkrad + Pedale). Tastatur funktioniert als Fallback. Der Wagen startet im Auto-Pilot und folgt der Rennlinie.

## Steuern

| Eingabe | Aktion |
|---|---|
| G29-Lenkrad | Lenken |
| G29-Gas / -Bremse | Beschleunigen / Bremsen |
| `W` / Pfeil hoch | Gas |
| `S` / Pfeil runter | Bremse |
| `A`/`D` oder Pfeile | Lenken |
| `Enter` | Auto-Pilot an/aus |
| `R` | Reset auf die Startaufstellung |
| `C` | Kamera (Chase / Onboard / Helikopter) |
| `Esc` | Beenden |

Sobald das G29 über den Totbereich hinaus bewegt wird, schaltet der Auto-Pilot ab.

## Starten

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
