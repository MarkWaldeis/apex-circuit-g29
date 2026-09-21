# Prüfbericht Welle 3: Integration, Auslieferung und Rückkanal

Prüfer: **Root-Audit** (dieselbe Person, die das Modell gebaut hat — deshalb
ist dieser Bericht ausdrücklich *keine* fremde Prüfung; die fremden Agenten
der Wellen 1 und 2 stehen in `ffb_chain_review.md`, `ffb_wave2_chain.md` und
`ffb_f1_style.md`). Die Welle-3-Agenten wurden mehrfach angesprochen und haben
ihren Lauf nicht mehr abgeschlossen; ihre Zwischenstände (Headless-Schutz in
`ffb_settings.gd`, die zwei zusätzlichen Ende-zu-Ende-Prüfungen) sind in den
Dateien erhalten und unten mit aufgeführt.

Alle Zahlen unten stammen aus Läufen dieses Turns; die Befehle stehen jeweils
dabei.

| Nr. | Mangel | Messung | Status |
|---|---|---|---|
| 1 | **G920 und G923 wurden abgewiesen.** Der Helfer suchte fest nach dem Namen „G29“, der Auftrag nennt die ganze Familie. | `G29ForceFeedback(name_filter="G29")` brach ab; die Godot-Seite konnte es seit jeher (`g29_input.gd`, `DEVICE_HINTS`) | behoben: `WHEEL_NAME_NEEDLES = ("g29", "g920", "g923")`, `--name`, neue Prüfung `die_ganze_lenkradfamilie_wird_gefunden` (12 Prüfungen in `--check`) |
| 2 | **Ein Prüflauf hatte dem Fahrer das FFB abgeschaltet.** In `user://ffb_settings.json` stand `"enabled":false` (geschrieben von einem Lauf **ohne** `--headless`, also dem exportierten Spiel). Die nächste Messung las das und meldete die Kette als kaputt. | `ffb_end_to_end.ps1`: `FAIL die Kraft im Bogen kommt an Spitze 0,000`, Runde `Quellen {"aus": 1799}`; `tests/test_ffb_link.gd` rot mit `Kraftspitze 0.000` | behoben (vier Schichten, siehe unten) |
| 3 | **Die Auslieferung war nicht belegt.** Der Desktop-Start läuft auf `Apex Circuit.exe`/`.pck`; ein Zeitstempel beweist nicht, was im Pack liegt (GDScript-Konstanten liegen kompiliert im `.pck`, eine Textsuche findet sie nicht). | — | behoben: `tools/ship_check.ps1` startet den **ausgelieferten Build** headless gegen den echten Helfer: FFB AN → 408 Pakete, Reibung 0,130, Dämpfung 0,310, Quelle `Asphalt`; FFB AUS → 0,000/0,000, Quelle `aus` (3 Prüfungen, 0 Mängel) |
| 4 | **Der Kettentest hing am Fahrer-Profil.** Er las die gespeicherten Einstellungen; mit `enabled:false` messen alle 14 s nur Nullen, und der Test kann „Kette kaputt“ nicht von „Schalter aus“ unterscheiden. | siehe Nr. 2 | behoben: der Test nagelt `enabled=true`, Bänder 100 %, Stärke 0,75, Lenkbereich 400° fest; neue Prüfung `the_channel_is_not_muted` (`Quellen ["aus"]` → FAIL) |
| 5 | **Der Helfer war unsichtbar.** Das Spiel sendet per UDP ins Leere, wenn kein Helfer lauscht — es gab keine Möglichkeit, von innen zu erkennen, dass die Kraft keinen Empfänger hat. | vorher: kein Feld, keine Antwort, kein Hinweis | behoben: **Rückkanal** `{"v":2,"ack":1,"mode":"wheel"\|"dry"}` (10 Hz), `ffb_link.gd` liest ihn (`helper_acks`, `helper_mode`, `helper_alive()`); gemessen 140 Lebenszeichen in 14 s, `--check` bekommt die Antwort nach 0,01 s |
| 6 | **Das HUD zeigte bei totem Lenkrad nur „0 %“.** | — | behoben: drei benannte Zustände — „LENKRADKRAFT AUS“, „LENKRADKANAL AUS (APEX_FFB=0)“, „KEIN HELFER — Apex Circuit FFB starten.cmd“; alle drei in `test_ffb_settings.gd` geprüft |
| 7 | **Der Ende-zu-Ende-Test maß Stichproben statt Spitzen.** `--verbose` schreibt alle 2 s, ein Kurvenscheitel hält ~1 s. | derselbe Lauf: einmal `Spitze 0,560`, einmal `Spitze 0,250` (Schwelle 0,30) → Fehlalarm; die Runde im Spiel selbst zeigte `Spitze 0,584` | behoben: `[ffb-peak]` mit dem Maximum aus **jedem** Sample des 200-Hz-Loops; der e2e-Test liest diese Zeile und prüft, dass sie existiert |

## Was die vier Schichten gegen Mangel 2 sind

1. `ffb_settings.gd`: im Headless-Betrieb wird `user://ffb_settings.json`
   **nie** geschrieben (`push_warning`, Rückgabe `false`) — dieselbe Regel, die
   `g29_input.gd` für das Lenkrad-Profil schon hatte. Geprüft von
   `ein_testlauf_kann_die_echten_einstellungen_nicht_ueberschreiben`
   (Datei-Inhalt **und** Zeitstempel vorher/nachher).
2. `main.gd`: `auto_save = DisplayServer.get_name() != "headless"`.
3. `APEX_FFB_SETTINGS`: jeder Messlauf bringt seine eigene Einstellungsdatei
   mit (`tools/ffb_end_to_end.ps1`, `tools/ship_check.ps1`) und hängt nicht am
   Menüstand des Fahrers.
4. Der Fahrer-Zustand wurde **wiederhergestellt**: in `user://ffb_settings.json`
   steht wieder `"enabled":true` (Sicherung der kaputten Datei liegt daneben
   als `ffb_settings.json.bak-20260921-1741`). Ohne diesen Schritt hätte der
   Doppelklick auf das Spiel weiterhin ein stummes Lenkrad ergeben — die Kette
   war in Ordnung, nur der Schalter stand auf AUS.

## Messungen dieses Turns

| Prüfung | Werkzeug | Ergebnis |
|---|---|---|
| Modell | `tests/test_ffb_model.gd` | **34 Prüfungen**, alle PASS (u. a. blockierende Räder **18 %** der Bogenkraft, Kerb 0,85 @ 43 Hz, Kies 0,43 @ 15 Hz) |
| Einstellungen/Menü/HUD | `tests/test_ffb_settings.gd` | **32 Prüfungen**, alle PASS |
| Kette, echte Fahrt | `tests/test_ffb_link.gd` | **839 Pakete / 839 gesendet in 14,0 s = 59,9 Hz**, Kraftspitze 0,577 über 293 Ticks, 291/293 = 99 % gegen den Lenkbefehl, Puls 0,60 in 55 Paketen, Quellen `Asphalt, Schalten, Blockiert`, **140 Lebenszeichen** vom Helfer |
| Kette ohne Godot | `python tools/g29_ffb.py --check` | **12 Prüfungen, 0 Mängel** (u. a. Stärke genau einmal, Rampe 0,200/Sample, Puls 0,280, Antwort des Helfers) |
| Bestand | alle 15 Testdateien in `godot_f1/tests/` | **alle PASS** (Orientierung, Cockpit, Crash, Antrieb, Getriebe, Eingabe, Runde, Pedale, Linie, Reifen) |
| Spiel → echter Helfer | `tools/ffb_end_to_end.ps1` | **1829 Pakete**, Kraftspitze **0,584** (echte Spitze), Rütteln 0,700 @ 42 Hz, Quellen `Asphalt, Blockiert, Kerb, Kies`, Ereignis `shift`, 0 Werte über 1,0 — **10 Prüfungen, 0 Mängel** |
| Ausgelieferter Build | `tools/ship_check.ps1` | 3 Prüfungen, 0 Mängel |

## Was weiterhin NICHT geprüft ist (ehrlich)

**Die Kraft am eigenen Lenkrad.** Das G29 meldet sich am PC, liefert aber keine
HID-Reports (`python tools/hid_probe.py 046d:c24f`: auf allen drei
Schnittstellen `report timeout … (no data)`) — ohne Netzteil gibt es weder
Achsendaten noch Kraft. Belegt ist alles bis zum DirectInput-Aufruf; der
Fühltest (`--demo`) braucht das Netzteil.
