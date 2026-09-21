# Kraftrichtung: aus der Annahme wird eine Messung

Autor: Agent `wave4_journey`, 21.09.2026 (Welle 5). Kein Prüfbericht, sondern
die Umsetzung des letzten offenen Punktes aus `ffb_wave4_hardware.md` §5.

## 1. Was offen war

Gemessen war nur die halbe Kette:

```text
python tools/ffb_hw_probe.py --seconds 1.5 --force 0.35
PHASE plus  32767 -> 39      delta=-32728
HW_PROBE ANDERS: positive Kraft dreht die Achse nach -
```

Eine positive DirectInput-Kraft fährt die G29-Achse zu ihrem **Minimum** — am
echten Rad viermal reproduziert. Ob „Achse runter“ im Spiel links oder rechts
ist, hängt aber daran, wie die DirectInput-Achse zur **SDL**-Achse steht, aus
der das Spiel „rechts = +1“ gelernt hat (`steer_invert: false`,
`steer_span 0.5547`). Diese zweite Hälfte war eine **Annahme**. Falsch geraten
hieße das: das Rad drückt in der Kurve nach außen statt nach innen — genau das
Gegenteil von „echt“.

Der Test, der es entscheidet (`tools/ffb_direction_check.ps1`), bewegt das Rad
zweimal drei Sekunden mit Kraft. Er wurde nicht ausgeführt.

## 2. Die Lösung: das Spiel misst es beim Fahren selbst

Beide Seiten lesen dieselbe Achse, nur über verschiedene Schnittstellen:

* Der Helfer liest sie über **DirectInput** — er schickt seinen Rohwert jetzt
  mit jedem Lebenszeichen mit (10 Hz, Feld `axis`, 0…65535).
* Das Spiel liest sie über **SDL** (`g29_input.axis_snapshot()`), und es weiß
  aus der Kalibrierung des Fahrers, welche Richtung „rechts“ ist.

Dreht der Fahrer das Lenkrad, zeigen beide Werte entweder in dieselbe Richtung
(gleichläufig) oder in entgegengesetzte (gegenläufig). Aus dieser einen
Beobachtung folgt die richtige Kraftrichtung ohne jede Annahme:

* **gleichläufig** → „Achse runter“ ist links, die positive Kraft fährt dorthin
  → Kraftrichtung **umgekehrt**,
* **gegenläufig** → „Achse runter“ ist rechts, die positive Kraft fährt dorthin
  → Kraftrichtung **normal**.

Umgesetzt in `godot_f1/scripts/ffb_link.gd::measure_direction()`:

* Die **Mitte** der Helferachse wird gelernt (gemessen ruht sie je nach Lauf
  bei 32767 bis 33104 — ein fester Nullpunkt wäre schon schief).
  Erst ab 10 ruhigen Samples und ab 15 % Lenkeinschlag wird überhaupt gezählt.
* Fünf **verschiedene** Lebenszeichen müssen dieselbe Aussage liefern (nicht
  fünfmal dieselbe Zahl: die Antwort kommt mit 10 Hz, die Physik mit 90 Hz).
* Bei fehlenden Achsdaten (Rad stromlos) bleibt das Ergebnis **unbekannt** —
  `direction_aligned = -1`, keine Meldung, keine Änderung.
* Angewandt wird erst, wenn das Rad **leicht** ist (`|torque| ≤ 0,15`). Ein
  Vorzeichenwechsel mitten im Bogen wäre ein Ruck, den niemand versteht.
* Der Fahrer behält das letzte Wort: `invert_source` steht in der
  Einstellungsdatei. Sobald er den Schalter im Menü selbst anfasst, steht dort
  `"fahrer"` und die Automatik hält sich dauerhaft heraus.

## 3. Messungen

```text
python tools/g29_ffb.py --check
PASS das_lebenszeichen_traegt_die_achsenstellung axis=21234 (erwartet 21234)
PASS ohne_rad_keine_erfundene_achse Felder ohne Rad: ['ack', 'mode', 'torque', 'v']
FFB_CHECK PASS 14 Pruefungen, 0 Mangel
```

```text
powershell -File tools\run_godot.ps1 --headless --path godot_f1 --script tests/test_ffb_direction.gd
PASS ohne_achsenwert_keine_entscheidung direction_aligned=-1
PASS gleichlaeufig_erkannt direction_aligned=1 nach 5 Stimmen
PASS gleichlaeufig_dreht_die_kraft_um invert=true
PASS gegenlaeufig_erkannt direction_aligned=0
PASS gegenlaeufig_laesst_die_kraft_in_ruhe invert=false
PASS fahrerwahl_schaltet_die_automatik_aus auto_direction=false
PASS im_bogen_wird_gemessen direction_aligned=1
PASS im_bogen_kein_vorzeichenwechsel invert=false bei Kraft 0.62
PASS auf_der_geraden_wird_es_gesetzt invert=true
FFB_DIRECTION PASS
```

19 Prüfungen, alle grün. Dazu die ganze Kette unverändert:

| Prüfung | Ergebnis |
|---|---|
| alle 19 `godot_f1/tests/test_*.gd` | PASS, 0 FAIL |
| `tools/ffb_end_to_end.ps1` | 10 Prüfungen, 0 Mängel (Spitze 0,584, Rütteln 0,700 @ 42,2 Hz) |
| `python tools/g29_ffb.py --check` | 14 Prüfungen, 0 Mängel |
| `tools/ship_check.ps1` | siehe Welle-5-Bericht des Root (ausgelieferter Build) |

### 3.1 Ein Fehler, den der Test selbst gefunden hat

Die erste Fassung wandte eine gefällte Entscheidung nur dann an, wenn sie
*erneut* bestätigt wurde — neue Bestätigungen gibt es aber nur beim Lenken,
also genau dann, wenn Kraft am Rad liegt. Auf der Geraden wäre die Entscheidung
damit nie angekommen:

```text
FAIL auf_der_geraden_wird_es_gesetzt invert=false
```

Behoben: Steht die Entscheidung, wird sie in **jedem** Tick erneut zu setzen
versucht, bis das Rad ruhig genug ist. Danach ist `FFB_DIRECTION PASS`.

## 4. Was jetzt noch offen ist

1. **Der Fühltest am Rad.** Software kann messen, dass die Kraft in die richtige
   Richtung geht, aber nicht, ob sie sich *richtig anfühlt*:
   `"Apex Circuit FFB starten.cmd" --demo` bzw. eine Runde fahren.
2. **Die Zuverlässigkeit der Hardware.** Das Rad liefert zeitweise Achsdaten
   und Kraft, zeitweise nicht; dann bleibt die Richtungsmessung ehrlich bei
   „unbekannt“, bis Bewegung und Achsen wieder da sind.
