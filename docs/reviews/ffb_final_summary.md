# Apex Circuit — Lenkrad-Gefühl: Abschlussübersicht

Stand: 21.09.2026, Commit `b16c623`. Diese Seite verknüpft **jede Anforderung
aus dem Auftrag** mit dem Beleg. Alles, was hier als „gemessen" steht, ist mit
den Werkzeugen in `tools/` bzw. `godot_f1/tests/` reproduzierbar; alles, was
als „offen" steht, ist es ausdrücklich.

## Der Auftrag, Punkt für Punkt

| Anforderung | Beleg |
|---|---|
| Im Internet nachsehen, wie sich das offizielle F1-Spiel am Lenkrad anfühlt (schwer? wann rüttelt es?) | `docs/FFB_F1_STYLE_PLAN.md` §1: sechs Quellen mit wörtlichen Zitaten (Traxion, Brian Koponen/G29, racinggames, TheGamer/F1 25, SIMGASM/Understeer Enhance, Sim Racing Manual) und §1.3, was ein G29 davon leisten kann (2–3 Nm gegen 6–15 Nm echter Rennwagen) |
| Kompletter Plan für dieses Spiel | `docs/FFB_F1_STYLE_PLAN.md` §2 (Soll-Tabelle pro Fahrsituation), §3 (Architektur, Protokoll v2, Dateien, Soft Lock, Einstellungen), §4 (Abnahmekriterien) |
| Im Spiel umsetzen | `ffb_model.gd`, `ffb_settings.gd`, `ffb_link.gd`, `wheel_feedback.gd`, `g29_input.gd`, `car_controller.gd`, `menu.gd`, `hud.gd`, `tools/g29_ffb.py`, `Apex Circuit FFB starten.cmd`; ausgeliefert als Desktop-Build |
| Subagenten prüfen kritisch, Funde werden abgearbeitet, Wiederholung bis nichts mehr gefunden wird | Wellen 1–10 in `docs/reviews/`: `ffb_f1_style.md`, `ffb_chain_review.md`, `ffb_wave2_chain.md`, `ffb_wave3_integration.md`, `ffb_wave4_hardware.md`, `ffb_wave4_pedals.md`, `ffb_direction_selfcheck.md`, `ffb_wave7_ownership.md`, `ffb_wave8_restart.md` |

## Was jede Prüfwelle gefunden hat (und was daraus wurde)

| Welle | Fund | behoben |
|---|---|---|
| 2 | Stärke wurde **zweimal** angewendet (30 % kamen als 9 % am Rad an) | ✅ eine Stelle skaliert |
| 2 | Kettentest konnte sich per „Port belegt“ selbst überspringen und meldete trotzdem Erfolg | ✅ belegter Port = FAIL |
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
| 10 | Der Fühltest (`--demo`) hätte die **Gegenrichtung** vorgeführt | ✅ auf gemessene Paketwerte umgestellt |

## Gemessene Antworten auf die Fragen aus dem Auftrag

| Frage | Antwort (am echten G29 bzw. in der echten Szene gemessen) |
|---|---|
| Wie schwer ist das Lenkrad zu drehen? | Bogen Spitze 0,58–0,64 der Lenkradkraft; Dämpfung 0,09 (< 60 km/h) → 0,30 (> 200 km/h); auf der Geraden 0,11 Rütteln (ruhig) |
| Wann wird es leicht? | Untersteuern −76 %; blockierende Vorderräder 18 % + Rattern 0,70 @ 34 Hz; über einer Kuppe 0,39 statt 0,64 |
| Wann rüttelt es? | Kerb 0,62 @ 30 Hz · Kies 0,32 @ 13 Hz · Gras 0,19 @ 11 Hz · Bodenwelle Puls 0,55 · durchdrehende Räder 0,53 · Unwucht nach Schaden 0,38 @ 28 Hz (mit dem Tempo schneller) |
| Zieht es in die Gegenlenkrichtung? | ja, im tiefen Slide 97 % der Ticks |
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

3. **Gras** ist nur im Modell und in der Demo gemessen, nicht in der Szene —
die Barriere steht bei 16 m Querabstand, Gras beginnt bei 16,85 m; erreichbar
ist es nur an den vier Stellen, an denen beim Streckenbau eine Barriere
verworfen wurde.
