# Apex Circuit — Lenkrad-Gefühl: Abschlussübersicht

Stand: 21.09.2026, Commit `867ecc8`. Diese Seite verknüpft **jede Anforderung
aus dem Auftrag** mit dem Beleg. Alles, was hier als „gemessen" steht, ist mit
den Werkzeugen in `tools/` bzw. `godot_f1/tests/` reproduzierbar; alles, was
als „offen" steht, ist es ausdrücklich.

## Der Auftrag, Punkt für Punkt

| Anforderung | Beleg |
|---|---|
| Im Internet nachsehen, wie sich das offizielle F1-Spiel am Lenkrad anfühlt (schwer? wann rüttelt es?) | `docs/FFB_F1_STYLE_PLAN.md` §1: sechs Quellen mit wörtlichen Zitaten (Traxion, Brian Koponen/G29, racinggames, TheGamer/F1 25, SIMGASM/Understeer Enhance, Sim Racing Manual) und §1.3, was ein G29 davon leisten kann (2–3 Nm gegen 6–15 Nm echter Rennwagen) |
| Kompletter Plan für dieses Spiel | `docs/FFB_F1_STYLE_PLAN.md` §2 (Soll-Tabelle pro Fahrsituation), §3 (Architektur, Protokoll v2, Dateien, Soft Lock, Einstellungen), §4 (Abnahmekriterien) |
| Im Spiel umsetzen | `ffb_model.gd`, `ffb_settings.gd`, `ffb_link.gd`, `wheel_feedback.gd`, `g29_input.gd`, `car_controller.gd`, `menu.gd`, `hud.gd`, `tools/g29_ffb.py`, `Apex Circuit FFB starten.cmd`; ausgeliefert als Desktop-Build |
| Subagenten prüfen kritisch, Funde werden abgearbeitet, Wiederholung bis nichts mehr gefunden wird | Wellen 1–11 in `docs/reviews/`: `ffb_f1_style.md`, `ffb_chain_review.md`, `ffb_wave2_chain.md`, `ffb_wave3_integration.md`, `ffb_wave4_hardware.md`, `ffb_wave4_pedals.md`, `ffb_direction_selfcheck.md`, `ffb_wave7_ownership.md`, `ffb_wave8_restart.md`, `ffb_wave11_lap.md` |

## Was jede Prüfwelle gefunden hat (und was daraus wurde)

| Welle | Fund | behoben |
|---|---|---|
| 1 | Kette: Stärke wurde **zweimal** angewendet (30 % kamen als 9 % am Rad an) — `ffb_chain_review.md`, Mangel 1 | ✅ eine Stelle skaliert |
| 1 | Kette: der Test konnte sich per „FFB SKIP port busy“ selbst überspringen und meldete trotzdem Erfolg — `ffb_chain_review.md`, Mangel 2 | ✅ belegter Port = FAIL |
| 2 | Kette: der Test **konnte die Kraft nicht verlieren** (Schwelle 0,02 gegen gemessene 0,163, weil der Wagen geradeaus fuhr); `max_rumble >= 0.0` konnte nie falsch werden; ein Vergleich war zufallsabhängig — `ffb_wave2_chain.md`, Mängel 1–3 | ✅ echte Kurvenfahrt, falsifizierbare Schwellen |
| 3 | Ein Prüflauf hatte dem Fahrer **das FFB abgeschaltet** | ✅ Headless schreibt nie ins Profil, `APEX_FFB_SETTINGS` |
| 4 | **NaN** aus der Physik vergiftete die Glättung dauerhaft | ✅ `_num`/`_safe` + Selbstheilung |
| 4 | Diagnoselauf überschrieb das **Lenkrad-Profil** des Fahrers | ✅ `APEX_G29_PROFILE` |
| 4 | Verseuchtes Profil **deckelte Vollgas auf 53 %** | ✅ unmögliche Spannweiten werden verworfen |
| 4 | **Kraftrichtung** war nur erschlossen | ✅ am echten Rad gemessen: positiv dreht links → `invert = true` |
| 7 | **Startreihenfolge** war die Ursache des „stummen" Lenkrads (Helfer zuerst = Rad friert ein) | ✅ Helfer wartet auf das Spiel |
| 8 | Warten schützte nur den ersten Start; Helfer hielt das Rad nach dem Spielende weiter | ✅ `--release-wheel-after`, echtes `wheel.close()` |
| 8 | Zwei Fehlermeldungen des Versand-Gates brachen **genau im Fehlerfall** ab | ✅ Klammerung, mit System-PID 4 gemessen |
| 9 | Stöße **ohne Lenkbefehl** kamen als 0,000 am Rad an (Schalten, Einschlag) | ✅ Klopfen mit 30 Hz statt nichts |
| 9 | Prüfwerkzeuge erschlugen sich gegenseitig (parallele Läufe) | ✅ Alters-Regel, Exit 125 |
| 9 | Ein **Wrack verdrängte Kerb und Kies** (0,300 @ 13 Hz → 0,750 @ 19 Hz, Quelle „Unwucht“) für den Rest der Sitzung | ✅ die Oberfläche führt, auf Asphalt bleibt die Unwucht (0,75) |
| 9 | Die **letzte Naht** (Paketfeld → DirectInput-Effekt) war nie gemessen | ✅ `_DeviceProbe`: `dwPeriod` 33333 µs = 30 Hz, Kies 76923 gegen Kerb 23809 µs, `invert` dreht im Gerät |
| 10 | Der Fühltest (`--demo`) hätte die **Gegenrichtung** vorgeführt | ✅ auf gemessene Paketwerte umgestellt (18 Stationen) |
| 10 | Die Stufe „Geradeaus 250 km/h“ trug 0,097 aus einem synthetischen Schräglauf und schob das frei gelassene Rad an den Anschlag | ✅ echte Gerade: 0,000 (Runde Mittel 0,003), neue Prüfung `der_fuehltest_laesst_die_gerade_ruhen` |
| 11 | **KI-Auto und Autopilot blieben 45 s bei 0 km/h im Kies liegen** (13,9 m Querabstand, Nase zur Bande) — der Rundentest sah es nie, weil er nach 40 s endet | ✅ `_watch_stuck()` in `car_controller.gd` (2,5 s Stillstand bzw. 8 s draußen → zurück auf die Linie; **der Fahrer wird nie angefasst**), geprüft von `test_stuck_rejoin.gd` (8 Prüfungen); Standphase 45,0 s → 2,6 s, vollständige Runde |
| 11 | Drei **Messfehler in meiner eigenen Sonde**: falscher Schlüssel (`lat_g` statt `lateral_g` → jede Querlast 0), Wandkontakt in der Gerade-Zahl, Kerb-Rattern in der Blockier-Zahl | ✅ alle drei getrennt und nachgemessen (`docs/reviews/ffb_wave11_lap.md`, Fund 2) |
| 11 | Mein **Übersteuer-Test war pauschal falsch angesetzt**: er forderte die Kraftumkehr für *jeden* Übersteuer-Tick (66 von 282) | ✅ getrennt gezählt: Vorderachse durch die Null 64 von 67 (96 %) gedreht, vorher 213 von 215 (99 %) gegen den Lenkbefehl |

## Gemessene Antworten auf die Fragen aus dem Auftrag

| Frage | Antwort (am echten G29 bzw. in der echten Szene gemessen) |
|---|---|
| Wie schwer ist das Lenkrad zu drehen? | **In echter Fahrt** (volle Runde, 1439/1440 Punkte, Spitze 283 km/h): Bogen ab 3 g Kraft Mittel **0,452**, Spitze **0,673**; Dämpfung min **0,244** auf der Geraden, Rütteln dort max **0,131**; Kurvenlast bis **3,95 g**. Stärke 90 % → Mittel 0,543/Spitze 0,808; 100 % → 0,603/0,898 — **in allen Fällen 0 Clipping-Ticks** |
| Wann wird es leicht? | **In echter Fahrt**: Untersteuern 152 Ticks, Kraft fällt auf Mittel **0,077** (83 % leichter als im Bogen); blockierende Vorderräder 0,700 Ratter @ 29–34 Hz bei Kraft max 0,215; über einer Kuppe 0,39 statt 0,64 (Modellmessung) |
| Wann rüttelt es? | **In echter Fahrt**: Kerb **0,795 @ 27–37 Hz** · Kies **0,399 @ 8–15 Hz** · Asphalt-Textur **0,131 @ 22–42 Hz** · durchdrehende Räder 213 Ticks, Rütteln **0,833** · Unwucht nach Schaden (Modell 0,19/0,38/0,64/0,75) |
| Zieht es in die Gegenlenkrichtung? | **In echter Fahrt** 2390 von 2508 Bogen-Ticks (95 %) gegen den Lenkbefehl; bei ausbrechendem Heck 64 von 67 (96 %) mit der Vorderachse durch die Null umgedreht |
| Spürt man den Anschlag? | Soft Lock bei 400° von 900°, Rangieren am Anschlag 0,37, monoton steigend |
| Kommen Schaltstoß und Einschlag an? | ja, auch ohne Lenkbefehl (dort als Klopfen) |
| Ist Clipping ein Thema? | 0 von 1800 Ticks über 0,97 auf einer Runde; weiche Begrenzung bei 0,90 |

## Offen (ehrlich)

1. **Dein Urteil am Lenkrad.** Alle Zahlen sind gemessen, aber ob sich Bogen,
Kerb, Blockieren, Unwucht und Anschlag *richtig anfühlen*, kann nur der Fahrer
sagen:

   ```cmd
   "Apex Circuit FFB starten.cmd"          :: Spiel + Kraft
   "Apex Circuit FFB starten.cmd" --demo   :: die 18 Stationen nacheinander
   ```

2. **Nicht gepusht.** Die Arbeit liegt in ~25 lokalen Commits auf `main`
(`origin/main` ist älter).

3. **Wie stark das Rad sein soll, ist eine Fühlentscheidung** — gemessen ist
nur die Wirkung: 75 % (Werk) gibt im schnellen Bogen Mittel 0,452 / Spitze
0,673, 90 % gibt 0,543 / 0,808, 100 % gibt 0,603 / 0,898. Das Menü nennt die
Empfehlung (90 %) jetzt selbst.

4. **Der Soft Lock ist headless nicht messbar**: `lock_pressure` kommt aus dem
Lenkdruck des G29. Belegt ist er im Modell (`test_ffb_model.gd`) und im
Fühltest (`--demo`, Station „Rangieren am Anschlag" 0,37) — nicht in einer
Rundenmessung.

5. **Gras** ist nur im Modell und in der Demo gemessen, nicht in der Szene —
die Barriere steht bei 16 m Querabstand, Gras beginnt bei 16,85 m; erreichbar
ist es nur an den vier Stellen, an denen `barriers.gd` eine Box **verwirft,
weil sie auf der Strecke läge** (gemessen mit
`tests/probe_barrier_geometry.gd`: `Barriers 476 boxes, 4 skipped`). Über eine
solche Lücke kommt der Wagen bis auf 16,85 m und weiter — dort gilt dann
Gras/Grip 0,30. Im normalen Fahren ist die Gras-Rückmeldung also unerreichbar,
und das ist eine Eigenschaft der Strecke, nicht des Lenkradmodells.
