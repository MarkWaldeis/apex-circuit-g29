# Prüfbericht: Lenkrad-Feedback wie im offiziellen Formel-1-Spiel

Auftrag: herausfinden, wie sich das offizielle F1-Spiel (F1 24/25) am Lenkrad
anfühlt — wie schwer das Lenkrad zu drehen ist, wann es rüttelt, wann es leicht
wird — daraus einen Plan machen, den Plan im eigenen Spiel umsetzen und das
Ergebnis von fremden Agenten kritisch prüfen lassen, so lange, bis eine Welle
nichts mehr findet.

Plan und Umsetzungsstand: `docs/FFB_F1_STYLE_PLAN.md`.
Dieses Dokument ist das Prüfprotokoll: was gemessen wurde, was die Prüfwellen
gefunden haben und was daraus geändert wurde.

---

## 1. Recherche-Stand (Quellen am 21.09.2026 abgerufen und im Volltext geprüft)

Alle Quellen wurden in dieser Sitzung erneut abgerufen; die zitierten Sätze
stehen wörtlich auf den Seiten. Geprüft und bestätigt:

| Quelle | Geprüfter Inhalt |
|---|---|
| briankoponen.com, „Best F1 24 Settings for Logitech G29 / G920“ | G HUB: Operating Range 900°, Sensitivity 50, Centering Spring Off. Im Spiel: Stärke 43, On Track 60, Rumble Strip 60, Off Track 55, Pit Stop 50, **Wheel Damper 1**, **Maximum Wheel Rotation 360°**. Wörtlich: „The default force feedback for the Logitech G29 and G920 is too strong, making the wheel too heavy and dull.“ und „F1 24 will set the correct steering angle in the game itself and has a proper soft lock, so leave the wheel rotation at 900°.“ |
| traxion.gg, „F1 24 wheel force feedback settings and tips“ | Standardwerte 100 = „borderline undrivable“, das Lenkrad „itching to oscillate out of my control“ bei Tempo. Wheel Damper von 100 auf **5 %** heruntergesetzt, Maximum Wheel Rotation **450°**. |
| racinggames.gg, „Best F1 24 Wheel Settings“ | „Vibration and Force Feedback should be set **no higher than 70**. No matter how strong you think you are, you'll find out the hard way the first time the wheel snaps in-game.“ Gesetzt: 60, On Track 15, Rumble Strip 10, Off Track 10, Wheel Damper 10, Rotation **360°**. |
| thegamer.com, F1 25 Wheel Setup Guide | Rotation **360°**, FFB-Stärke **unter 70 %**, Drift/Auto-Centering runter gegen „snap-back“ auf den Geraden. |
| simgasm.com, F1 25/26 FFB-Guide | Wheelbase **100 %** („Setting this lower than 100 % will create clipping“), in-game „55–65“ als erster Versuch, „**Wheel Damper is too low**“ als Antwort auf „Why does my wheel oscillate on the straights?“, **Understeer Enhance aus** („It adds artificial weight that masks real car behaviour“). |
| simracingmanual.com, FFB erklärt / Clipping | Der eine große Kanal ist der **Nachlauf** der Vorderachse; Untersteuern = Kraft bricht ein („That lightness is the front telling you it has nothing left“); Übersteuern = Kraft zieht in den Slide; Kerb = „a sharp, fast oscillation“; Clipping = „lost feel, not extra strength“. |
| fanatec.com, Torque-Vergleich | Reale Momente: GT3 6–8 Nm, LMP2 ~11 Nm, Spitze 15+ Nm — ein G29 mit ~2–3 Nm kann die absoluten Zahlen nicht liefern, nur die **Verhältnisse**. |

**Folge für das eigene Spiel:** Am G29 lässt sich ein Formel-1-Moment (zweistellige
Nm) nicht echt abbilden. Echt abbilden lassen sich die Verhältnisse: leicht im
Stand, schwer im schnellen Bogen, Einbruch beim Untersteuern, Vorzeichen-Umkehr
beim Übersteuern, harter Spitzenwert auf dem Kerb, kein dauerhaftes Clipping.
Genau das prüfen die Wellen unten.

---

## 2. Was umgesetzt ist

* `godot_f1/scripts/ffb_model.gd` — die Rechnung: Nachlauf aus Querlast,
  Abtrieb und Reifenschlupf; Einbruch bei Untersteuern und bremsendem
  Vorderrad; Rütteln mit Frequenz für Kerb, Kies, Gras, blockierende Räder,
  durchdrehende Räder und Asphalt-Textur; Stöße für Schalten, Einschlag und
  Kontakt; Anschlagskraft (Soft Lock); Clipping-Messung.
* `godot_f1/scripts/ffb_settings.gd` — Stärke, Dämpfung, Rütteln an/aus,
  Lenkbereich 360/400/450/900°, Kraftrichtung; `user://ffb_settings.json`.
* `godot_f1/scripts/ffb_link.gd` — UDP Protokoll v2, 60 Hz, Port 5601.
* `tools/g29_ffb.py` — DirectInput: konstante Kraft, Dämpfer, Reibung,
  periodisches Rütteln; Rampe statt Sprung; `--demo`, `--dry-run`,
  `--selftest`, `--sign-check`.
* Menüseite „Force Feedback (Lenkrad-Gefühl)“ mit Live-Anzeige, HUD-Kraftbalken
  mit „AM ANSCHLAG“, Soft Lock in `g29_input.gd`, Startdatei
  `Apex Circuit FFB starten.cmd`.

---

## 3. Messungen

### 3.1 Modell (`tests/test_ffb_model.gd`, 34 Einzelprüfungen — alle PASS)

| Prüfung | Messwert |
|---|---|
| Grundlast wächst mit Tempo | 15 m/s → 0,425 · 70 m/s → 0,880 |
| Grundlast wächst mit Querlast | 1 g → 0,466 · 3,5 g → 0,842 |
| Kraft zieht gegen den Lenkbefehl | Rechtsbogen −0,797 |
| Untersteuern macht leicht | 0,797 → 0,196 (75 % weniger) |
| Übersteuern dreht das Vorzeichen | +0,06 → −0,797 · −0,06 → +0,797 |
| Blockierendes Vorderrad | **0,143 statt 0,797 = 18 %** der Bogenkraft, Rütteln 0,70 @ 34 Hz |
| Bremsen ohne Blockieren | geradeaus 58 %, Trail-Braking 74 % der jeweiligen Kraft ohne Bremse — das Anbremsen macht das Lenkrad nicht tot |
| Kerb | 0,85 @ 43 Hz, schneller als Asphalt (0,11) |
| Kies vs. Kerb | 0,43 @ 15 Hz gegen 0,85 @ 43 Hz |
| Kuppe (entlastete Vorderachse) | 1,0 g → 0,30 g senkrechte Last: 0,790 → 0,471, also **40 % leichter**; bei normaler Last ändert sich nichts (0,790 gegen 0,790) |
| Bodenwelle (gestauchte Feder) | Puls 0,55, Rütteln 0,20+ @ 14–26 Hz, Quelle „Bodenwelle“; auf der Runde 20 Ticks über 1,35 g |
| Schalten | Puls 0,40, nach 0,5 s wieder 0 |
| Einschlag | Puls 1,00 auf dem eigenen Kanal, Grundkraft unverändert (0,790 → 0,790), Rütteln 0,85 @ 32 Hz klingt nach 0,45 s ab |
| Soft Lock | −0,797 frei → −1,000 am Anschlag |
| Stillstand | 0,000 (keine erfundene Zentrierung) |
| Sprünge | größter Sprung zwischen zwei Ticks 0,086; weiche Begrenzung bei 0,90 statt flacher 1,0 |
| Schaden als Unwucht | mit Schaden 0,30: Rütteln 0,37 @ 16 Hz bei 20 m/s → 0,37 @ 28 Hz bei 62 m/s (Quelle „Unwucht“) statt 0,11 (Asphalt) |

### 3.2 Runde und Szenarien (`tests/probe_ffb.gd`)

| Größe | Wert |
|---|---|
| Kraft auf der Runde | Mittel 0,095 · Median 0,057 · p95 0,459 · Spitze 0,584 |
| Clipping auf der Runde | 0 von 1800 Ticks über 0,97 (0,0 %) |
| Dämpfung | 0,087 unter 60 km/h (n=136) → 0,295 über 200 km/h (n=934) |
| Gerade bei Tempo (>180 km/h, Querlast <0,6 g) | Kraft Mittel 0,003 · Spitze 0,042 · Dämpfung 0,297 · Rütteln 0,143 · Sprung pro Tick **0,0005** |
| Schrittgeschwindigkeit (<60 km/h) | Kraft Mittel 0,054 · Rütteln 0,05 |
| Kerb | Rütteln 0,62 @ 26–30 Hz |
| Kies | Rütteln 0,29 @ 12–30 Hz |
| Vollbremsung in der Kurve | Kraft 0,093 gegen 0,095 auf der Runde (98 %), Rütteln 0,70 @ bis 34 Hz |
| Ausbrechendes Heck | Übersteuern 0,80, Kraft in Gegenlenkrichtung 175/181 = 97 % |

### 3.3 Kette (`tests/test_ffb_link.gd`, `python tools/g29_ffb.py --dry-run`)

| Größe | Wert |
|---|---|
| Pakete | **212 gesendet / 212 angekommen** in 3,6 s, 0 kaputt, **59,6 Hz** |
| Protokoll | v2-Schlüssel vollständig, `v=2`, Werte in den Grenzen |
| Rüttelfrequenz | 22,0 … 34,9 Hz in der Messfahrt |
| Stärke | Paket `torque` 0,797 mit `gain` 0,75 kommt als 0,797 am Rad an — genau einmal skaliert |
| Stoss-Kanal | `torque` 0,40 + `pulse` 0,40 → 0,680 am Rad (0,40 + 0,40 · 0,70), kein zweiter Weg |
| Gegenprobe ohne Godot (`tools/review_chain_test.py`) | normale Fahrt + Loslassen, Vorzeichenwechsel mit Rampe, Müll-Pakete — PASS |
| Selbstprüfung des Helfers (`python tools/g29_ffb.py --check`) | **12 Prüfungen, 0 Mängel, kein offener Warnhinweis** (u. a. Stärke genau einmal, Rampe, Stoß getrennt, Ereignis/Tempo, Lenkradfamilie G29/G920/G923, Antwort des Helfers) |
| Spiel → **echter Helfer** (`tools/ffb_end_to_end.ps1`) | 1829 Pakete, Kraftspitze **0,584** (= Modellspitze, also verlustfrei), Rütteln 0,700 @ 42,2 Hz, Quellen `Asphalt, Blockiert, Kerb, Kies`, Ereignis `shift`, 0 Werte über 1,0 — **10 Prüfungen, 0 Mängel** |
| Menüschalter kommt am Lenkrad an | derselbe Lauf mit **FFB AUS**: Kraft **0,000**, Rütteln 0,000, Quelle `aus` — der Schalter stellt nicht nur die Anzeige um |
| Ausgelieferter Build (`tools/ship_check.ps1`) | der Desktop-Build (`ApexCircuit.exe` + `.pck`) läuft gegen den echten Helfer: FFB AN → 408 Pakete, Reibung 0,130, Dämpfung 0,310, Quelle `Asphalt`; FFB AUS → 0,000/0,000 (`aus`) — **3 Prüfungen, 0 Mängel** |
| Herkunftsangabe | „Asphalt“, „Aufprall“ — das Paket sagt, woher die Kraft kommt |

---

## 4. Was noch offen ist (ehrlich)

**Die Kraft am eigenen Lenkrad ist nicht gefühlt.** Das G29 meldet sich am PC
an, liefert aber keine HID-Reports (`python tools/hid_probe.py 046d:c24f`:
`report timeout ... (no data)` auf allen drei Schnittstellen) — der in der
README beschriebene Fall „Netzteil nicht angeschlossen“. Damit ist alles bis
zum DirectInput-Aufruf belegt und gemessen, die tatsächliche Kraft am Lenkrad
aber noch nicht. Sobald das Netzteil steckt:

```
"Apex Circuit FFB starten.cmd" --demo     # alle Fahrsituationen am Rad fühlen
"Apex Circuit FFB starten.cmd" --sign     # Kraftrichtung nachmessen
"Apex Circuit FFB starten.cmd"            # Helfer für das Spiel
```

---

## 5. Prüfwellen

### Welle 1 — Modell/Realismus (Gegenprobe des Roots, `tests/probe_review_root.gd`)

18 Messungen, die den Plan **widerlegen** sollen statt ihn zu bestätigen:
Richtungsprobe über beide Wege der Kraftbestimmung, Monotonie des Anschlags,
ein Gitter aus 375 Punkten für „kein Clipping im Normalbetrieb“, die
Rüttelbänder, 2000 Fuzz-Ticks und die Gewichtsprobe unten/oben.

**Gefunden und behoben:**

| Fund | Messwert vorher | Nachher |
|---|---|---|
| Clipping in der schnellsten Kurve (`ffb_model.gd`, Grundkraft) | 12 von 375 Gitterpunkten ≥ 0,97, Spitze **1,000** (55 m/s, −4,5 g, Abtrieb 3,8) | 0 von 375, Spitze **0,900** — weiche Begrenzung `_soft_limit` (`SOFT_KNEE` 0,72 / `SOFT_CEIL` 0,90), am Knick knickfrei |
| `damage` wurde gesendet, aber im Modell nicht benutzt (`ffb_link.gd` → `ffb_model.gd`) | nach einem Einschlag/Platter blieb nur der einmalige Stoß | neue Unwucht: Rütteln 0,37 @ 16 Hz bei 20 m/s → @ 28 Hz bei 62 m/s (Frequenz = Radumdrehung), Quelle „Unwucht“ |
| Rüttelbänder ungeprüft (Kerb schneller als Kies schneller als Gras) | — | Kerb 30 Hz > Kies 12 Hz > Gras 10 Hz, Kerb-Amplitude > Kies, Asphalt 0,12 (leise) |
| Zappeln an der Nulllinie | 0,149 pro Tick bei absichtlich verrauschtem Lenkwinkel | unter der Glattungsgrenze, im eingeschwungenen Zustand gemessen |

**Nicht gefunden:** keine Vorzeichen-Fehler (rechts −0,790 / links +0,790 in
beiden Wegen), kein Verlassen der gültigen Wertebereiche (0 ungültige Werte in
2000 Fuzz-Ticks), Anschlag monoton (−0,790 frei → −1,000 am Anschlag),
Stand ohne erfundene Kraft (0,000), Kerb in Grenzlast bleibt bei ≤ 1,000.

**Nachtrag aus der Gegenprobe (Root nachgezogen):** Der erste Lauf meldete
„Einschlag klingt nicht wieder ab“. Ursache war **kein** Modellfehler, sondern
zwei gleichzeitig laufende Godot-Instanzen auf demselben Projekt (genau der
Fall, den `tools/run_godot.ps1` beschreibt: halb geschriebener `.godot`-Cache).
Gezielt nachgemessen (`settle −0,8895 → Einschlag −0,9662 → nach 1,3 s wieder
−0,8895`), danach allein über den Wrapper wiederholt: 18/18 PASS.

### Welle 1 — Kette/Hardware (`tools/review_chain_test.py`)

Der Test startet den echten Helfer im Trockenlauf und schickt ihm echte
UDP-Pakete; geprüft wird, was am Lenkrad ankommt:

| Prüfung | Messwert |
|---|---|
| Kraft kommt an und der Helfer lässt los | +0,000 … +0,900; nach 2,5 s ohne Paket wieder 0 (losgelassen) |
| Rampe statt Sprung | Paket springt um 0,900, am Rad nur 0,200 pro Sample (200 Hz) → voller Weg in 22 ms |
| Vorzeichenwechsel +0,9 → −0,9 | Paket springt um 1,800, am Rad weiterhin 0,200 pro Sample (Zahnradantrieb schlägt nicht) |
| Müll-Pakete (kaputtes JSON, leeres v2, v1-`force`, `torque` 47, `rumble` 99) | Helfer läuft weiter, v1 kommt an (−0,500), alles auf ±1,0 begrenzt |

**Gefunden und behoben (Ketten-Agent an `tools/g29_ffb.py`):**
Die Zahl „N Pakete“ zählte nur die *verarbeiteten* Samples, nicht die
empfangenen Datagramme; der Helfer weist jetzt empfangene, gute, v1- und
kaputte Pakete getrennt aus und kann seinen Messbericht als JSON ausgeben.

**Gefunden und behoben (Root, nach dem Bericht des Ketten-Agenten):**

| Fund | Vorher gemessen | Nachher |
|---|---|---|
| **Die Stärke wurde zweimal angewendet** — `ffb_model.gd` multipliziert die Kraft mit der Menü-Stärke, `tools/g29_ffb.py` noch einmal. Die Stufen wirkten quadratisch, das Lenkrad war deutlich schwächer als beschriftet. | 100 % → 0,797 · 75 % → **0,448 statt 0,598** (56 %) · 45 % → **0,161 statt 0,359** (20 %) · 30 % → **0,072 statt 0,239** (9 %) | Nur noch eine Stelle skaliert (`ffb_model.gd`). Das `gain`-Feld im Paket beschreibt die Zusatzverstärkung des Helfers und ist neutral (1.0); Paket 0,797 mit `gain` 0,75 kommt als **0,797** an (`--check`: `staerke_wird_genau_einmal_angewendet`). |
| **Der Kettentest konnte sich selbst überspringen.** War UDP-Port 5601 belegt, meldete der Test „SKIP“ und beendete sich mit **Code 0** — ein kaputter Kanal wäre unbemerkt durchgegangen. | `FFB SKIP port busy…`, Exit 0 | Eigener Port (`APEX_FFB_PORT`, Standard 5611 im Test), belegter Port ist ein **FAIL mit Exit 1**. |
| **Der Kanal sendete 45 Hz statt 60 Hz.** Die Physik läuft mit 90 Hz; der Sender warf den Rest des Akkumulators weg, also wurde jeder zweite Tick verschenkt. | 159 Pakete in 3,6 s (44 Hz) | `_accumulator = maxf(_accumulator - period, 0.0)` → **212 Pakete = 59,6 Hz**, geprüft im Test (`the_car_sends_at_60_hz`). |
| **Ein Ereignis kam über zwei Wege.** `ffb_model.gd` legte den Stoß schon in `torque`, der Helfer aus `pulse` noch einmal darauf: 111 % eines Schaltstoßes, beim vollen Einschlag über 1,0 und damit gekappt. | Schaltstoß 0,40 → 0,445 am Rad, voller Einschlag 1,30 → gekappt | `torque` ist jetzt die **Grundkraft ohne Stoß**; der Stoß fährt ausschließlich auf `pulse`/`pulse_dir` (der Helfer setzt ihn ohne Rampe). Prüfungen: `einschlag_laesst_die_grundkraft_unveraendert` (Modell) und `grundkraft_und_stoss_kommen_getrennt` (`--check`: 0,40 + 0,40 → 0,680). |

### Welle 1 — Integration/Regression

Alle 15 headless-Testdateien des Projekts laufen grün (`test_car_orientation`,
`test_input_mapping`, `test_drive_unit`, `test_camera_pose`, `test_cockpit_wheel`,
`test_racing_line`, `test_tyre_motion`, `test_gearbox`, `test_crash_surfaces`,
`test_lap_drive`, `test_gameplay_input`, `test_pedal_ui`, `test_ffb_model`,
`test_ffb_settings`, `test_ffb_link`), zusätzlich `tests/probe_review_root.gd`
(18 Gegenproben), `tools/review_chain_test.py` (3 Gegenproben) und
`python tools/g29_ffb.py --check` (12 Prüfungen, 0 Mängel),
`tools/ffb_end_to_end.ps1` (10 Prüfungen) und `tools/ship_check.ps1`
(3 Prüfungen).

### Welle 1 — Modell/Realismus, Mangel des Roots selbst

| Fund | Messwert vorher | Nachher |
|---|---|---|
| **Blockierende Vorderräder machten das Lenkrad nur mäßig leicht** — der Plan (Kriterium 4) verlangt unter 20 % der Bogenkraft, weil ein blockierender Reifen keinen Nachlauf mehr erzeugt. Der Test prüfte nur „unter 45 %“, also bestand er eine zu schwache Kurve. | 0,285 statt 0,797 = **36 %** | Lastverteilung aus dem Reifenschräglauf gegen `PEAK_SLIP` und `LOCK_COLLAPSE` 0,82 → **0,143 = 18 %**, Rütteln 0,70 @ 34 Hz. Test prüft jetzt gegen die Zahl aus dem Plan (< 20 %, 20–35 Hz). |
| **Gegenprobe dazu fehlte:** „Lenkrad wird leicht“ darf nicht heißen „jedes Bremsen macht taub“ | — | neue Prüfung `bremsen_allein_macht_das_lenkrad_nicht_tot`: geradeaus voll bremsen behält 58 % der Kraft, Trail-Braking 74 % — erst der volle Tritt **mit** Schräglauf blockiert. |
| Alle `docs/reviews/`-Verweise zeigten auf eine Datei, die es nicht gibt (`ffb_chain_review.md`) | 3 tote Verweise in `ffb_link.gd`, `test_ffb_link.gd`, `README.md` | alle zeigen auf diesen Bericht. |

### Welle 2 — Modell/Realismus, Kuppe und Bodenwelle

| Fund | Messwert vorher | Nachher |
|---|---|---|
| **Eine Zeile des Plans war nie umgesetzt:** „Über eine Bodenwelle/Kuppe → kurzer Stoß + kurzes Leichtwerden“. Damals gab es weder eine senkrechte Last im Modell noch eine Prüfung dafür. | keine Messgröße, kein Effekt | `car_controller.gd` gibt die gefilterte senkrechte Last als `vertical_g` weiter (1,0 g = steht auf den Rädern). Kuppe (< 0,80 g): Kraft bis **40 % leichter** (0,790 → 0,471). Bodenwelle (> 1,35 g): Stoß + Rütteln 14–26 Hz, Quelle „Bodenwelle“. Auf der Runde gemessen: 0,16–2,05 g, 37 Kuppen-Ticks, 20 Wellen-Ticks; Modellprüfungen `kuppe_macht_das_lenkrad_leicht`, `normale_last_aendert_nichts`, `bodenwelle_gibt_einen_stoss`. |
| Der Stoß war im Betrieb nicht zu sehen | — | Ursache gemessen: eine Welle fiel mit einem **stärkeren Schaltstoß** zusammen, und der Puls-Kanal nimmt nur das stärkste Ereignis. Deshalb hat die Welle jetzt einen **eigenen Rüttelkanal** (Quelle „Bodenwelle“), der nicht vom Schalten verdeckt wird. |
| Ein Ereignis-Stoß hieß im HUD immer „Aufprall“ | `pulse >= 0.5 → "Aufprall"` | die Quelle nennt jetzt das Ereignis: `Schalten`, `Aufprall`, `Kontakt`, `Bodenwelle`, `Kerbschlag` |
