# Apex Circuit — G29 Formel-1

Eigenes Formel-1-Spiel für **Logitech G29** (Lenkrad + Pedale), gebaut mit **Blender 5.2** und **Godot 4.7**.

GitHub: https://github.com/MarkWaldeis/apex-circuit-g29

## Schnellstart

Doppelklick auf **Apex Circuit** auf dem Desktop, oder auf `Apex Circuit starten.lnk` im Projektordner.

Die eigentlichen Dateien liegen in:

- Desktop: `Apex Circuit\Apex Circuit.exe` (+ `.pck`, muss daneben liegen)
- Projekt: `ApexCircuit\ApexCircuit.exe` (+ `.pck`)

Falls die Datei noch nicht da ist, in Godot 4.7 den Ordner `godot_f1` öffnen und **Projekt → Exportieren → Windows Desktop**.

1. Godot 4.7 öffnen und den Ordner `godot_f1` importieren, oder:

```
godot --path godot_f1
```

2. G29 anschließen (optional). Ohne Lenkrad: `WASD` / Pfeiltasten.
3. Der Wagen startet im Auto-Pilot und fährt die Linie. `Enter` schaltet auf Manual. Gas am G29 übernimmt ebenfalls.

## Projektstruktur

| Ordner | Inhalt |
|---|---|
| `godot_f1/` | Spiel (Godot 4.7) |
| `blender/` | Blend-Datei, Python-Scripts, Source- und Export-GLBs |
| `blender/source_assets/` | Original-Modelle |
| `blender/exports/cars/` | 6 Low-Poly-Lackierungen, Reifen getrennt |
| `blender/exports/track/` | Apex Circuit + Racing Line |
| `docs/` | Inventar (Excel) |

## Steuerung

Siehe `godot_f1/README.md`.
