# Befund Welle 4 (Agent `wave4_journey`): Pedal-Kalibrierung deckelte das Gas

Prüfer: Agent `wave4_journey`, 21.09.2026. Dieser Bericht ist **keine**
Bestätigung des Vorstands, sondern das Ergebnis eigener Messungen an einem
fremden Prüfauftrag - gefunden wurde etwas, das die Wellen 1-4 nicht gesehen
hatten.

## 1. Was ich zuerst selbst nachgemessen habe (alles grün)

| Prüfung | Ergebnis |
|---|---|
| alle 15 damals vorhandenen `tests/test_*.gd` | alle PASS, 0 FAIL |
| `tests/test_ffb_edge.gd` (neu, NAN-Härtung) | 6 Prüfungen PASS |
| `tests/test_g29_profile_path.gd` (neu, Profilschutz) | 6 Prüfungen PASS |
| `python tools/g29_ffb.py --check` | 12 Prüfungen, 0 Mängel |
| `tools/ffb_end_to_end.ps1` (echtes Spiel → echter Helfer) | 10 Prüfungen, 0 Mängel; Kraftspitze 0,584, Rütteln 0,700 @ 42,2 Hz, Quellen `Asphalt, Blockiert, Kerb, Kies, Schalten` |
| `tools/ship_check.ps1` (ausgelieferter Build) | 3 Prüfungen, 0 Mängel |
| Fahrer-Einstellungen `user://ffb_settings.json` | unverändert, `enabled: true` |

Am **echten Rad** (es lieferte in diesem Zeitfenster Daten) habe ich zusätzlich
gemessen:

```text
python tools/ffb_hw_probe.py --seconds 1.5 --force 0.35
PHASE plus  32767 -> 39      delta=-32728
PHASE minus  1251 -> 27650   delta=+26399
HW_PROBE ANDERS: positive Kraft dreht die Achse nach -, der Helfer braucht --invert
```

Das ist derselbe Befund wie in `ffb_wave4_hardware.md`: eine positive
DirectInput-Kraft fährt die G29-Achse in Richtung ihres Minimums. Ob das im
Spiel „links“ oder „rechts“ ist, entscheidet die Polarität der DirectInput-
Achse gegenüber der SDL-Achse — siehe Abschnitt 4.

## 2. Der Fund: **Vollgas war unmöglich** (P1, Fahrer-sichtbar)

Im Fahrer-Profil `%APPDATA%\Godot\app_userdata\Apex Circuit\g29_profile.json`
stand (Sicherung: `g29_profile.json.bak-20260921-pedale`):

```json
"throttle_rest": 0.0,
"throttle_press": -1.88281071186066,
```

Eine SDL-Achse läuft von −1,0 bis +1,0 (`axis_snapshot()` gibt genau diese
Rohwerte zurück). Ein Druckpunkt bei −1,88 kann also **nie** erreicht werden.
Die Folge in `_pedal_value()`:

* `value = clampf(dev / span, 0, 1)` bleibt bei `1.0 / 1.8828 = 0.531` stehen,
* der Zweig „längeren Weg lernen“ (`absf(c_dev) > absf(c_span)`) kann nie
  greifen, weil `|dev| ≤ 1.0` ist — die Kalibrierung heilt sich **nicht**.

Bewiesen mit einem Regressionstest, der genau diese Profilwerte lädt
(`tests/test_pedal_span.gd`), gegen den Stand **vor** dem Fix:

```text
FAIL vollgas_ist_mit_dem_kaputten_profil_erreichbar  Gaspedal ganz gedrueckt -> 0.53 (kaputt: 0.53)
FAIL halbes_pedal_ist_ungefaehr_halb                 Gaspedal auf -0.50 -> 0.27
FAIL die_unmoegliche_spannweite_wird_nicht_gespeichert throttle_press in der Datei: -1.88
PEDAL_SPAN FAIL count=3
```

Also: **53 % Gas statt 100 %, und bei halbem Pedal 27 % statt 50 %** — das Auto
war die ganze Zeit über am Gas beschnitten, und der Fehler wurde bei jedem
Speichern wieder in die Datei zurückgeschrieben.

### 2.1 Woher der Wert kam (kein Rätsel, eine Kette)

1. Ein Lauf am 17.09. schrieb Ruhepositionen von `1.0` statt `0.0`
   (`g29_profile.json.polluted.bak`: `"throttle_rest": 1.0`,
   `"throttle_press": -1.0`).
2. Die Ruhe-Korrektur in `_anchor_auto_rest()` erkannte „Ruhe stimmt nicht“
   (`absf(now - stored_rest) > 0.5`) und verschob den Druckpunkt **mit
   demselben Abstand**: `now + (stored_press - stored_rest)` →
   `0.0 + (-1.0 - 1.0) = -2.0` (gemessen: −1.8828). Der unbrauchbare Abstand
   wurde also von der Reparatur mitgeschleppt.

## 3. Der Fix (drei Stellen, alle in `godot_f1/scripts/g29_input.gd`)

Die Regel lautet: ein Kalibrierpunkt muss **auf** der Achse liegen
(`PEDAL_AXIS_LIMIT 1.02`). Ein Abstand bis 2.0 bleibt erlaubt — ein Pedal über
die ganze Achse (Ruhe +1,0, Druck −1,0) ist eine gültige Bauart und wird von
`tests/test_input_mapping.gd` → `_pedal_polarities` verlangt.

1. `load_profile()`: glaubt eine gespeicherte Kalibrierung nur noch, wenn
   `absf(p - r) >= 0.15` **und** beide Punkte auf der Achse liegen.
2. `_pedal_value()`: verwirft eine geladene Kalibrierung mit einem Punkt neben
   der Achse (oder einer Spannweite < 0,15), löscht beide Punkte, markiert das
   Profil als schmutzig und überlässt das Pedal der automatischen Zuordnung.
3. `_anchor_auto_rest()`: verschiebt nur noch, wenn der verschobene Punkt auf
   der Achse landet; sonst wird die Kalibrierung verworfen und neu gelernt.

Nach dem Fix:

```text
PASS vollgas_ist_mit_dem_kaputten_profil_erreichbar Gaspedal ganz gedrueckt -> 1.00 (kaputt: 0.53)
PASS halbes_pedal_ist_ungefaehr_halb                Gaspedal auf -0.50 -> 0.50
PASS die_unmoegliche_spannweite_wird_nicht_gespeichert throttle_press in der Datei: 0.00
PASS gespeicherte_kalibrierung_wird_benutzt         Gaspedal auf -0.50 mit Kalibrierung 0.0 .. -1.0 -> 0.50
PASS ganze_achse_druck_ist_voll                     Achse -1.00 -> 1.00
PEDAL_SPAN PASS 8 Pruefungen
```

### 3.1 Zwischenschritt, der zu grob war (ehrlich)

Der erste Versuch verwarf jede Spannweite über 1,05. Damit wurde
`test_input_mapping.gd` rot:

```text
FAIL opposite_polarity_press_is_one gas=0.00
FAIL opposite_polarity_not_inverted
INPUT_MAPPING FAIL count=2
```

Der Test hatte recht — die Regel war falsch, nicht der Test. Deshalb prüft der
Fix jetzt **Punkte gegen die Achse**, nicht die Spannweite gegen eine
willkürliche Grenze, und `test_pedal_span.gd` deckt den ganzen-Achse-Fall
selbst mit ab.

## 4. Fahrer-Profil repariert

Die Sicherung des kaputten Stands liegt neben der Datei
(`g29_profile.json.bak-20260921-pedale`, 477 Bytes). In
`g29_profile.json` sind die drei Pedal-Punkte auf `0.0 / 0.0` gesetzt — genau
der Zustand, den `save_profile()` nach dem Verwerfen schreibt. Beim nächsten
Start lernt das Spiel die Pedale automatisch: Ruhe beim ersten glaubhaften
Sample, Druckpunkt beim weitesten Durchtreten. Die Achsen (`gas=2, brake=3,
clutch=1`), die Lenkrad-Kalibrierung (`steer_span 0.5547`, `steer_invert
false`) und `version 2` bleiben unangetastet.

## 5. Was weiter offen bleibt

1. **Kraftrichtung (der letzte offene Punkt).** Gemessen ist: positive
   DirectInput-Kraft → Achse zum Minimum. Welche Richtung das *im Spiel* ist,
   hängt daran, ob die DirectInput-Achse dieselbe Polarität hat wie die
   SDL-Achse, aus der das Spiel „rechts = +1“ kalibriert hat (`steer_invert:
   false`). Das entscheidet `tools\ffb_direction_check.ps1` in 5 Sekunden am
   freien Rad (Hände weg, das Rad dreht 2×3 s mit 0,35 Kraft). Solange das Rad
   keine Achsdaten liefert, ist der Lauf wertlos — er meldet das dann auch so.
2. **Hardware-Zuverlässigkeit.** Das Rad liefert zeitweise Achsen und Kraft,
   zeitweise nichts (`tools/ffb_hw_probe.py --force 0` → `delta=+0`).
3. **Fühltest.** `"Apex Circuit FFB starten.cmd" --demo` bzw. eine Runde im
   Spiel — das kann Software nicht entscheiden.
4. **Auslieferung.** Nach diesem Fix (und den Änderungen der Welle-4-Agenten
   an `ffb_model.gd`, `ffb_settings.gd`, `g29_input.gd`) ist der Desktop-Build
   erneut zu exportieren und mit `tools/ship_check.ps1` zu messen.
