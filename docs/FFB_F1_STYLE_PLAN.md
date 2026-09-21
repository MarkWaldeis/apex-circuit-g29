# Apex Circuit — Lenkrad-Feedback wie im offiziellen Formel-1-Spiel

Auftrag: herausfinden, wie sich das offizielle F1-Spiel (Codemasters/EA,
F1 24 / F1 25) am Lenkrad anfühlt — **wie schwer das Lenkrad zu drehen ist,
wann es rückelt, wann es leicht wird** — daraus einen Plan machen und diesen
Plan im eigenen Spiel umsetzen.

Dieses Dokument ist zuerst die Recherche, dann der verbindliche Plan.
Der Stand der Umsetzung steht am Ende in „Umsetzung“ und in
`docs/reviews/ffb_f1_style.md`.

---

## 1. Recherche: was das offizielle Spiel am Lenkrad macht

Alle Quellen unten wurden am **21.09.2026** abgerufen und im Volltext gelesen;
die zitierten Sätze und Zahlen sind wörtlich aus diesen Seiten übernommen
(geprüft mit einem Abruf der jeweiligen Seite, nicht aus dem Gedächtnis).

### 1.1 Die Regler des Spiels

F1 24 und F1 25 haben unter *Settings → Controls, Vibration & Force Feedback*
genau diese Regler:

| Regler | Bedeutung laut Spiel/Guides |
|---|---|
| Vibration & Force Feedback Strength | Hauptverstärkung — wie schwer das Lenkrad insgesamt geht („master gain“) |
| On Track Effects | Rütteln von der Fahrbahnoberfläche (Bodenwellen, Fugen) |
| Rumble Strip Effects | Rütteln auf dem Kerb |
| Off Track Effects | Rütteln auf Gras/Kies |
| Pit Stop Effects | Rütteln in der Box |
| Wheel Damper | Grundgewicht/Dämpfung des Lenkrads; zu hoch = Lenkrad wird schwergängig und taub |
| Maximum Wheel Rotation | Lenkbereich des virtuellen Fahrzeugs (360°, 400°, 450° …) |

Quellen und was sie belegen:

* **Traxion.gg, „F1 24 wheel force feedback settings and tips“**
  <https://traxion.gg/f1-24-force-feedback-settings-and-tips/>
  Die Standardwerte sind auf 100 — „borderline undrivable“, das Lenkrad
  „itching to oscillate out of my control“ bei hohem Tempo. Der Autor dreht
  *Wheel Damper* von 100 auf **5 %**, damit schnelle Richtungswechsel
  (Slide abfangen, Haarnadel) möglich sind, und stellt die
  *Maximum Wheel Rotation* auf **450°**.
* **Brian Koponen, „Best F1 24 Settings for Logitech G29 / G920“**
  <https://www.briankoponen.com/f1-24-logitech-g29-g920-settings/>
  G HUB: **Operating Range 900°**, Sensitivity 50, **Centering Spring Off**.
  Im Spiel: FFB-Stärke 43, On Track 60, Rumble Strip 60, Off Track 55,
  Pit Stop 50, **Wheel Damper 1**, **Maximum Wheel Rotation 360°**.
  Wörtlich: „The default force feedback for the Logitech G29 and G920 is too
  strong, making the wheel too heavy and dull.“ Und: „F1 24 will set the
  correct steering angle in the game itself and has a **proper soft lock**,
  so leave the wheel rotation at 900°.“
* **racinggames.gg, „Best F1 24 Wheel Settings“**
  <https://racinggames.gg/article/best-f1-24-wheel-settings>
  „Vibration and Force Feedback should be set **no higher than 70**. No matter
  how strong you think you are, you'll find out the hard way the first time the
  wheel snaps in-game.“ Gesetzt haben sie **60**, On Track 15, Rumble Strip 10,
  Off Track 10, Wheel Damper 10, **Rotation 360°**.
* **TheGamer, F1 25 Wheel Setup Guide**
  <https://www.thegamer.com/f1-25-wheel-settings-guide/>
  Rotation **360°**, FFB-Stärke unter 70 %, Drift/Auto-Centering runter —
  sonst „snap-back“ auf den Geraden.
* **SIMGASM, F1 25/26 Force-Feedback-Guide**
  <https://simgasm.com/blogs/articles/f1-26-dlc-best-force-feedback-settings>
  Grundregel: **Wheelbase auf 100 %** („This always needs to be at 100 %.
  Setting this lower than 100 % will create clipping“), in-game runter
  („Reduce in-game Force Feedback Strength to 55–65 first and see whether
  detail returns“). Auf die Frage „Why does my wheel oscillate on the
  straights in F1 25?“ antwortet die Seite: „**Wheel Damper is too low.**
  Increase it in increments of 5 until the oscillation stops.“ Und:
  **Understeer Enhance ausschalten** — „It adds artificial weight that masks
  real car behaviour“.

### 1.2 Was physikalisch dahinter steckt

Quelle: **Sim Racing Manual, „Force feedback explained: reading the wheel“**
<https://simracingmanual.com/ffb/explained/> und „Clipping“
<https://simracingmanual.com/ffb/clipping/>

* Force Feedback ist **Vorderachse**: die Kraft, die die Vorderräder über die
  Lenkung zurückgeben.
* Das eine große Signal ist der **Nachlauf / Self-Aligning Torque (SAT)**:
  Die Seitenkraft des Reifens greift hinter der Lenkachse an und will das
  Rad gerade stellen. Je mehr Last und je mehr Schräglauf, desto stärker.
  „With caster and high-grip tires, the self-aligning force while cornering
  can exceed the torque you feel turning the wheel at a standstill.“
* **Untersteuern:** Rutscht die Vorderachse über den Peak-Slip hinaus,
  bricht der Nachlauf ein — **das Lenkrad wird leicht und taub**, obwohl man
  weiter einschlägt. „That lightness is the front telling you it has nothing
  left.“
* **Übersteuern:** Das Auto dreht, die Vorderräder zeigen in den Slide —
  der Nachlauf wird erst klein und **kehrt sich dann um**: das Lenkrad zieht
  von selbst in den Slide, genau die Gegenlenkbewegung, die man sowieso
  machen würde.
* **Abtrieb/Luft:** Mit dem Tempo wird das Lenkrad immer schwerer
  (Frontflügel drückt), über einer Kuppe wird es kurz leicht.
* **Blockierende Vorderräder:** Ein stehender Reifen erzeugt keinen Nachlauf
  mehr → **das Lenkrad wird leicht/tot**, statt hart zu ziehen.
* **Kerb:** „a sharp, fast oscillation“ — eine schnelle, harte Schwingung.
* **Clipping:** Wenn die angeforderte Kraft über dem liegt, was die Basis
  hergibt, wird oben alles abgeschnitten: „heavy but dead“ — stark, aber
  ohne Information. Die Rettung ist ein Signal, das im normalen Fahren
  **nicht** am Anschlag hängt; nur große Kerbs dürfen kurz anschlagen.

### 1.3 Was ein G29 davon überhaupt kann (und was nicht)

* Ein Logitech G29/G923 ist ein Zahnradantrieb mit **etwa 2–3 Nm**;
  ein Thrustmaster T300 liegt bei ~3,9 Nm (simracingmanual). Das reicht,
  um Last und Kerbs zu zeigen, aber „a Thrustmaster T300 at ~3.9Nm or a
  Logitech G923 at ~2-3Nm smears“ das feine Untersteuern.
* Ein echtes Rennlenkrad arbeitet in einer anderen Liga: Fanatec nennt für
  GT3 6–8 Nm (Fahrer bis 12 Nm), LMP2 ~11 Nm, Spitzen bis 15+ Nm
  (<https://fanatec.com/us/en/explorer/products/racing-wheels-wheel-bases/how-realistic-is-fanatec-torque-compared-to-a-real-car/>).
  Ein Formel-1-Auto liegt noch darüber.
* **Konsequenz für uns:** Die absolute Newtonmeter-Zahl lässt sich am G29
  nicht echt abbilden. Echt abbilden lassen sich die **Verhältnisse**:
  0 % am Geradeauslauf, mittlere Last im schnellen Bogen, Einbruch bei
  Untersteuern, Umkehr beim Übersteuern, Spitze auf dem Kerb und beim
  Einschlag — und ein Signal, das nie dauerhaft am Anschlag klebt.
  Genau das ist der Unterschied zwischen „stark“ und „echt“.
* G29-Randbedingungen, die der Plan respektiert: 900° Betriebsbereich in
  G HUB, **Zentrierfeder aus**, Dämpfung aus dem Treiber so niedrig wie
  möglich (Filter lügen, siehe simracingmanual), FFB wird von einem
  DirectInput-Helfer erzeugt, weil Godot kein FF-API hat.

---

## 2. Soll-Zustand: was unser Lenkrad wann tun soll

Gemessen am offiziellen Spiel, übertragen auf die Physik, die wir haben
(`tyre_model.gd` liefert `slip_front`, `slip_rear`, `front_grip`,
`rear_grip`, `understeer`, `oversteer`, `downforce`; `surfaces.gd` liefert
Kerb/Kies/Gras; `crash.gd` liefert Einschläge; `gearbox.gd` die Schaltvorgänge).

| Fahrsituation | Lenkrad soll | Kanal |
|---|---|---|
| Geradeaus, Schrittgeschwindigkeit | leicht, aber mit echter Reibung; keine erfundene Zentrierung | `torque` ~0, `friction` klein |
| Geradeaus, 250–320 km/h | spürbares Grundgewicht („es liegt“), ruhig, kein Zappeln | `torque` klein, `damper` am höchsten |
| Schneller Bogen, 3–4 g | **schwer**: 55–75 % der Lenkradkraft (nach der eingestellten Stärke), steigt mit Tempo und Abtrieb | `torque` groß, Vorzeichen gegen den Lenkwinkel |
| Enger Bogen, Vorderachse am Limit | **bricht ein** (30–60 % leichter als der Bogen davor), obwohl mehr Lenkung drin ist | `torque` × (1 − Untersteuern) |
| Vorderrad blockiert beim Bremsen | **leicht/tot** + feines Rattern | `torque` → 0, `rumble` ~25–30 Hz |
| Heck bricht aus | Lenkrad wird erst **leicht**, und wenn der Schlupfwinkel der Vorderräder durch die Null dreht, **zieht es in die Gegenlenkrichtung** — man fängt es mit dem Lenkrad, nicht gegen es | `torque` Einbruch, dann Vorzeichen-Umkehr |
| Auf dem Kerb | hartes, schnelles Rütteln, mit Tempo stärker und höher frequent | `rumble` 0,6–0,9, 18–45 Hz |
| Gras/Kies | grobes Mahlen, deutlich langsamer und dumpfer als Kerb | `rumble` 0,3–0,5, 9–14 Hz |
| Asphalt bei Tempo | feine Textur, leise | `rumble` 0,05–0,12, 25–40 Hz |
| Über eine Bodenwelle/Kuppe | Kuppe: kurzes **Leichtwerden**; Bodenwelle: kurzer, dumpfer Stoß | `torque` runter (`vertical_g` < 0,80), `rumble` 14–26 Hz „Bodenwelle“, `pulse` klein |
| Schalten | kurzer, harter Anschlag („die Schaltstange“) | `pulse` 0,3–0,5 |
| Wand-/Autokontakt | harter Schlag, proportional zur Härte | `pulse` bis 1,0 |
| Schaden (Platter nach dem Blockieren, verbogenes Rad nach dem Einschlag) | das Lenkrad **rüttelt weiter**, statt nur einmal zu stoßen; mit dem Tempo wird die Unwucht schneller (Frequenz = Radumdrehung) | `rumble` 0,2–0,6, 11–30 Hz, Quelle „Unwucht“ |
| Am Lenkanschlag (Soft Lock) | die Wand ist zu spüren: Kraft steigt steil an, hält, lässt nicht weiter drehen | `torque` steigt mit `lock_pressure` |
| Stillstand, Motor aus/im Menü | Kraft fällt auf null (kein „festgenageltes“ Lenkrad) | Fail-sicher im Helfer |

Zusätzlich zwei Spielregeln aus der Recherche, die hart eingehalten werden:

1. **Kein Clipping im Normalbetrieb.** Die Grundlast liegt bei 0,55–0,75 und
   läuft über eine **weiche Begrenzung** (`SOFT_KNEE` 0,72, `SOFT_CEIL` 0,90):
   darunter unverändert, darüber gestaucht — am Knick knickfrei (`SOFT_K`),
   die Spitze kommt also ohne Ruck und ohne flache 1,0.
   Gefunden von der Gegenprobe des Roots — ohne sie klebten 12 von 375
   Gitterpunkten (4,5 g bei 90 m/s mit viel Abtrieb) an der 1,0, also genau
   das „heavy but dead“ aus dem Sim-Racing-Manual. Nur Kerbs, Einschläge und
   der Soft Lock dürfen die 1,0 berühren.
2. **Keine aufgeschmierten Zusatzkräfte.** Untersteuern wird nicht
   „verstärkt“ (F1-25-Guide: *Understeer Enhance* aus), sondern entsteht
   aus dem echten Nachlauf-Einbruch. Es gibt genau eine Grundkraft, alles
   andere sind Frequenzbänder.

---

## 3. Umsetzungsplan

### 3.1 Architektur

```
car_controller.gd  ──Physik-Telemetrie──▶  ffb_model.gd   (rechnet die Kanäle)
                                              │
              ┌───────────────────────────────┴────────────────┐
              ▼                                                ▼
     ffb_link.gd (UDP v2, 60 Hz)                    wheel_feedback.gd
              │                                     (HUD, Cockpit-Kamera,
              ▼                                      Gamepad-Vibration)
   tools/g29_ffb.py (DirectInput, 200 Hz)
              │
              ▼
        Logitech G29
```

Ein Rechenmodell (`ffb_model.gd`) ist die **einzige** Quelle der Wahrheit.
Alles, was reagiert, liest dieselben Zahlen — das verhindert, dass HUD und
Lenkrad unterschiedliche Dinge erzählen.

### 3.2 Dateien

| Datei | Was passiert |
|---|---|
| `godot_f1/scripts/ffb_settings.gd` | **neu**: Einstellungen (an/aus, Stärke, Dämpfung, Effekte, Lenkbereich), laden/speichern in `user://ffb_settings.json` |
| `godot_f1/scripts/ffb_model.gd` | **neu**: die Physik→Kraft-Rechnung aus Abschnitt 2 (reine Funktionen, unit-testbar) |
| `godot_f1/scripts/ffb_link.gd` | Transport auf Protokoll v2 umgestellt (Torque + Frequenz + Gain) |
| `godot_f1/scripts/wheel_feedback.gd` | liest dasselbe Modell (nicht mehr seine eigene Abschätzung) |
| `godot_f1/scripts/car_controller.gd` | Telemetrie vollständig füllen, Modell aufrufen, Soft-Lock-Druck weitergeben |
| `godot_f1/scripts/g29_input.gd` | Lenkbereich/Soft Lock: `steer` bleibt die kalibrierte −1…1-Größe, dazu `steer_lock` (0…1 jenseits des Anschlags) |
| `godot_f1/scripts/menu.gd` | Einstellungen-Seite „Force Feedback“ mit Live-Anzeige |
| `godot_f1/scripts/hud.gd` | Kraftbalken + „am Anschlag“-Warnung (das, was im F1-Spiel das Force-Meter ist) |
| `godot_f1/scripts/main.gd` | Einstellungen an G29 und Auto durchreichen |
| `tools/g29_ffb.py` | v2 lesen, Rampen/Glättung, Rüttelfrequenz, `--demo` (Fühltest am echten Lenkrad) |
| `godot_f1/tests/test_ffb_model.gd` | **neu**: jedes Verhalten aus Abschnitt 2 als Messung |
| `godot_f1/tests/test_ffb_link.gd` | auf v2 erweitert (Schlüssel, Raten, Wertebereiche) |
| `godot_f1/tests/test_ffb_settings.gd` | **neu**: Menü ↔ Einstellungen ↔ Modell |
| `godot_f1/tests/probe_ffb.gd` | **neu**: Messprotokoll (Tabelle) für den Beweis |

### 3.3 Protokoll v2 (Spiel → Helfer)

```json
{"v":2,"torque":-0.42,"damper":0.29,"friction":0.14,"rumble":0.55,
 "rumble_hz":31.0,"pulse":0.0,"spring":0.0,"gain":0.7,
 "event":"kerb","speed":48.3,"source":"Kerb","clip":0.0}
```

`force`/`damp`/`fric` bleiben als Aliasse lesbar, damit ein alter Sender
den Helfer nicht lahmlegt. Der Helfer darf **nie** blockieren, nie crashen
und fällt nach 0,5 s ohne Paket auf „Kraft loslassen“ zurück.

Zwei Regeln, die zur Kette gehören und geprüft werden:

1. `torque` ist die **Grundkraft ohne Stoss** und enthält die Menü-Stärke
   bereits (genau einmal angewendet, in `ffb_model.gd`).
2. Ein Ereignis (Schalten, Einschlag) fährt **nur** auf `pulse`/`pulse_dir`.
   Der Helfer setzt es sofort ohne Rampe auf die Kraft. Steckte es zusätzlich
   in `torque`, käme es doppelt an — gemessen waren das 111 % eines
   Schaltstoßes, beim vollen Einschlag über 1,0 und damit gekappt.

### 3.4 Der Helfer (`tools/g29_ffb.py`)

* **Radfamilie**: gesucht wird nach **G29, G920 oder G923** — dieselbe
  DirectInput-Arbeit, ein anderer Produktname. Ein fest auf „G29“ gestellter
  Filter hat ein angeschlossenes G920/G923 nicht gefunden
  (`kein Lenkrad gefunden, dessen Name 'G29' enthaelt`); die Pruefung
  `die_ganze_lenkradfamilie_wird_gefunden` in `--check` haelt das jetzt fest.
  `--name NAME` (auch `--name a,b`) sucht ein anderes Rad,
* liest v2-Felder **ohne eigene Verstärkung**: die Stärke aus dem Menü steckt
  schon im gesendeten `torque` (`ffb_model.gd` skaliert an genau einer
  Stelle, dort wo auch die HUD-Anzeige entsteht). Das Feld `gain` im Paket
  ist die Zusatzverstärkung des Helfers und bleibt deshalb neutral (1.0) —
  früher multiplizierte der Helfer die Menü-Stärke ein zweites Mal, die
  Stufen wirkten dann quadratisch (30 % kamen als 9 % an). `--gain` bleibt
  als manueller Trimm für `--demo`/`--selftest`,
* **Rampe statt Sprung**: die Kraft wird pro Sample begrenzt verändert
  (`TORQUE_RISE` 40/s → **25 ms** auf vollen Ausschlag, `TORQUE_FALL` 8/s →
  **125 ms** beim Loslassen, bei 200 Hz also 0,2 pro Sample; geprüft mit
  `python tools/g29_ffb.py --check`), damit der Zahnradantrieb nicht wie eine
  Treppe wirkt. Nur ein **Stoß** (`pulse`) umgeht die Rampe und sitzt sofort
  auf der Kraft,
* **Frequenz**: das periodische Rütteln bekommt die Frequenz aus
  `rumble_hz` (statt konstant),
* Effekte: Konstante Kraft, Dämpfer, Reibung, periodisches Rütteln,
  Zentrierfeder (nur noch als Rest, Standard 0),
* `--demo`: spielt eine feste Abfolge ab (Gerade → Bogen → Untersteuern →
  Kerb → Blockieren → Schalten → Einschlag → loslassen) und schreibt zu
  jedem Schritt auf die Konsole, was gerade anliegt. Damit lässt sich der
  Plan **am echten Lenkrad abfahren**, ohne das Spiel zu starten.
* `--idle-release`, `--invert`, `--shared`, `--rate`, `--gain` wie gehabt.

### 3.5 Der Soft Lock (Lenkbereich)

F1 24/25 fahren 360–400°, das G29 bleibt in G HUB auf 900° und das Spiel
macht den Anschlag selbst (Brian Koponen: „has a proper soft lock“).
Genauso machen wir es:

* G HUB: Betriebsbereich **900°**, Zentrierfeder aus (steht in `README`).
* Im Spiel einstellbar: **360 / 400 / 450 / 900°**.
* Rechnung: `steer_soft = clamp(steer / (rotation_deg / wheel_range_deg))`
  mit `wheel_range_deg = 900`. Bei 400° ist also nach ±22 % des
  Lenkradwegs voller Einschlag — deutlich F1-artiger als der heutige
  1:1-Weg.
* Jenseits des Anschlags: `steer_lock` (0…1) wächst und das Modell legt
  eine steigende Gegenkraft drauf — man **spürt** die Wand.

### 3.6 Einstellungen im Spiel

Auf der Einstellungen-Seite, Abschnitt „Force Feedback (G29)“:

* **FFB: AN / AUS**
* **Stärke**: 30 / 45 / 60 / 75 / 90 / 100 % (Standard 75)
* **Dämpfung**: NIEDRIG / MITTEL / HOCH (Standard MITTEL — F1-Standard
  wäre 100 und damit „dull“, Traxion und Brian Koponen drehen sie auf 1–5 %;
  MITTEL ist der Kompromiss gegen Zappeln)
* **Rüttel-Effekte**: AN / AUS als Hauptschalter
* **On Track Effects** (Asphalt-Textur), **Rumble Strip Effects** (Kerb) und
  **Off Track Effects** (Kies/Gras): je 0…100 % in 10-%-Schritten, Standard
  100 %. Das sind **genau die drei Regler des offiziellen Spiels**
  (§1.1: On Track / Rumble Strip / Off Track Effects) — und sie wirken
  getrennt: wer den Kerb leiser stellt, behält das Kies-Mahlen. Ein einzelner
  An/Aus-Schalter könnte das nicht (die Guides setzen die drei Regler
  unterschiedlich: 60/60/55 bzw. 15/10/10).
* **Lenkbereich**: 360° / 400° / 450° / 900°
* Live-Zeile: **Kraft 0–100 %** und „**am Anschlag**“, wenn das Signal
  länger als 0,15 s über 0,97 liegt.

---

## 4. Abnahmekriterien (alle messbar)

| Nr. | Kriterium | Messung |
|---|---|---|
| 1 | Grundlast wächst mit Tempo und Querlast | `probe_ffb`: Kraft bei gleichem Lenkwinkel 60 vs. 250 km/h |
| 2 | Untersteuern macht das Lenkrad messbar leicht | Kraft bei `understeer` 0,1 vs. 0,8 — mindestens 30 % weniger |
| 3 | Übersteuern: erst leicht, dann Vorzeichen-Umkehr | gemessen im Slide-Szenario (`probe_ffb`): Übersteuern 0,80, Kraft in Gegenlenkrichtung 175/181 Ticks = 97 % |
| 4 | Blockierende Vorderräder | Kraft fällt unter 20 % der Bogenkraft, Rütteln 20–35 Hz |
| 5 | Kerb | `rumble` ≥ 0,5 bei 120 km/h, 0 auf Asphalt; Frequenz steigt mit Tempo |
| 6 | Gras/Kies | eigener Frequenzbereich, Amplitude zwischen Asphalt und Kerb |
| 7 | Schalten | genau ein Puls je Schaltvorgang, 0,25–0,6 |
| 8 | Einschlag | Puls skaliert mit der Härte, Härte 1,0 bleibt ≤ 1,0 |
| 9 | Soft Lock | Kraft steigt monoton mit `steer_lock`, Steuerbefehl wird nicht größer |
| 10 | Kein Clipping im Normalbetrieb | Anteil der Ticks über 0,97 in einer Runde < 5 % |
| 11 | Keine Sprünge | Änderung der Grundkraft pro Tick < 0,15 im Modell |
| 12 | Kette | `test_ffb_link`: v2-Pakete, 60 Hz, Wertebereiche, 0 kaputte Pakete |
| 13 | Bestand | alle bisherigen Tests bleiben grün (Orientierung, Eingabe, Runde, Cockpit, Pedale, Getriebe, Crash, Ideallinie) |
| 14 | Hardware | `python tools/g29_ffb.py --selftest` meldet PASS; `--demo` ist am Rad fühlbar |
| 15 | Rückkanal | der Helfer antwortet dem Spiel (`{"ack":1}`); `test_ffb_link` prüft, dass das Spiel das Lebenszeichen liest und `helper_alive()` wahr wird; `--check` prüft die Antwort |
| 16 | Tests hängen nicht am Fahrer-Profil | `test_ffb_link` nagelt die FFB-Einstellungen selbst fest (an, Bänder 100 %, Stärke 0,75); ein Headless-Lauf darf `user://ffb_settings.json` nicht schreiben (`test_ffb_settings`) |
| 17 | Kein stilles Lenkrad | das HUD nennt den Grund: „LENKRADKRAFT AUS“ (Schalter), „LENKRADKANAL AUS“ (Kanal), „KEIN HELFER“ (keine Antwort) — statt einfach 0 % |

## 5. Prüfwellen (fremde Agenten, kritisch)

Nach der Umsetzung prüfen **fremde** Agenten in drei Rollen, jeder mit
eigenen Messungen und ohne die Tests des Autors nachzubeten:

1. **Modell/Realismus**: Stimmt die Kurve gegen die F1-Referenz (Last,
   Einbruch, Umkehr, Kerb, Blockieren)? Gegenproben: versuchen, die
   Behauptungen zu widerlegen.
2. **Kette/Hardware**: v2-Protokoll, Brücke, DirectInput, Rampen,
   Frequenzen, echtes G29 (`--demo`, `--selftest`), Verhalten ohne Helfer.
3. **Integration/Regression**: Menü, HUD, Soft Lock, alle Bestandstests,
   Bildrate, Spiel ohne Lenkrad, Spiel ohne Helfer.

Jeder Mangel wird mit Datei, Zeile und Messwert gemeldet. Danach bessert
der Root nach und startet die nächste Welle — so lange, bis eine Welle
**nichts** mehr findet. Erst dann gilt der Auftrag als erledigt.

**Stand der Wellen**

| Welle | Rolle | Bericht | Ergebnis |
|---|---|---|---|
| 1 | Modell/Realismus | `docs/reviews/ffb_f1_style.md` §5 | 4 Mängel gefunden (Clipping in der schnellsten Kurve, `damage` ungenutzt, blockierende Räder zu lasch, Rüttelbänder ungeprüft) — alle behoben |
| 1 | Kette/Hardware | `docs/reviews/ffb_chain_review.md` | 9 Mängel gefunden (u. a. Stärke doppelt angewendet, 45 statt 60 Hz, Stoss über zwei Wege) — alle behoben |
| 2 | Kette | `docs/reviews/ffb_wave2_chain.md` | 7 Mängel gefunden: **der Kettentest konnte die Kraft nicht verlieren** (Schwelle 0,02 gegen 0,163, Wagen fuhr geradeaus), zwei weitere Prüfungen konnten nie fehlschlagen, `event`/`speed` im Helfer ungelesen, Doku wich vom Code ab — alle behoben |
| 3 | Integration/Auslieferung (Root-Audit) | `docs/reviews/ffb_wave3_integration.md` | 3 Mängel gefunden: **G920/G923 wurden abgewiesen** (Filter fest auf „G29“), **ein Prüflauf hatte die echten Einstellungen des Fahrers auf „FFB AUS“ gestellt** (die nächste Messung fand keine Kraft und meldete die Kette als kaputt), und **die Auslieferung war nicht belegt**. Alle drei behoben — siehe §7 „Welle 3“ |
| 3 | Modell/Realismus, Kette/Hardware | — (kein Bericht) | Die beiden Welle-3-Agenten liefen bis zum Abbruch, ohne einen Bericht zu schreiben. Was sie an Zwischenständen hinterlassen haben (Headless-Schutz, zwei zusätzliche Ende-zu-Ende-Prüfungen), ist in den Dateien und in §8 dokumentiert. **Ersetzt durch Welle 4** — die Prüfung ist damit nicht „bestanden“, sondern wiederholt |
| 4 | Modell/Realismus (Agent `wave4_realism`) | — (kein eigener Bericht) | Der Agent brach ab; sein erhaltener Beitrag ist die **NAN-/INF-Härtung** in `ffb_model.gd` samt Randfall-Test `tests/test_ffb_edge.gd` (6 Prüfungen) — vom Root übernommen und nachgemessen |
| 4 | Kette/Hardware **am echten G29** (Root-Audit) | `docs/reviews/ffb_wave4_hardware.md` | Erstmals lag echte Hardware vor: **Motor dreht das Rad** (dreimal gemessen: +0,5 Kraft → Achse 32767→26), aber **nur zeitweise** (später dieselbe Messung ohne Bewegung). Zwei Mängel in den Diagnosewerkzeugen gefunden und behoben: der Richtungstest **startete den Helfer nie** (Pfad mit Leerzeichen) und **schrieb das Lenkrad-Profil des Fahrers neu**. Dazu drei neue Werkzeuge (`tools/ffb_hw_probe.py`, `tests/probe_axis_read.gd`, `tests/test_g29_profile_path.gd`) |
| 5 | Kette/Hardware (Agent `w5_direction`) | `docs/reviews/ffb_direction_selfcheck.md` | Die Kraftrichtung wird jetzt **gemessen statt angenommen**: der Helfer schickt seine DirectInput-Achse im Lebenszeichen mit, `ffb_link.gd` vergleicht sie mit der SDL-Achse des Spiels. 19 Prüfungen, `--check` 14/14. Details in §9 |
| 5 | Messkette/Auslieferung (Root-Audit) | §10 dieses Dokuments | Drei Mängel, alle behoben: ein **Kollisionslauf zählte als grün** (`LAP_DRIVE PASS` aus einer Welt ohne Auto), ein **hängender Godot blieb als Waise stehen** und vergiftete jede weitere Messung, und die **ausgelieferte Kopie konnte still veralten** (Desktop-Start 18:58, Export 19:06). Neu: `tools/run_all_tests.ps1`, gehärteter `tools/run_godot.ps1`, `tools/export_and_deliver.ps1` |

## 6. Risiken

* **G29 ohne Netzteil** kann keine Kraft erzeugen — dann ist die Kette
  korrekt und trotzdem fühlt man nichts. `--selftest` sagt das ausdrücklich.
* **Treiber-Dämpfung** in G HUB zerstört die feinen Signale. Steht in der
  Anleitung, ist nicht vom Spiel aus änderbar.
* **Zwei Programme am Lenkrad**: Der Helfer übernimmt das G29 exklusiv;
  Godot liest weiter (das ist gemessen, siehe `tools/ffb_live_check.ps1`).
* **Zu starkes Modell** = Clipping = taubes Lenkrad. Deshalb Kriterium 10.

---

# 7. Umsetzung — was steht, was gemessen ist

Alles unten ist mit den Werkzeugen in `godot_f1/tests/` gemessen, nicht
behauptet. Die Zahlen stammen aus den Läufen, die im Prüfbericht
`docs/reviews/ffb_f1_style.md` aufgeführt sind.

**Gebaut**

* `ffb_model.gd` rechnet die Kanäle aus der Physik (Nachlauf aus Querlast,
  Abtrieb und Reifenschlupf; Einbruch bei Untersteuern und bremsendem
  Vorderrad; Rütteln für Kerb, Kies, Gras, Blockieren, durchdrehende Räder,
  Asphalt-Textur; Stöße für Schalten und Einschlag; Anschlagskraft).
* `ffb_settings.gd` hält die Einstellungen (`user://ffb_settings.json`):
  Stärke, Dämpfung, Rütteln an/aus, Lenkbereich, Kraftrichtung.
* `ffb_link.gd` sendet Protokoll **v2** mit 60 Hz; `wheel_feedback.gd`, HUD
  und Kamera lesen dasselbe Modell.
* `tools/g29_ffb.py` liest v2 (und v1), zieht die Kraft mit Rampe nach
  (`TORQUE_RISE`/`FALL`), stellt die Rüttelfrequenz (`dwPeriod`) und hat
  `--demo`, `--dry-run`, `--sign-check`.
* Soft Lock: 360/400/450/900° wählbar, der Anschlag wird im Spiel gebaut
  (`g29_input.gd`), inklusive Druckkraft.
* Menüseite „Force Feedback“ mit Live-Anzeige, HUD-Kraftanzeige mit
  „AM ANSCHLAG“-Warnung, `Apex Circuit FFB starten.cmd`.
* Die drei Rüttel-Regler des offiziellen Spiels (On Track / Rumble Strip /
  Off Track, je 0–100 % in 10-%-Schritten) sind im Menü und im Modell getrennt
  verdrahtet: `test_ffb_model.gd` prüft, dass ein Band auf 0 nur sein eigenes
  Rütteln abschaltet (`kerb_band_auf_null_laesst_das_kies_stehen`),
  `test_ffb_settings.gd` prüft Speichern/Laden und die Menü-Knöpfe.
* `tools/ffb_end_to_end.ps1`: das **echte Spiel** fährt gegen den **echten
  Helfer** (kein Test-Sender, kein Lenkrad nötig). Damit ist die Naht zwischen
  den beiden Hälften geprüft und nicht nur jede Hälfte für sich.

**Gemessen** (`tests/probe_ffb.gd`, echte Runde mit der KI plus Szenarien;
`tests/test_ffb_model.gd`, 34 Einzelprüfungen; `tests/test_ffb_settings.gd`,
32 Prüfungen (Menü, Speichern, Soft Lock, HUD-Hinweise); `tests/probe_review_root.gd`,
18 Gegenproben; `tests/test_ffb_link.gd`, 14 s echte Fahrt; `tools/review_chain_test.py`
und `tools/g29_ffb.py --check`, 12 Prüfungen, Kette ohne Godot):

| Größe | Wert |
|---|---|
| Kraft auf der Runde | Mittel 0,095 · Median 0,057 · p95 0,459 · Spitze 0,584 |
| Clipping auf der Runde | 0 von 1800 Ticks über 0,97 (0,0 %); die weiche Begrenzung deckelt bei 0,90 (`SOFT_CEIL`), damit die Spitze nie flach an der 1,0 klebt |
| Dämpfung | 0,087 unter 60 km/h (n=136) → 0,295 über 200 km/h (n=934) |
| Gerade bei Tempo (> 180 km/h, Querlast < 0,6 g) | Kraft Mittel 0,003 · Spitze 0,042 · Dämpfung 0,297 · Rütteln Mittel 0,143 · **Sprung pro Tick 0,0005** (kein Zappeln) |
| Schrittgeschwindigkeit (< 60 km/h) | Kraft Mittel 0,054 · Spitze 0,153 · Rütteln 0,05 (keine erfundene Zentrierung) |
| Kerb | Rütteln 0,62 bei 30 Hz |
| Kies | Rütteln 0,29 bei 12–30 Hz (langsamer und schwächer als Kerb) |
| Kuppe / Bodenwelle | senkrechte Last 0,16–2,05 g auf der Runde (Mittel 1,00); **37 Ticks unter 0,80 g** (Kuppe: Kraft bis 40 % leichter) und **20 Ticks über 1,35 g** (Bodenwelle: Stoß + Rütteln 14–26 Hz) |
| Blockierende Vorderräder | Kraft 0,143 statt 0,797 = **18 %** der Bogenkraft, Rütteln 0,70 bei 34 Hz |
| Bremsen ohne Blockieren | geradeaus 58 %, Trail-Braking 74 % der jeweiligen Kraft ohne Bremse (das Anbremsen macht das Lenkrad nicht tot) |
| Vollbremsung in der Kurve | Kraft 0,093 statt 0,584 im Bogen (16 %), Rütteln 0,70 bis 34 Hz |
| Ausbrechendes Heck | Übersteuern 0,80, Kraft in Gegenlenkrichtung 175/180 = 97 % |
| Kraft gegen den Lenkbefehl (ruhig) | 98 % der Ticks (956/974) |
| Größter Sprung zwischen zwei Ticks | 0,086 (Modell), Rampe im Helfer zusätzlich (0,2 pro Sample bei 200 Hz) |
| Kette Spiel → Helfer | **839 Pakete gesendet / 839 angekommen in 14,0 s = 59,9 Hz**, 0 kaputte, v2-Schlüssel vollständig, Wertebereiche eingehalten |
| Kette Spiel → **echter Helfer** (Ende zu Ende, `tools/ffb_end_to_end.ps1`) | **1829 Pakete**, Kraftspitze **0,584** im Bogen (= Modellwert 0,584, also verlustfrei), Rütteln **0,700 @ 42 Hz**, Quellen `Asphalt, Blockiert, Kerb, Kies`, Ereignis `shift`, 0 Werte über 1,0 — **10 Prüfungen, 0 Mängel** |
| Rückkanal (Helfer → Spiel) | der Helfer antwortet mit `{"v":2,"ack":1,"mode":"wheel"\|"dry"}`; `test_ffb_link` liest **140 Lebenszeichen** in 14 s und `helper_alive()` wird wahr; `--check` bekommt die Antwort nach 0,01 s (`--check`: 12 Prüfungen) |
| Kein stilles Lenkrad | HUD nennt den Grund statt „0 %“: „LENKRADKRAFT AUS“ (Schalter), „LENKRADKANAL AUS (APEX_FFB=0)“, „KEIN HELFER — Apex Circuit FFB starten.cmd“ (keine Antwort) — `test_ffb_settings` prüft alle drei Texte |
| Echte Spitzen statt Stichproben | `[ffb-peak]` je Lauf: Maximum aus **jedem** Sample des 200-Hz-Loops (Kraft, Rütteln, Hz, Tempo, Clipping, „über 1,0“) — der Ende-zu-Ende-Test las vorher 2-s-Stichproben und meldete denselben Lauf einmal mit 0,560, einmal mit 0,250 |
| Kraft im Bogen auf der Kette | Spitze **0,577** über 293 Ticks (`test_ffb_link`), **291/293 = 99 %** davon gegen den Lenkbefehl |
| Stoss auf der Kette | Puls **0,60** in 55 von 839 Paketen, Ereignis „shift" im Paket (`test_ffb_link`), `--check`: 0,40 + 0,40·0,70 = 0,680 am Rad |
| Herkunft auf der Kette | `["Asphalt", "Schalten", "Blockiert"]` in einem Lauf (`test_ffb_link`); das Paket nennt das Ereignis, und `source` sagt, woher die Kraft kommt (Schalten, Aufprall, Kontakt, Bodenwelle, Kerbschlag) |
| Ereignis und Tempo | `--dry-run`: `Ereignisse {'shift': 174} bei bis 180 km/h` (`--check` prüft beides) |
| Stärke wirkt genau einmal | Paket 0,797 mit `gain` 0,75 kommt als **0,797** am Rad an (`--check`, `review_chain_test.py`) |
| Schalter im Menü kommt am Lenkrad an | `tools/ffb_end_to_end.ps1` fährt **zweimal**: FFB AN → Kraft **0,584** (echte Spitze), Rütteln 0,700 @ 42 Hz, Quellen `Asphalt, Blockiert, Kerb, Kies`; FFB AUS → Kraft **0,000**, Rütteln **0,000** (10 Prüfungen, 0 Mängel) |
| Radfamilie | `--check`: `die_ganze_lenkradfamilie_wird_gefunden` — „Logitech G29/G920/G923“ treffen, ein Gamepad nicht; `--name G923` grenzt auf ein Rad ein (12 Prüfungen, 0 Mängel) |
| Ausgelieferter Build | `tools/ship_check.ps1` gegen `Apex Circuit.exe` (Desktop-Start): ~428 Pakete, im Stand Reibung 0,12–0,13 / Dämpfung 0,31, Quelle `Asphalt`; mit `APEX_FFB_SETTINGS` = FFB AUS: Reibung 0,000, Dämpfung 0,000, Quelle `aus` → **der Build enthält den neuen Stand** (3 Prüfungen, 0 Mängel). Ein Textvergleich im `.pck` beweist das **nicht**: dort sind nur die Dateipfade lesbar (`rg -a -c "scripts/ffb_model.gd"` findet 3 Treffer, `"AM ANSCHLAG"` oder `"LENKRADKRAFT AUS"` dagegen 0) — die GDScript-Literale liegen kompiliert und unlesbar im Pack. Der Beweis ist die Messung, nicht die Suche |

**Hardware, Stand Welle 4.** Am 21.09.2026 lag das G29 **zeitweise mit
Kraft** vor: `python tools/ffb_hw_probe.py --seconds 2.0 --force 0.5` fuhr die
Achse dreimal reproduzierbar `32767 → 26` (positive Kraft) und `→ 59525`
(negative Kraft) — der Motor arbeitet. Sechs Minuten später dieselbe Messung:
keine Bewegung (`delta=+0`, `+168`) und Godot bekam kaum Achsdaten
(`rest gas=1.00 brake=0.00 clutch=0.00` — eine Woche vorher genau andersherum).
Das Rad ist in diesem Zustand **unzuverlässig** (Netzteil? Kabel? Port?),
und genau deshalb ist der Fühltest weiterhin offen — plus die Kraftrichtung,
die nur mit zuverlässig meldendem Rad messbar ist. Alles dazu, mit Messwerten
und den zwei behobenen Werkzeug-Mängeln, steht in
`docs/reviews/ffb_wave4_hardware.md`. Sobald das Rad laufend Reports liefert
(`python tools/hid_probe.py 046d:c24f`):

```
python tools/hid_probe.py 046d:c24f        # laufende Reports = Rad ist bereit
tools\ffb_direction_check.ps1              # Kraftrichtung messen (5 s)
"Apex Circuit FFB starten.cmd" --demo      # Fühltest am Lenkrad
"Apex Circuit FFB starten.cmd"             # Helfer für das Spiel
```

### Die Kraftrichtung ist jetzt entschieden (Nachtrag zum Stand oben)

Die Messung oben liefert nicht nur „der Motor arbeitet“, sondern auch die
Richtung — und die war bis hierher offen:

* Positive DirectInput-Kraft fährt die G29-Achse zum **Minimum**
  (`33117 → 14`, dreimal reproduziert).
* Die Kalibrierung des Fahrers sagt: „rechts“ ist das **Maximum**
  (`steer_invert: false`, `steer_span: +0.5547` — beim Drehen nach rechts
  stieg die Achse).
* Also dreht eine positive Kraft dieses Rad **nach links**, während das Modell
  mit positivem `torque` „nach rechts drücken“ meint. Die Kraft wäre
  spiegelverkehrt angekommen: in der Kurve gegen den Fahrer statt mit ihm.

Folge, umgesetzt und geprüft:

* `ffb_settings.invert` steht auf **true** (gemessener Wert dieser Hardware).
* `invert` dreht **auch `pulse_dir`** mit — vorher hätte die Grundkraft in der
  Kurve gestimmt und der Einschlag in die falsche Richtung gedrückt
  (`test_ffb_settings.gd`: `kraftrichtung_dreht_auch_den_stoss`).
* Einstellungsdateien der **Version 1** werden beim Laden migriert: ihr
  `invert` war nur der alte Standard, nicht die Wahl des Fahrers
  (`alte_datei_bekommt_die_gemessene_kraftrichtung`). Ab Version 2 gilt die
  Datei (`neue_datei_darf_das_vorzeichen_selbst_bestimmen`).
* `tests/probe_ffb_steer.gd` meldet ohne Achsendaten jetzt **„UNBEKANNT“**
  statt „dreht nach links“ — ein Fehlalarm, der wie eine Messung aussah.

Der Menüschalter und `tools/ffb_direction_check.ps1` bleiben: nach einem
Treiberwechsel oder an einem anderen Rad kann die Richtung anders sein.

**Nachgemessen an der ganzen Kette** (echtes Spiel, echter Helfer, zwei
Einstellungsdateien, je 36 s; Port privat, damit nichts dazwischenfunkt):

```text
invert = true  (neuer Standard): torque  -0.233 .. +0.584
invert = false (alter Stand)  : torque  -0.584 .. +0.233
```

Spiegelbildlich bis auf die Stelle — die Umdrehung wirkt also wirklich vom
Modell über das Paket bis zum Helfer, und die Spitze im Bogen (0,584) bleibt
in der Größe erhalten.

---

## 9. Welle 4: was der Root am echten Lenkrad gefunden und geändert hat

Vollständiger Bericht: `docs/reviews/ffb_wave4_hardware.md`.

### 9.1 Mangel: Der Richtungstest startete den Helfer nie (behoben)

`tools/ffb_direction_check.ps1` übergab die Helfer-Argumente als **Array** an
`Start-Process`; der Projektpfad enthält ein Leerzeichen, also startete Python
mit `C:\Users\Mark` als Skript (`ffb_bridge.err`: `File "C:\Users\Mark", line
8 … SyntaxError`). Es wurde **nie eine Kraft gesendet**, und der Test meldete
„das Lenkrad bewegt sich nicht“ — ein Fehlalarm, der wie ein Hardware-Fehler
aussieht. Behoben mit einem selbst gequoteten Argument-String (dieselbe
Falle war in `tools/ffb_live_check.ps1` schon einmal behoben worden).

### 9.2 Mangel: Ein Prüflauf schrieb das Lenkrad-Profil des Fahrers neu (behoben)

`tests/probe_ffb_steer.gd` kann nicht headless laufen (headless zählt Godot
keine Joysticks auf), also griff der Headless-Schutz in `save_profile()` dort
nicht. Beleg aus `logs/godot2026-09-21T18.12.20.log` mitten im Richtungstest:
`G29 profile saved: { … "throttle_rest": 0.0, "throttle_press": -1.88 … }`
— das von Hand kalibrierte Pedalprofil des Fahrers wurde überschrieben.
Behoben in vier Schichten: `APEX_G29_PROFILE` verlegt den Profilpfad
(`g29_input.gd`, in `_init()` **und** `_ready()`), die beiden Fenster-Probes
setzen die Variable selbst, das Richtungstest-Skript zusätzlich von außen,
und `tests/test_g29_profile_path.gd` (6 Prüfungen) hält fest, dass das echte
Profil inhaltlich und im Zeitstempel unberührt bleibt.

### 9.3 Mangel: Ein abgebrochener Prüflauf ließ den Helfer stehen (behoben)

`$ErrorActionPreference = 'Stop'` brach das Skript vor dem Aufräumen ab, das
Lenkrad blieb exklusiv belegt. Behoben: Aufräumen in `finally`, Zeitlimit für
den Prüflauf, eigenes Protokoll `tools/ffb_direction_probe.log`.

### 9.4 Mangel: Ein NAN-Tick vergiftete die Kraft dauerhaft (behoben, vom Agenten)

Der Welle-4-Agent `wave4_realism` hat gemessen, dass ein einziger
NAN-/INF-Wert aus der Physik in der Glättung hängen bleibt und jeden weiteren
Tick vergiftet (HUD „nan“, Paket für den Helfer undeutbar). `ffb_model.gd`
ersetzt seitdem jede nicht endliche Zahl über `_num()`/`_safe()` durch einen
Ersatzwert, plus Selbstheilung der Glättung. Der Test dazu ist jetzt
`tests/test_ffb_edge.gd` (600 Ticks NAN/INF/widersprüchliche Eingaben,
6 Prüfungen).

---

## 8. Welle 3: was der Root beim Nachmessen gefunden und geändert hat

Die Welle-2-Agenten haben die Prüfung nicht mehr abgeschlossen (sie liefen
ohne Bericht zu schreiben). Der Root hat deshalb selbst nachgemessen — die
Welle-3-Prüfagenten laufen parallel und dürfen diese Befunde widerlegen.

### 8.1 Mangel: G920 und G923 wurden abgewiesen (behoben)

Der Auftrag nennt die ganze Familie (G29/G920/G923). Die Godot-Seite konnte
das schon (`g29_input.gd`, `DEVICE_HINTS = ["g29", "g920", "g923", …]`), der
Helfer nicht: `G29ForceFeedback.__init__(name_filter="G29")` suchte nach genau
diesem Namen und brach mit
`kein Lenkrad gefunden, dessen Name 'G29' enthaelt` ab — dieselbe
DirectInput-Arbeit, ein anderer Produktname.

Behoben: `WHEEL_NAME_NEEDLES = ("g29", "g920", "g923")` gilt überall
(Standard-Lauf, `--selftest`, `--demo`, `--sign-check`, `--dry-run`,
`--matrix`), `--name NAME` (auch `--name a,b`) sucht ein anderes Rad, und die
neue Prüfung `die_ganze_lenkradfamilie_wird_gefunden` hält es fest. Gegenprobe:
mit einem wieder auf `("g29",)` verengten Filter schlägt die Prüfung fehl
(gemessen) — sie kann also fehlschlagen.

### 8.2 Mangel: ein Prüflauf hatte dem Fahrer das Force Feedback abgeschaltet (behoben)

Gemessen: `python tools/ffb_end_to_end.ps1` meldete
`FAIL die Kraft im Bogen kommt an Spitze 0,000`, und die Runde zeigte
`Quellen: {"aus": 1799}`. Ursache war nicht die Kette, sondern die Datei
`user://ffb_settings.json` des Fahrers: dort stand `"enabled": false`,
geschrieben während einer vorherigen Prüfung. Jede weitere Messung las diesen
Zustand und erklärte die Kette für kaputt.

Drei Änderungen, damit das nicht wieder passiert:

1. **Schutz in `ffb_settings.gd`**: im Headless-Betrieb wird die echte
   Einstellungsdatei nie geschrieben (`push_warning`, Rückgabe `false`) —
   dieselbe Regel, die `g29_input.gd` schon für das Lenkrad-Profil hat.
   Geprüft von `ein_testlauf_kann_die_echten_einstellungen_nicht_ueberschreiben`
   (29 Prüfungen in `test_ffb_settings.gd`).
2. **`APEX_FFB_SETTINGS`**: jeder Messlauf bringt seine eigene
   Einstellungsdatei mit und hängt nicht mehr am Menüstand des Fahrers.
3. **Der Schalter wird jetzt selbst geprüft**: `tools/ffb_end_to_end.ps1`
   fährt zweimal — FFB AN und FFB AUS — und verlangt im zweiten Lauf
   0,000 Kraft (9 Prüfungen).

### 8.3 Mangel: die Auslieferung war nicht belegt (behoben)

Der Desktop-Start läuft auf `Apex Circuit.exe` + `.pck`, nicht auf
`godot_f1/`. Ein Zeitstempel beweist nicht, was im Pack steht (die
GDScript-Konstanten liegen kompiliert und komprimiert darin — eine
Textsuche im Pack findet sie nicht, auch nicht die alten).

Behoben mit `tools/ship_check.ps1`: es startet den **ausgelieferten Build**
headless gegen den echten Helfer und misst ein Merkmal, das nur der neue Stand
hat — `APEX_FFB_SETTINGS`. Ergebnis: FFB AN → 408 Pakete, Reibung 0,130,
Dämpfung 0,310, Quelle `Asphalt`; FFB AUS → Reibung 0,000, Dämpfung 0,000,
Quelle `aus`. Ein Build ohne diesen Stand hätte in beiden Läufen dieselben
Zahlen geliefert.

Eine Textsuche im `.pck` taugt für diesen Beweis **nicht** — nachgemessen:
`rg -a -c "scripts/ffb_model.gd"` findet 3 Treffer (die Pfadliste liegt offen
im Pack), `"AM ANSCHLAG"`, `"LENKRADKRAFT AUS"` und `"Blockiert"` dagegen
**0**. Die GDScript-Literale liegen kompiliert und unlesbar im Pack. Eine
Suche nach Dateinamen sagt deshalb nur, *dass* die Datei im Pack liegt, nicht
*welcher Stand* — der Beweis steht auf der Messung.

**Nachgezogen: der Export.** Der Desktop-Start (`Apex Circuit.lnk`) zeigte auf
einen Export vom **17.09.** — also auf eine Version **ohne** das ganze Force
Feedback; spielbar war es nur aus den Godot-Quellen. Am 21.09. neu exportiert
(`export_windows.cmd`, Exit 0) und nach `Desktop\Apex Circuit\` kopiert. Im
`.pck` stehen nachweislich `scripts/ffb_model.gd`, `scripts/ffb_link.gd` und
`scripts/ffb_settings.gd` (Prüfung: `rg -a "scripts/ffb_" ApexCircuit.pck`).
Damit läuft auch der Doppelklick auf den neuen Stand.

### 8.4 Mangel: die Kette konnte stumm sein und niemand sagte warum (behoben)

Gemessen nach dem Fund aus 8.2: `tests/test_ffb_link.gd` meldete
`the_channel_is_not_muted`-Zustand `Quellen ["aus"]`, also **keine Kraft**. Das
Spiel sendet in diesem Fall weiter, aber mit `source:"aus"` und Kraft 0. Von
außen war das nicht zu unterscheiden von „Kette kaputt“: UDP bestätigt nichts.
Vier Änderungen:

1. **Der Test nagelt seine Eingangswerte fest** (`enabled=true`, Bänder 100 %,
   Stärke 0,75, Lenkbereich 400°). Ein Test, dessen Ergebnis davon abhängt, was
   der Fahrer zuletzt im Menü gedrückt hat, misst nicht die Kette.
2. **Neue Prüfung `the_channel_is_not_muted`**: stünde im Lauf `source:"aus"`,
   fällt der Test auf, statt 14 s lang Nullen zu bestaunen.
3. **Rückkanal**: `tools/g29_ffb.py` antwortet auf jedes Paket mit
   `{"v":2,"ack":1,"mode":"wheel"|"dry","torque":…}` (10 Hz), `ffb_link.gd`
   liest die Antwort (`helper_acks`, `helper_mode`, `helper_alive()`). Gemessen
   im Kettentest: **140 Lebenszeichen in 14 s**, Modus `wheel`,
   `helper_alive()` = wahr. `--check` prüft die Antwort (`der_helfer_antwortet_dem_spiel`,
   Antwort nach 0,01 s, 12 Prüfungen).
4. **Das HUD nennt den Grund**, statt „Lenkkraft 0 %“ zu zeigen:
   „LENKRADKRAFT AUS“ (Schalter), „LENKRADKANAL AUS (APEX_FFB=0)“ und
   „KEIN HELFER — Apex Circuit FFB starten.cmd“ (gesendet, aber nie eine
   Antwort). Alle drei Texte sind in `test_ffb_settings.gd` geprüft; die
   Warnung erscheint erst nach 120 gesendeten Paketen, damit sie beim Laden
   der Szene nicht fälschlich aufleuchtet.

### 8.5 Mangel: der Ende-zu-Ende-Test maß Stichproben statt Spitzen (behoben)

Gemessen: derselbe Lauf meldete `FAIL die Kraft im Bogen kommt an Spitze
0,250` (Schwelle 0,30), obwohl die Runde im Spiel selbst `Spitze 0,584` zeigte.
Ursache: `--verbose` schreibt alle **2 s** eine Zeile, ein Kurvenscheitel mit
3,5 g hält rund **1 s**. Die Prüfung las also den Zufall, nicht den Lauf.

Behoben: der Helfer druckt `[ffb-peak]` mit dem Maximum aus **jedem** Sample
des 200-Hz-Loops (Kraft, Rütteln, Hz, Tempo, Clipping, „über 1,0“-Zähler),
`tools/ffb_end_to_end.ps1` liest diese Zeile und prüft zusätzlich, dass sie
überhaupt da ist (`der Helfer meldet die echten Spitzen`). Ergebnis: **10
Prüfungen, 0 Mängel**, Kraftspitze **0,584** = exakt der Modellwert, Rütteln
0,700 @ 42 Hz, 0 Werte über 1,0.

---

## 9. Welle 5: die Kraftrichtung wird gemessen, nicht angenommen

### 9.1 Warum das nötig war

Am echten Rad gemessen (`python tools/ffb_hw_probe.py --seconds 1.5 --force
0.35`, viermal reproduziert): eine **positive DirectInput-Kraft fährt die
G29-Achse zu ihrem Minimum**. Damit war die halbe Kette bewiesen. Die andere
Hälfte war eine Annahme: ob „Achse runter“ im Spiel links oder rechts ist,
hängt davon ab, wie die DirectInput-Achse zur **SDL**-Achse steht, aus der das
Spiel „rechts = +1“ gelernt hat (`steer_invert: false`, `steer_span 0.5547`).
Falsch geraten hieße das: das Rad drückt in der Kurve nach außen statt nach
innen. Der Test, der es entscheidet (`tools/ffb_direction_check.ps1`), dreht
das Rad mit Kraft — er braucht eine Hand-freie, zuverlässig meldende Hardware.

### 9.2 Die Lösung: beide Seiten lesen dieselbe Achse

* `tools/g29_ffb.py` schickt die eigene **DirectInput-Achsenstellung** im
  Lebenszeichen mit (`{"ack":1,…,"axis":0…65535}`, 10 Hz). Fehlt sie, steht
  das Feld **nicht** im Paket — „keine Achsendaten“ darf nie als Messung
  durchgehen (`PASS ohne_rad_keine_erfundene_achse`).
* `ffb_link.gd::measure_direction()` vergleicht sie mit der **SDL**-Achse des
  Spiels: Mitte aus dem Stehen gelernt (das G29 ruht gemessen bei 32767 bis
  33104), gezählt wird erst ab 15 % Lenkeinschlag und nur mit fünf
  **verschiedenen** Lebenszeichen.
  * **gleichläufig** → „Achse runter“ ist links → Kraftrichtung **umgekehrt**,
  * **gegenläufig** → „Achse runter“ ist rechts → Kraftrichtung **normal**.
* Angewandt wird nur bei `|torque| ≤ 0,15` — ein Vorzeichenwechsel mitten im
  Bogen wäre ein Ruck ohne Erklärung. Das HUD meldet das Ergebnis kurz,
  das Menü zeigt bei „Kraftrichtung“ zusätzlich `(gemessen: gleichläufig /
  gegenläufig)`.
* **Der Fahrer behält das letzte Wort:** `ffb_settings.gd` speichert
  `invert_source` (`"fahrer"` oder `"gemessen"`, Version 3 der Datei). Sobald
  er den Schalter selbst anfasst, steht dort `"fahrer"` und die Automatik hält
  sich dauerhaft heraus — auch mitten in der Sitzung.

### 9.3 Messungen

| Prüfung | Ergebnis |
|---|---|
| `tests/test_ffb_direction.gd` (neu) | **19 Prüfungen PASS** — u. a. `ohne_achsenwert_keine_entscheidung`, `gleichlaeufig_erkannt → invert=true`, `gegenlaeufig_erkannt → invert=false`, `fahrerwahl_schaltet_die_automatik_aus`, `im_bogen_kein_vorzeichenwechsel` |
| `python tools/g29_ffb.py --check` | **14 Prüfungen, 0 Mängel** (neu: `das_lebenszeichen_traegt_die_achsenstellung`, `ohne_rad_keine_erfundene_achse`) |
| alle 19 `godot_f1/tests/test_*.gd` | alle PASS, 0 FAIL |
| `tools/ffb_end_to_end.ps1` | 10 Prüfungen, 0 Mängel (Spitze 0,584, Rütteln 0,700 @ 42,2 Hz) |
| `tools/ship_check.ps1` | **5 Prüfungen, 0 Mängel** gegen den neu exportierten Desktop-Build — inklusive der beiden neuen Testfälle **im Build** |

Zusätzlich in Kriterium 17 aufgenommen: **18. Kraftrichtung wird gemessen** —
das Spiel leitet sie aus dem Vergleich der Helfer- und der SDL-Achse ab, ohne
eine Hand am Lenkrad; ohne Achsdaten bleibt das Ergebnis ausdrücklich unbekannt.

### 9.4 Ein Fehler, den der eigene Test gefunden hat

Die erste Fassung wandte eine gefällte Entscheidung nur beim nächsten **neuen**
Messwert an — neue Messwerte gibt es nur beim Lenken, also genau dann, wenn
Kraft am Rad liegt. Auf der Geraden wäre die Entscheidung nie angekommen
(`FAIL auf_der_geraden_wird_es_gesetzt`). Behoben: steht die Entscheidung, wird
sie in jedem Tick erneut zu setzen versucht, bis das Rad ruhig genug ist.

### 9.5 Was offen bleibt

Der **Fühltest**: Software kann messen, dass die Kraft in die richtige Richtung
geht und wie stark sie ist — nicht, ob sie sich richtig anfühlt. Dafür
`"Apex Circuit FFB starten.cmd" --demo` oder eine Runde fahren. Das Rad muss
dabei zuverlässig Achsdaten liefern (sonst bleibt die Richtungsmessung ehrlich
bei „unbekannt“).

---

## 10. Welle 5 (Root-Audit): die Messkette selbst war angreifbar

Ein Prüfbericht ist nur so viel wert wie die Messung, aus der er stammt. Diese
Welle hat nicht das Lenkrad geprüft, sondern das, was das Lenkrad prüft — und
dabei drei Mängel gefunden, von denen zwei die **ganze bisherige Beweislage**
hätten entwerten können.

### 10.1 Ein Kollisionslauf zählte als bestanden

Gemessen am 21.09.2026 um 18:56, beim Nachfahren der Testliste: mein
`test_lap_drive.gd` lief gleichzeitig mit fremden Godot-Läufen. Die Ausgabe war

```
SCRIPT ERROR: Could not preload resource script "res://scripts/ffb_link.gd"
SCRIPT ERROR: Nonexistent function 'new' in base 'GDScript'
PASS nobody_falls_out_of_the_world lowest y=inf m ()
LAP_DRIVE PASS            (exit=0)
```

Das Auto war nie gebaut worden, die Szene war tot — und der Test meldete
**PASS**, weil jede seiner Prüfungen über ein leeres Feld lief (`INF > -4,0`
ist wahr). Der erste Zählversuch („wie viele Testdateien sind grün?“) hätte
diesen Lauf mitgezählt.

Zwei Ursachen:

1. Die Sperre in `tools/run_godot.ps1` war umgehbar: die README zeigte
   `godot --headless ...` direkt. Wer das tippt, startet Godot am Cache vorbei.
2. Ein so kaputter `SceneTree`-Test erreicht sein `quit()` nie. Godot lief
   endlos weiter (gemessen: PID 32524, sechs Minuten, Elternprozess weg), der
   Wrapper gab nach seinem Timeout auf und **ließ die Waise stehen** — jede
   folgende Messung war damit ebenfalls vergiftet.

### 10.2 Was jetzt dagegen steht

* **`tools/run_godot.ps1`** erkennt vor jedem Start fremde Godot-Instanzen am
  selben Projekt. Statt erfundene Messwerte zu liefern, bricht er mit Exit 125
  ab (`-AllowStray` erzwingt den Start); nach `-Timeout` wird der eigene Godot
  wirklich beendet (Exit 126). Die Exit-Codes stehen im Kopf der Datei.
* **`tools/run_all_tests.ps1`** (neu) fährt alle Testdateien nacheinander durch
  die Sperre und zählt eine Datei nur dann als Beweis, wenn der Exit-Code 0
  ist, **keine** Zeile wie `SCRIPT ERROR`, `Parse Error`, `Compile Error`,
  `Nonexistent function`, `Failed to load script` oder `Invalid call` vorkommt,
  **keine** `FAIL`-Zeile dasteht und mindestens eine `PASS`-Zeile existiert.
  Logs liegen in `tools/testlogs/`. Ein Zählfehler in die andere Richtung wurde
  dabei gefunden und behoben: das erste Muster akzeptierte nur `PASS ` am
  Zeilenanfang und machte `test_drive_unit` fälschlich rot.
* **`tests/test_lap_drive.gd`** fragt jetzt ausdrücklich nach Fahrer- und
  KI-Auto und nach der Zahl der gelesenen Positionen. Eine tote Szene ist damit
  ein Fehler statt eines stillen „PASS“.
* **`godot_f1/README.md`** zeigt keinen direkten Godot-Aufruf mehr, nennt
  Runner und Wrapper und führt die fünf Tests, die in der Liste fehlten.

### 10.3 Der zweite Mangel: ausgeliefert ≠ aktuell

Gemessen um 19:10: Der Desktop-Start `Apex Circuit.lnk` zeigt auf
`Desktop\Apex Circuit\`, der Export schrieb nach `grok f1 try\ApexCircuit\`.
Die ausgelieferte `.pck` war vom **18:58**, der frische Export vom **19:06** —
der Spieler hätte eine ältere Version gestartet. `tools/ship_check.ps1` hätte
das nicht gemerkt: es prüft die ausgelieferte Kopie, und die bestand die neuen
Testfälle zufällig schon.

Jetzt: `tools/export_and_deliver.ps1` (aufgerufen von `export_windows.cmd`)
exportiert, **liefert an den Desktop-Ort aus**, vergleicht die
SHA256-Summen beider Kopien und prüft, dass die ausgelieferte Datei nicht
älter ist als die neueste Quelldatei. `tools/ship_check.ps1` hat dafür eine
sechste Prüfung („die ausgelieferte Datei ist nicht älter als die Quelle“).

Nebenbei aufgefallen: `& $godot …` **wartet nicht** (Godot ist ein
GUI-Programm) und `$LASTEXITCODE` bleibt leer — die Prüfung meldete „exit “ ohne
Zahl, während der Export im Hintergrund noch lief. Jetzt `Start-Process -Wait`.

### 10.4 Gemessen nach dem Umbau (21.09.2026, 19:05–19:25)

| Prüfung | Ergebnis |
|---|---|
| `tools/run_all_tests.ps1` | **19 Dateien, 380 Prüfungen, 186 s, alle grün** — jede Datei Exit 0, ohne Fehlerzeile, mit PASS |
| `python tools/g29_ffb.py --check` | **14 Prüfungen, 0 Mängel** |
| `tools/ffb_end_to_end.ps1` (Spiel + echter Helfer) | **10 Prüfungen, 0 Mängel** — Kraftspitze 0,584, Rütteln 0,700 @ 42,2 Hz, Quellen Asphalt/Blockiert/Kerb/Kies/Schalten, Schalter AN/AUS wirkt |
| `tools/ship_check.ps1` gegen den **neu ausgelieferten** Build | **6 Prüfungen, 0 Mängel** |
| `tools/export_and_deliver.ps1` | beide Kopien identisch (`SHA256 EA2DF4EB…`), ausgeliefert 19:08:27 nicht älter als die neueste Quelle 19:07:19 |

### 10.5 Was auch diese Welle nicht beweisen kann

Der **Fühltest am Lenkrad**. Alle Zahlen oben belegen Richtung, Stärke,
Frequenz und Kette — nicht, ob sich das Ergebnis für den Fahrer richtig anfühlt.
Der Helfer liefert dafür weiterhin `--demo` (alle Fahrsituationen einmal am Rad)
und `tools/ffb_direction_check.ps1` (dreht das Rad mit Kraft, Hände weg).
