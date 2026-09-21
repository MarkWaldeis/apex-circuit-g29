# Prüfbericht: Kette Spiel → Helfer → Lenkrad (Welle 1)

Prüfer: fremder Agent `review_ffb_chain` (nicht der Autor des Modells).
Auftrag: das Lenkrad-Gefühl soll wie im offiziellen F1-Spiel sein — geprüft
wird hier der Weg **vom gerechneten Wert bis zur Kraft am G29**:

```
car_controller.gd → ffb_model.gd → ffb_link.gd (UDP v2, JSON)
                  → tools/g29_ffb.py (DirectInput) → G29
```

Alle Zahlen unten stammen aus Läufen dieses Turns. Läufe, die Godot starten,
gehen über `tools/run_godot.ps1` (Serialisierung, sonst korrumpiert der
Godot-Cache parallele Läufe).

## 1. Der Vertrag, an dem gemessen wird

`ffb_link.gd` dokumentiert das Protokoll v2, und das ist die Messlatte:

* `torque` ist die **Grundkraft** (‑1…+1, + drückt nach rechts). Die Stärke aus
  dem Menü steckt dort schon drin — genau **einmal**.
* `pulse`/`pulse_dir` ist ein **eigener, einmaliger Stoss** (Schalten,
  Einschlag) und sitzt sofort auf der Kraft.
* `gain` ist die **Meldung**, wie stark das Menü steht — kein zweiter
  Verstärker.
* `rumble`/`rumble_hz`, `damper`, `friction`, `spring` sind eigene Kanäle.
* `source`, `clip`, `damage`, `event`, `speed` sagen, **woher** die Kraft
  kommt.

## 2. Gefundene Mängel

| Nr. | Mangel | Messung | Status |
|---|---|---|---|
| 1 | **Stärke wurde zweimal angewendet** — `ffb_model.gd` multipliziert mit der Menü-Stärke, `tools/g29_ffb.py` multiplizierte das Ergebnis noch einmal mit dem `gain`-Feld. | Modell 0,797 bei 100 %; bei 75 % kamen **0,598** an, bei 45 % **0,161** (statt 0,359 = 20 %), bei 30 % **0,072** = 9 % — die Stufen wirkten quadratisch. | behoben |
| 2 | **Der Kettentest konnte stillschweigend überspringen**: `FFB SKIP port busy` mit Exit-Code 0. Ein kaputter Kanal wäre unbemerkt durchgegangen. | Zwei Läufe hintereinander meldeten SKIP, obwohl nichts mehr auf dem Port saß (alter Godot-Prozess). | behoben |
| 3 | **Der Kanal sendete real 45 Hz statt der zugesagten 60 Hz.** Der Akkumulator wurde nach jedem Senden auf 0 gesetzt; bei 90-Hz-Physik liegt 1/60 s zwischen zwei Ticks, also wurde jeder zweite Tick verschenkt. | `sent=159` in 3,6 s = 44,2 Hz; live 1036 Pakete in 30 s. Nach dem Fix: **212 in 3,6 s = 59,6 Hz**. | behoben |
| 4 | **Der Puls verlor 12 % vor dem ersten Sample**: die Abklingstufe lief, bevor ein neu angekommenes Paket gesetzt war. | `pulse=0.40` → am Rad **0,251** statt 0,280. Nach dem Fix: **0,280** = 70 % des Pulses (der Rest ist `PULSE_MIX`). | behoben |
| 5 | **Der Helfer starb mit Traceback**, wenn der Port belegt war (`WinError 10013`). | Zweiter Start auf einem frisch von einem Test gehaltenen Port: Traceback statt Meldung. Jetzt: klare Zeile, Exit 1. | behoben |
| 6 | **Ein zweiter Helfer hätte den ersten still abgehängt** (Windows gibt die Pakete dem zuletzt gebundenen Socket). | Mit `SO_EXCLUSIVEADDRUSE` kommt jetzt `WinError 10048` und die klare Meldung „Port … ist belegt“. | behoben |
| 7 | **`source`, `clip`, `damage`, `event`, `speed` waren blinde Passagiere** — sie wurden gesendet, aber vom Helfer nie gelesen. | Der Helfer kennt jetzt Quellen und Clipping: `[ffb-dry] Quellen der Kraft {'Asphalt': 1081, 'Kerb': 150, 'Kies': 151, 'Blockiert': 134}`. | behoben |
| 8 | **Der Stoss kam über zwei Wege.** `ffb_model.gd` legte ihn schon in `torque` (0,55·pulse, **vor** der 45-ms-Glättung), `tools/g29_ffb.py` legte ihn aus `pulse` ein zweites Mal drauf (0,70·pulse). | Schalten (pulse 0,40): 0,165 + 0,280 = **0,445** statt 0,400 (111 %). Einschlag (pulse 1,0): 0,4125 + 0,70 = **1,11** → der Helfer kappt auf 1,0, **13 % des Schlags gehen verloren**. | **behoben** (Root, nach diesem Bericht): `torque` ist jetzt die Grundkraft **ohne** Stoss, der Stoss fährt nur auf `pulse`/`pulse_dir`. Gemessen: Einschlag lässt die Grundkraft unverändert (0,790 → 0,790, Modelltest `einschlag_laesst_die_grundkraft_unveraendert`), `--check` prüft `torque 0,40 + pulse 0,40 → 0,680`, die alte WARN-Zeile ist weg (`FFB_CHECK PASS 9 Prüfungen, 0 Mangel`). |
| 9 | **Doku wich von der Messung ab.** `docs/FFB_F1_STYLE_PLAN.md` §3.4 versprach „Angriff ~5 ms für Stöße, Release ~150 ms“. | Gemessen: Grundkraft 25 ms auf Vollausschlag (`TORQUE_RISE = 40/s` bei 200 Hz), Release 125 ms (`TORQUE_FALL = 8/s`); nur der **Puls** umgeht die Rampe. §7-Zahlen waren teils veraltet („blockieren 0,285/33 Hz“ → gemessen **0,143 (18 %) / 34 Hz**; Rundenspitze 0,588 → 0,592). | **behoben** (Root): §3.4 nennt jetzt 25 ms / 125 ms und den Puls als Ausnahme, §7 trägt die frischen Messwerte (Runde Mittel 0,095 · Spitze 0,584 · blockieren 18 % · Kette 212/212 = 59,6 Hz). |

Zu Mangel 8 — der Kommentar in `ffb_model.gd:260` („Ein Schlag sitzt sofort auf
der Kraft, nicht erst nach der Glättung“) beschreibt genau das, was der Code
**nicht** tut: addiert wird vor der Glättung. Sofort spürbar ist der Stoss
heute nur, weil der Helfer ihn ein zweites Mal draufsetzt. Sauber ist genau
einer der beiden Wege:

* entweder `torque` ist die Grundkraft und der Helfer setzt `pulse` (so steht
  es im Protokoll) → dann darf `ffb_model.gd` den Stoss nicht in `raw` addieren;
* oder das Modell rechnet den Stoss selbst ein → dann muss er **nach** der
  Glättung addiert werden (der Kommentar stimmt dann auch), und der Helfer
  fasst `pulse` bei v2-Paketen nicht an.

## 3. Messungen der Kette (alles ohne Hardware reproduzierbar)

| Prüfung | Werkzeug | Ergebnis |
|---|---|---|
| Pakete kommen an | `tests/test_ffb_link.gd` | 212 Pakete in 3,6 s, 0 kaputt, 0 außerhalb der Grenzen |
| Sendetakt | `tests/test_ffb_link.gd` | **59,6 Pakete/s** (vorher 44,2) |
| Sendetakt unter Volllast | `probe_ffb.gd` + Helfer | 1516 Pakete in 32 s = 47,4 Hz — jetzt begrenzt der Physik-Takt, nicht mehr der Akkumulator |
| Paketinhalt = Modellkraft | `tests/test_ffb_link.gd` | Paket 0,000 = Modell 0,000; Spitze im Live-Lauf −0,592 = Modellspitze −0,592 |
| Stärke genau einmal | `python tools/g29_ffb.py --check` | Paket 0,797 mit `gain` 0,75 → Rad **0,797** (nicht 0,598) |
| Rampe | `--check` | größter Sprung 0,200 pro Sample = 25 ms auf Vollausschlag, kein Sprung |
| Kraft loslassen | `--check` | 0,5 s ohne Paket → 0,000 |
| Alter Sender (v1) | `--check` | `force=0,5` → 0,500, 59 v1-Pakete gelesen |
| Müll und Extremwerte | `--check` | 36 kaputte Pakete verworfen, kein Absturz, Werte auf 1,000 geklemmt |
| Puls | `--check` | `pulse=0,40` → 0,280 sofort (70 % = `PULSE_MIX`) |
| Zweiter Helfer | Handlauf | klare Meldung, Exit 1, kein Traceback |
| Bestand | alle 14 Tests in `godot_f1/tests/` | **alle PASS** (Orientierung, Eingabe, Runde, Getriebe, Crash, Linie, Reifen, FFB-Modell 24 Prüfungen, FFB-Einstellungen 21 Prüfungen) |

Nicht widerlegen konnte ich: die Rampenwerte als solche (25 ms / 125 ms sind
für ein Zahnradlenkrad plausibel und verhindern Treppchen), das Loslassen im
Leerlauf, die v1-Kompatibilität und den Aufbau des Protokolls.

## 4. Was die Prüfung dauerhaft absichert

```text
python tools/g29_ffb.py --check              # 8 Prüfungen, Exit 0/1, ohne Lenkrad
python tools/g29_ffb.py --dry-run            # Pakete, Rampe, Quellen, Endzustand
powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/test_ffb_link.gd
powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/test_ffb_settings.gd
```

`--check` läuft gegen den **echten** Brücken-Loop (derselbe Code wie im
Betrieb) mit einem synthetischen Sender und einer Sonde am Geräte-Ausgang; die
Sonde ist nötig, weil Rampe und Puls erst in `G29ForceFeedback.apply()`
entstehen. Damit sind genau die Mängel 1, 3, 4 und 5 Dauertests: sie können
nicht wieder eingebaut werden, ohne dass `--check` rot wird.

## 5. Offen für Welle 2

1. ~~Mangel 8 entscheiden und umsetzen (Stoss auf **einem** Weg), danach die
   WARN-Zeile in `--check` entfernen und die Puls-Zahlen im Plan nachziehen.~~
   → **erledigt** (Root): Stoss nur noch auf `pulse`, WARN-Zeile entfernt,
   Plan §3.3/§7 nachgezogen.
2. ~~Mangel 9: Plan §3.4 und die Tabelle in §7 auf die gemessenen Zahlen
   bringen.~~ → **erledigt** (Root).
3. ~~`tests/test_ffb_link.gd` prüft die Grundkraft nur mit `max_force > 0.02`
   (gemessen 0,163 in diesem Kurzlauf).~~ → **erledigt** (Welle 2): der Test
   fährt jetzt 14 s (1260 Ticks) bis in den ersten schnellen Bogen und
   verlangt dort **≥ 0,30** Grundkraft, ≥ 80 % Ticks gegen den Lenkbefehl,
   einen Puls ≥ 0,30 und Rütteln > 0,03 — die alten Schwellen (0,02, `>= 0,0`)
   hätten auch einen toten Kanal durchgehen lassen.
4. **Hardware bleibt offen:** das G29 meldet sich am PC, liefert aber keine
   HID-Reports (`tools/hid_probe.py 046d:c24f`: `report timeout … (no data)`) —
   ohne Netzteil gibt es weder Achsendaten noch Kraft. Belegt ist damit alles
   bis zum DirectInput-Aufruf, nicht die Kraft am eigenen Lenkrad. Sobald das
   Netzteil steckt: `"Apex Circuit FFB starten.cmd" --demo`, dann `--sign-check`.

## 6. Was ich selbst geändert habe

* `godot_f1/scripts/ffb_link.gd`: `gain` im Paket auf 1.0 (die Stärke steckt in
  `torque`), Sendetakt-Fix (Akkumulator-Rest), Port über `APEX_FFB_PORT`.
* `godot_f1/tests/test_ffb_link.gd`: harter Fehlschlag statt SKIP, eigener Port,
  gerechnete Senderate mit Grenzen 55–65 Hz, Prüfung „Paket = Modellkraft“,
  Prüfung „`gain` verstärkt nicht ein zweites Mal“.
* `tools/g29_ffb.py`: `gain` nur noch als Meldung, Puls-Abklingen vor der
  Anwendung, klare Meldung bei belegtem Port, `SO_EXCLUSIVEADDRUSE`, Quellen/
  Clip/Damage aus dem Paket ausgewertet, neues `--check` samt Geräte-Sonde,
  v2-Protokoll im Modulkopf dokumentiert.
* `tools/ffb_send_test.py`: dokumentiert, dass dieser Sender bewusst v1 spricht.
