# Welle 8 — Das Warten schützte nur den ersten Start

Auftrag: „Fahrgefühl am Lenkrad so echt wie im offiziellen Spiel“ — hier der
Teil, der sich am **Neustart** entscheidet, nicht am ersten Start.
Stand: 21.09.2026, Prüfung ohne Subagenten (die Slots waren durch frühere
Wellen belegt), dafür mit eigenen Messungen und Gegenproben.

## Der Fund

Welle 7 hat gemessen: das G29 verträgt nur eine Reihenfolge. Übernimmt der
Kraft-Helfer (`tools/g29_ffb.py`) das Rad **vor** dem Spiel, bekommt das Spiel
keine Achsendaten mehr, und das Rad steht auch für den Helfer still. Behoben
wurde das mit `wait_for_game()`: der Helfer öffnet das Rad erst nach dem ersten
Paket des Spiels.

**Das schützt aber nur den ersten Start.** Nach dem Ende einer Sitzung:

```
[ffb-peak] torque=0.000 rumble=0.127 hz=41.2 over=0 packets=468 speed=74.6 clip=0.000
[ffb] 468 Pakete, torque=+0.00 damp=0.10 fric=0.05 rumble=0.00@41Hz ... [idle]
```

Die `[idle]`-Zeile ist der Beweis: der Helfer fällt nach `--idle-release`
(Standard 0,5 s) auf ein **Ruhegewicht** zurück (`damp=0.10 fric=0.05`) und
bleibt dabei im Loop. Im ganzen Loop gibt es kein `wheel.close()` — das Gerät
wurde nur im `finally` beim Beenden des Programms geschlossen.

Daraus folgt die Falle:

1. `Apex Circuit FFB starten.cmd` → Spiel zuerst, Helfer wartet, übernimmt das
   Rad nach dem ersten Paket. Alles läuft.
2. Spiel beenden (Esc). Der Helfer läuft weiter — und **hält das Rad**.
3. Spiel neu starten (Desktop-Symbol). Das Spiel öffnet das Rad über SDL,
   während der Helfer es exklusiv hält: genau der in Welle 7 gemessene Fall
   (`Spiel sieht data=false`).

Der Hinweis im HUD („Spiel neu starten, dann den Kraft-Helfer“) nennt zwar die
richtige Reihenfolge, aber der Helfer ist ja schon da — der Fahrer müsste das
Helfer-Fenster schließen **und** das Spiel neu starten. Das ist keine
Einstellung, das ist eine Falle.

## Was geändert wurde

`tools/g29_ffb.py`:

* **`--release-wheel-after SEKUNDEN`** (Standard 30, `0` = aus): so lange ohne
  Paket, dann **schließt** der Helfer das Lenkrad wirklich (`wheel.close()`) —
  nicht nur die Kraft weg. Die Meldung sagt, was passiert:

  ```
  [ffb] kein Spiel seit 30 s - Lenkrad freigegeben (Haende weg). Startet das Spiel neu,
  uebernimmt der Helfer es von selbst wieder.
  ```

* **Zurückholen erst bei Paketen.** Sobald wieder ein Paket kommt, baut der
  Helfer das Rad erneut auf — also **nach** dem Spiel, in der gemessen sicheren
  Reihenfolge. Ohne Paket passiert nichts (kein „schon wieder der Erste“). Der
  Kraftzustand wird bei der Freigabe zurückgesetzt, damit nichts nachhängt.
* Die Freigabe greift nur, wenn wirklich ein Rad offen ist (`wheel_override` und
  Trockenlauf unberührt) — die bestehenden Messungen der anderen Wellen
  (`--dry-run`, `tools/ffb_end_to_end.ps1`, `tools/ship_check.ps1`) laufen
  unverändert, weil dort kein Rad geöffnet wird.

## Beweise

### 1. Kette ohne Lenkrad (`python tools/g29_ffb.py --check`)

```
PASS das_rad_wird_freigegeben_wenn_das_spiel_weg_ist offen vor dem ersten Paket: False
     (muss False sein), nach Paketen offen: True (muss True sein), freigegeben: True,
     wartet danach: True, zurueckgeholt: True (Oeffnen 2, Freigaben 1)
PASS die_freigabe_kann_ausbleiben Gegenprobe mit --release-wheel-after 0:
     freigegeben = False (muss False sein; ohne die Freigabe bleibt das Rad offen,
     genau der Fall, der den Neustart blind machte)
FFB_CHECK PASS 20 Pruefungen, 0 Mangel
```

Beide neuen Prüfungen sind falsifizierbar: die erste verlangt *alle vier*
Zeitpunkte (warten → öffnen → freigeben → warten → zurückholen), die zweite
zeigt, dass die Prüfung „aus“ auch erkennt.

### 2. Am echten G29 (Spy um `G29ForceFeedback`, synthetischer Sender)

```
[ffb] warte auf das Spiel, bevor das Lenkrad uebernommen wird (das Spiel muss das Rad zuerst oeffnen)
[ffb] das Spiel sendet - jetzt uebernimmt der Helfer das Lenkrad
[ffb] G29 Driving Force Racing Wheel bereit, Effekte: const, damper, friction, spring, rumble
[live] Rad geoeffnet  #1  G29 Driving Force Racing Wheel
[ffb] kein Spiel seit 2 s - Lenkrad freigegeben (Haende weg). ...
[live] Rad geschlossen #1
[ffb] das Spiel sendet wieder - Lenkrad erneut uebernommen (es war freigegeben, ...)
[live] Rad geoeffnet  #2  G29 Driving Force Racing Wheel
[live] Oeffnen: 2  Freigaben: 2  report: releases=2 reopens=1
```

Geprüft wurde mit `release_after = 2,5 s`: senden → 4 s Pause → senden. Das Rad
wird wirklich geschlossen (der Treiber gibt das Gerät frei) und danach wirklich
erneut geöffnet — beide DirectInput-Öffnungen gelangen, die Effekte
(`const, damper, friction, spring, rumble`) sind beim zweiten Mal wieder da.
Die zweite Freigabe am Ende ist korrekt: nach dem letzten Paket lief die Pause
weiter.

### 3. Was **nicht** gemessen ist

Ob das **Spiel** die Achse weiterliest, wenn der Helfer sie während einer
laufenden Sitzung freigibt und zurückholt (Pausenmenü länger als 30 s — das
Menü pausiert den Szenenbaum, `menu.gd`: `get_tree().paused = target != Screen.NONE`,
und `g29_input` läuft mit `PROCESS_MODE_ALWAYS` weiter). Die Messung dafür
braucht das Rad allein und ein **Fenster** (headless zählt Godot keine
Joysticks auf):

```
python tools/g29_ffb.py --release-wheel-after 3
powershell -File tools/run_godot.ps1 --path godot_f1 --resolution 320x200 --script tests/probe_axis_track.gd
```

Erwartung: `AXIS_TRACK ... data=true` auch nach der Freigabe, und die Spanne
wächst weiter, sobald der Helfer das Rad zurückgeholt hat. Bis dahin gilt für
die Freigabe derselbe Beweisstand wie in Welle 7 für das erste Öffnen: das
Öffnen **nach** dem Spiel ist gemessen sicher, das Öffnen während ein anderes
Programm das Rad liest war genau der Welle-7-Fall „Spiel zuerst, dann Helfer“
(`AXIS_TRACK t=12 a0=+0.996 span=1.996 data=true`).

## Was der Fahrer davon merkt

* Das Helfer-Fenster darf offen bleiben: mehrere Runden, Spiel-Neustarts,
  Pausen — das Rad wird von allein freigegeben und von allein zurückgeholt.
* Während der Helfer freigegeben hat, liegt **keine** Kraft an (kein
  „festgenageltes“ Rad im Stand) — dieselbe Regel wie im Plan („Stillstand,
  Motor aus/im Menü: Kraft fällt auf null“).
* `--release-wheel-after 0` stellt das alte Verhalten her (nie freigeben), falls
  es je stören sollte.
