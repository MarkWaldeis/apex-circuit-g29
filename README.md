# Apex Circuit — G29 Formel-1

Eigenes Formel-1-Spiel für **Logitech G29** (Lenkrad + Pedale), gebaut mit **Blender 5.2** und **Godot 4.7**.

GitHub: https://github.com/MarkWaldeis/apex-circuit-g29

## Was das Spiel kann

* **Startmenü** mit *Fahren*, *Einstellungen* und *Beenden*; `Esc` öffnet jederzeit das Pausenmenü und führt immer wieder zurück ins Rennen.
* **Pedale selbst anlernen**: unter *Einstellungen* Gas, Bremse und Kupplung einzeln kalibrieren — Taste drücken, Pedal durchtreten, das Spiel erkennt die Achse und merkt sie sich (`user://g29_profile.json`). Die Zuordnung verbessert sich danach von selbst, wenn du im Rennen härter trittst.
* **Pedale von Hand korrigieren**: die Zeilen *Gas / Bremse / Kupplung* unter den Achsenbalken zeigen live, was das Spiel wirklich als Gas, Bremse und Kupplung verwendet. Falsch erkannte Achse? Ein Klick auf **Gas ⟷ Bremse tauschen** oder auf **Achse aN ändern** — belegte Achsen werden dabei übersprungen, die Wahl wird sofort gespeichert.
* **Lenkrad-Kalibrierung** inklusive Drehrichtung.
* **Cockpit-Ansicht**, in der sich das Lenkrad im Spiel mit dem echten G29 mitdreht, mit Schaltblitzen und Pedalanzeige im HUD.
* **Echtes Force Feedback am G29** wie im offiziellen F1-Spiel: das Lenkrad
  wird im schnellen Bogen schwer, wird leicht, wenn die Vorderachse
  untersteuert oder blockiert, zieht im ausbrechenden Heck in die
  Gegenlenkrichtung, rüttelt auf dem Kerb (schnell) und auf Kies (grob),
  gibt einen Stoß beim Schalten und beim Einschlag — und hat einen
  fühlbaren Lenkanschlag (Soft Lock) bei 360/400/450/900°. Der ganze Plan
  mit Quellen und Messwerten steht in `docs/FFB_F1_STYLE_PLAN.md`.
  Gemessen auf einer Runde: Kraft Mittel 10 %, Spitze 59 % der
  Lenkradstärke, auf der Geraden bei Tempo praktisch ruhig (Sprung pro Tick
  0,0005), 0 % der Ticks im Anschlag. Was noch **nicht** gemessen ist: die
  Kraft am eigenen Lenkrad — das G29 meldet sich ohne Netzteil am PC an,
  liefert aber keine Achsendaten und keine Kraft. Der ehrliche Stand steht
  am Ende von `docs/FFB_F1_STYLE_PLAN.md` und in
  `docs/reviews/ffb_f1_style.md`.
* Der Wagen fährt vorwärts in die richtige Richtung (Nase = Fahrtrichtung), Vorderräder lenken sichtbar mit, Hinterräder treiben an.
* **Lenkrichtung stimmt**: rechts am Lenkrad ist rechts im Spiel — Cockpit-Lenkrad, sichtbare Vorderräder und die Fahrphysik drehen alle in dieselbe Richtung (`godot_f1/tests/test_cockpit_wheel.gd`).

## Schnellstart

Doppelklick auf **Apex Circuit** auf dem Desktop, oder auf `Apex Circuit starten.lnk` im Projektordner.

Für die Kraft am Lenkrad zusätzlich **`Apex Circuit FFB starten.cmd`**
doppelklicken (Fenster offen lassen). Ohne dieses Fenster läuft das Spiel
unverändert, nur eben ohne Kraft — Godot selbst kann am G29 kein
Force Feedback erzeugen.

Unterstützt werden **G29, G920 und G923** — der Helfer sucht die ganze
Logitech-Familie (ein anderes Rad: `python tools/g29_ffb.py --name <Name>`).
Im Logitech G HUB einstellen: **Betriebsbereich 900°, Zentrierfeder AUS**,
Dämpfung so niedrig wie möglich. Das Spiel bildet den eingestellten
Lenkbereich (Standard 400°, wie im offiziellen Spiel) auf diese 900° ab und
baut den Anschlag selbst.

Die Rüttel-Regler heißen wie im offiziellen Spiel (**On Track Effects**,
**Rumble Strip Effects**, **Off Track Effects** — je 0–100 %) und wirken
getrennt: den Kerb leiser stellen lässt das grobe Kies-Mahlen stehen.

Die **Kraftrichtung misst das Spiel beim Fahren selbst**. Gemessen ist am
echten Rad, dass eine positive DirectInput-Kraft die G29-Achse zu ihrem Minimum
fährt (`python tools/ffb_hw_probe.py --seconds 1.5 --force 0.35`, viermal
reproduziert). Ob „Achse runter“ links oder rechts ist, hängt daran, wie die
DirectInput-Achse zur SDL-Achse steht, aus der das Spiel „rechts“ gelernt hat —
und das vergleicht das Spiel im Betrieb: der Helfer schickt seine
Achsenstellung mit jedem Lebenszeichen mit, das Spiel liest dieselbe Achse über
SDL. Sobald du das erste Mal richtig lenkst, steht die Richtung fest; gesetzt
wird sie in einem ruhigen Moment, nicht im Bogen, und das HUD meldet es kurz
(„Kraftrichtung gemessen: …“). Ohne Achsdaten (Rad stromlos) wird **nichts**
entschieden. Willst du es selbst bestimmen: `Esc` → *Einstellungen* → *Force
Feedback* → **Kraftrichtung** — deine Wahl gewinnt und die Automatik hält sich
dauerhaft heraus.

**Wichtig für Änderungen am Spiel:** der Doppelklick-Start läuft auf dem
**Export**, nicht auf den Godot-Quellen. Nach Änderungen also
`export_windows.cmd` ausführen (schreibt `ApexCircuit\ApexCircuit.exe` und
`.pck`) und beide Dateien als `Apex Circuit.exe` / `Apex Circuit.pck` in den
Desktop-Ordner `Apex Circuit\` kopieren. Sonst spielt der Desktop-Start eine
alte Version — genau das war der Fall: der Desktop-Build war vom 17.09. und
enthielt das ganze Force Feedback noch nicht.

Die eigentlichen Dateien liegen in:

- Desktop: `Apex Circuit\Apex Circuit.exe` (+ `.pck`, muss daneben liegen)
- Projekt: `ApexCircuit\ApexCircuit.exe` (+ `.pck`)

Falls die Datei noch nicht da ist, in Godot 4.7 den Ordner `godot_f1` öffnen und **Projekt → Exportieren → Windows Desktop**, oder:

```
export_windows.cmd
```

1. Godot 4.7 öffnen und den Ordner `godot_f1` importieren, oder:

```
godot --path godot_f1
```

2. G29 anschließen (optional, **Netzteil nicht vergessen**). Ohne Lenkrad: `WASD` / Pfeiltasten.
3. Im Menü *Fahren* wählen — der Wagen wartet auf dem Startplatz auf dein Gas. `Enter` schaltet den Auto-Pilot ein.
4. Wenn Gas und Bremse vertauscht sind: `Esc` → *Einstellungen* → *Gas kalibrieren*.

## Projektstruktur

| Ordner | Inhalt |
|---|---|
| `godot_f1/` | Spiel (Godot 4.7) |
| `godot_f1/scripts/` | Fahrphysik, G29-Eingabe, Menü, HUD, Kameras |
| `godot_f1/tests/` | Headless-Tests (Ausrichtung, Eingabe, Fahrphysik, Runde) |
| `godot_f1/assets/shaders/` | Lack-Shader (die GLBs enthalten keine Lackfarbe) |
| `blender/` | Blend-Datei, Python-Scripts, Source- und Export-GLBs |
| `blender/source_assets/` | Original-Modelle |
| `blender/exports/cars/` | 6 Low-Poly-Lackierungen, Reifen getrennt |
| `blender/exports/track/` | Apex Circuit + Racing Line |
| `tools/glb_probe.py` | Diagnose: schneidet ein GLB entlang Z (welches Ende ist die Nase?) |
| `tools/hid_probe.py` | Diagnose: liest rohe HID-Reports des G29 (Netzteil-/Kabel-Check ohne Godot) |
| `docs/` | Inventar (Excel) |

## Wenn das Lenkrad nicht reagiert

### Kraft kommt nicht an

Alles, was mit Force Feedback zu tun hat, steht unter **`Esc` → Einstellungen
→ Force Feedback (Lenkrad-Gefühl)**: Stärke, Dämpfung, Rütteln an/aus,
Lenkbereich und Kraftrichtung. Die Live-Anzeige dort (und oben rechts im
Rennen) zeigt, wie viel Kraft gerade wirklich ans Lenkrad geht und woher sie
kommt — steht dort „AM ANSCHLAG“, ist die Stärke zu hoch und das Lenkrad
wird taub statt stark.

Steht dort statt einer Zahl einer dieser Sätze, nennt das Spiel den Grund,
statt still zu bleiben:

* **„LENKRADKRAFT AUS“** — im Menü ist das Force Feedback abgeschaltet
  (`Esc` → Einstellungen → Force Feedback, Schalter auf AN).
* **„LENKRADKANAL AUS (APEX_FFB=0)“** — der Kanal wurde per
  Umgebungsvariable abgeschaltet.
* **„KEIN HELFER — Apex Circuit FFB starten.cmd“** — das Spiel sendet, aber
  niemand antwortet: das Helfer-Fenster ist zu. Der Helfer meldet sich auf
  jedem Paket zurück (`{"ack":1}`), deshalb kann das Spiel das überhaupt
  erkennen. (Die Warnung erscheint erst nach rund zwei Sekunden Fahrt, damit
  sie beim Laden der Szene nicht fälschlich aufleuchtet.)

Prüfen lässt sich die Kette ohne Spiel und ohne Lenkrad:

```
python tools/g29_ffb.py --check             # Kette prüfen: Stärke genau einmal, Rampe, Puls, Loslassen (Exit 0/1)
python tools/g29_ffb.py --dry-run          # Pakete, Rampe, Wertebereiche
python tools/g29_ffb.py --selftest         # Gerät + Effekte, kurzer Teststoß
python tools/g29_ffb.py --demo             # alle Fahrsituationen am Lenkrad fühlen
python tools/g29_ffb.py --name G923        # anderes Rad als G29/G920/G923 suchen
powershell -File tools/ffb_end_to_end.ps1  # echtes Spiel gegen den echten Helfer, ohne Lenkrad
powershell -File tools/ship_check.ps1      # läuft der AUSGELIEFERTE Build (Desktop-Start) richtig?
powershell -File tools/ffb_direction_check.ps1   # dreht eine positive Kraft nach rechts?
```

`--check` braucht kein Lenkrad und keinen zweiten Rechner: es schickt die
Pakete selbst durch denselben Weg, den das Spiel im Betrieb nimmt, und meldet
PASS/FAIL je Prüfung. Was es abdeckt und welche Mängel es gefunden hat, steht
in `docs/reviews/ffb_f1_style.md`.

`ffb_end_to_end.ps1` fährt zweimal: mit **FFB AN** (die Kraft muss ankommen)
und mit **FFB AUS** (es darf keine ankommen). Der zweite Lauf ist der Beweis,
dass der Schalter im Menü wirklich bis ans Lenkrad durchschlägt. Beide Läufe
bringen ihre eigene Einstellungsdatei mit (`APEX_FFB_SETTINGS`), damit sie
nicht davon abhängen, was zuletzt im Menü eingestellt war.

`ship_check.ps1` prüft die **ausgelieferte** `Apex Circuit.exe` — der
Desktop-Start läuft auf dem Export, nicht auf den Godot-Quellen. Es startet
den Build headless gegen den echten Helfer und misst, ob er den neuen Stand
enthält. Fünf Prüfungen: er kennt `APEX_FFB_SETTINGS` und schaltet bei „FFB
AUS“ alle Kanäle auf 0, er legt im Stand Reibung an — und er läuft zwei
Testfälle, die es in alten Ständen nicht gab (Vollgas trotz kaputter
Pedal-Kalibrierung, Selbstmessung der Kraftrichtung). Damit ist „der Build ist
aktuell“ gemessen und nicht aus einem Zeitstempel geschlossen.

Windows erkennt das G29 auch dann, wenn es **keine** Daten liefert — typisch, wenn das Netzteil nicht angeschlossen ist. Prüfen:

```
python tools/hid_probe.py 046d:c24f
```

Kommt nur `report timeout ... (no data)`, obwohl die Joystick-Schnittstelle mit sieben Achsen beschrieben wird, dann sendet das Lenkrad selbst nichts: Netzteil prüfen, Pedalkabel am Lenkrad festziehen, anderes USB-Port (möglichst direkt hinten am PC, kein Hub) probieren, Modusschalter am Lenkrad auf **PC** stellen. Danach im Spiel `Esc` → *Einstellungen* → *Gas kalibrieren*.

Einfacher geht es per Doppelklick im Projektordner: **`Lenkrad pruefen.cmd`** startet dieselbe Prüfung und zeigt die Checkliste an.

## Steuerung

Siehe `godot_f1/README.md`.
