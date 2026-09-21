# Prüfbericht Welle 4: echte Hardware (G29), Kette und Diagnosewerkzeuge

Prüfer: **Root-Audit** am echten Lenkrad, plus zwei Welle-4-Agenten
(`wave4_realism`, `wave4_journey`). Die beiden Agenten haben in dieser Welle
ihren Lauf **nicht abgeschlossen** und keinen eigenen Bericht geschrieben; ihr
einziger erhaltener Beitrag ist die NAN-Härtung in `scripts/ffb_model.gd` und
der dazugehörige Randfall-Test (heute `tests/test_ffb_edge.gd`). Alles andere
unten ist am 21.09.2026 vom Root selbst gemessen, mit Befehl und Messwert.

## 1. Was in dieser Welle anders war

Bis Welle 3 war die Hardware-Seite **nicht prüfbar**: das G29 meldete sich am
PC, lieferte aber keine HID-Reports (`python tools/hid_probe.py 046d:c24f`:
auf allen drei Schnittstellen `report timeout … (no data)`) — der in der
README beschriebene „Netzteil fehlt“-Fall. In dieser Welle lieferte das Rad
zeitweise **echte Achsdaten und echte Motorkraft**. Damit wurden zwei Dinge
möglich und zwei Dinge sichtbar, die vorher niemand messen konnte.

## 2. Der Motor arbeitet — messbar, dreimal

Neues Werkzeug `tools/ffb_hw_probe.py` (misst die Achse **während** jeder
Phase; `--sign-check` vergleicht dagegen nur den Endstand mit der Ruhe, und
das ist bei einem Rad ohne Zentrierfeder irreführend, weil es dort stehen
bleibt, wo die Kraft es hingeschoben hat):

```text
python tools/ffb_hw_probe.py --seconds 2.0 --force 0.5
PHASE ruhe  gueltig=40/40  von=32767 bis=32526
PHASE plus  gueltig=21/40  von=32526 bis=26     delta=-32500
PHASE ruhe  gueltig=39/40  von=215   bis=1364   delta=+1149
PHASE minus gueltig=40/40  von=1364  bis=59525  delta=+58161
```

Zweite Messung (`--seconds 1.0`, andere Ausgangslage), dritte Messung
(`--seconds 2.5 --force 0.6`): `plus … delta=-32125`, `minus … delta=+63525`.
**Dreimal dasselbe Ergebnis:** eine positive DirectInput-Kraft fährt die
Achse in Richtung ihres Minimums, eine negative in Richtung Maximum.

## 3. Der Motor arbeitet **nicht immer** — dieselbe Messung, 6 Minuten später

```text
python tools/ffb_hw_probe.py --seconds 3.0 --force 0.6
PHASE ruhe  gueltig=60/60  von=32767 bis=32767 delta=+0
PHASE plus  gueltig=60/60  von=32767 bis=32767 delta=+0
PHASE minus gueltig=60/60  von=32767 bis=32935 delta=+168
HW_PROBE FAIL: die Kraft bewegt das Lenkrad nicht (plus +0, minus +168) - Netzteil? Rad festgehalten?
```

Parallel dazu, im selben Zeitfenster, das Spiel (`tests/probe_axis_read.gd`,
Fensterlauf, weil headless keine Joysticks aufgezählt werden):

```text
AXIS_READ t=1 a0=+0.000 a1=+0.000 a2=+0.000 a3=+0.000 data=false
AXIS_READ t=4 a0=+0.000 a1=+1.000 a2=+0.000 a3=+0.000 data=true
```

Und in einem anderen Lauf meldet das Spiel als Ruhepositionen
`rest gas=1.00 brake=0.00 clutch=0.00` — eine Woche vorher (17.09.) waren es
`gas=0.00 brake=0.00 clutch=1.00`. Die Achsen, auf denen Godot die Pedale
sieht, **wandern also zwischen Läufen**.

**Urteil:** Das G29 ist in diesem Zustand nicht verlässlich — mal liefert es
Kraft und Achsen, mal nur ein Rinnsal von Reports. Das ist ein Hardware-/
Versorgungszustand (Netzteil, USB-Kabel/-Port, Pedalkabel), kein Fehler der
Kette: alles, was die Software tun kann, ist getan und gemessen. Solange das
Rad so unzuverlässig ist, ist jede „Fühlt sich das echt an?“-Aussage nichts
wert, weil die Kraft mal da ist und mal nicht.

## 4. Zwei echte Mängel in den Diagnosewerkzeugen (behoben)

Beide gefunden, weil der Richtungstest **anstatt** eines Ergebnisses nur
`FAIL das_lenkrad_bewegt_sich_ueberhaupt` meldete. Gemessen mit
`tools/ffb_bridge.err` (193 Bytes statt leer):

```text
  File "C:\Users\Mark", line 8
SyntaxError: leading zeros in decimal integer literals are not permitted …
```

### 4.1 Mangel: `tools/ffb_direction_check.ps1` startete den Helfer nie

`Start-Process -ArgumentList $ffbArgs` mit einem **Array** setzt die Teile
unquotiert zusammen; der Projektpfad enthält ein Leerzeichen
(`C:\Users\Mark Waldeis\…`), also startete Python mit `C:\Users\Mark` als
Skript. Der Helfer lief nie, es wurde nie eine Kraft gesendet — und der Test
meldete brav „das Lenkrad bewegt sich nicht“. Ein Fehlalarm, der wie ein
Hardware-Fehler aussieht. Dieselbe Falle war in `tools/ffb_live_check.ps1`
schon einmal gefunden und dort behoben worden; der Richtungstest hatte den
Fix nie bekommen.

**Behoben:** ein einziger, selbst gequoteter Argument-String
(`-u "<pfad>\g29_ffb.py" --verbose --gain 1.0`), genau wie in
`ffb_live_check.ps1`. Zweite Messung: der Helfer startet
(`G29 Driving Force Racing Wheel bereit, Effekte: const, damper, friction,
spring, rumble`) und sieht die Pakete des Spiels.

### 4.2 Mangel: Der Prüflauf schrieb das Lenkrad-Profil des Fahrers neu

`tests/probe_ffb_steer.gd` kann nicht headless laufen (headless zählt Godot
keine Joysticks auf), der Headless-Schutz in `save_profile()` greift dort also
nicht. Beleg aus dem Godot-Log `logs/godot2026-09-21T18.12.20.log`, mitten im
Richtungstest:

```text
G29 profile rest for clutch corrected: 0.00 -> 1.00
G29 data arrived: rest gas=0.00 brake=0.00 clutch=1.00 steer=0.00
G29 profile saved: { … "throttle_rest": 0.0, "throttle_press": -1.88, … }
```

Der Fahrer hatte seine Pedale von Hand kalibriert; ein Diagnoselauf, der die
Pedale nicht anfasst, hat diese Werte überschrieben (und die Steuerwerte
`steer_axis/rest/span/invert` unverändert gelassen). Das ist derselbe
Fundtyp wie der Welle-3-Mangel „ein Prüflauf hatte dem Fahrer das FFB
abgeschaltet“, nur eine Ebene tiefer.

**Behoben, vier Schichten:**

1. `scripts/g29_input.gd`: `APEX_G29_PROFILE` verlegt den Profilpfad (in
   `_init()` **und** `_ready()`, damit auch ein Skript, das die Klasse nur
   instanziiert, den Pfad sieht).
2. `tests/probe_ffb_steer.gd` und `tests/probe_axis_read.gd` setzen die
   Variable selbst — der Schutz greift auch, wenn jemand den Probe direkt
   startet.
3. `tools/ffb_direction_check.ps1` setzt sie zusätzlich von außen.
4. `tests/test_g29_profile_path.gd` (neu, 6 Prüfungen) hält es fest: ohne
   Variable bleibt der echte Pfad, mit Variable landet das Schreiben in der
   Diagnosedatei, das echte Profil bleibt **inhaltlich und im Zeitstempel**
   unberührt.

### 4.3 Mangel: Der Prüflauf ließ den Helfer stehen

`$ErrorActionPreference = 'Stop'` brach das Skript beim ersten Fehler des
Prüflaufs ab — **vor** dem `Stop-Process` des Helfers. Das Lenkrad blieb
exklusiv belegt und der nächste Lauf hätte ins Leere gemessen. **Behoben:**
der Helfer und ein hängender Godot-Prüflauf werden in `finally` aufgeräumt,
der Prüflauf hat ein Zeitlimit, und sein Output steht in
`tools/ffb_direction_probe.log`.

## 5. Der eine Punkt, der offen bleibt — und warum

Die Kette liefert Kraft bis zum DirectInput-Aufruf (Welle 1–3) und der Motor
dreht das Rad (Abschnitt 2). **Welche Richtung „rechts“ ist, ist damit aber
noch nicht bewiesen.**

Was feststeht:

* Positive DirectInput-Kraft fährt die Achse zum **Minimum** (dreimal
  gemessen, Abschnitt 2).
* Das Spiel definiert „rechts = +1“ aus seiner Kalibrierung
  (`steer_invert: false`, `steer_span: +0.5547` — der Fahrer hat „ganz nach
  rechts“ gezeigt, die Godot-Achse wurde dabei positiv). Das ist die
  **SDL**-Seite.
* Ob die **DirectInput**-Achse dieselbe Polarität hat wie die SDL-Achse, ist
  von außen nicht sichtbar — und in genau diesem Zustand lieferte das Rad
  Godot kaum Achsdaten (Abschnitt 3), sodass der Richtungstest, der genau das
  messen würde, kein verwertbares Ergebnis bekam.

Hätte die DirectInput-Achse dieselbe Polarität wie die SDL-Achse (der
Normalfall für dasselbe HID-Achse), dann bedeutet „positive Kraft → Achse
Minimum“ = **das Rad dreht nach links**, während das Modell mit positivem
`torque` nach rechts drücken will. Dann müsste im Menü
**„Kraftrichtung: umgekehrt“** stehen (`ffb_settings.invert = true`, wirkt
über `ffb_model.gd` und ist getestet) oder der Helfer mit `--invert` laufen.

**Der Test, der das in 5 Sekunden entscheidet** (Lenkrad frei, Hände weg):

```text
tools\ffb_direction_check.ps1        # startet den Helfer selbst; das Rad dreht 2x3 s
```

Und wenn Godot dabei keine Achsdaten sieht (Abschnitt 3), bleibt der Fühltest:

```text
"Apex Circuit FFB starten.cmd" --demo    # im Bogen: drückt das Rad in die Kurve oder heraus?
```

Meldet er `FFB_STEER ERGEBNIS: positive Kraft dreht nach LINKS`, dann
`Esc → Einstellungen → Force Feedback → Kraftrichtung` auf **umgekehrt**
stellen. Meldet er `… nach RECHTS`, bleibt alles wie es ist. Der Test ist
jetzt in Ordnung (Abschnitt 4) — er braucht nur ein Rad, das zuverlässig
Achsdaten liefert.

## 6. Was diese Welle am Spiel verbessert hat

| Datei | Änderung | Beleg |
|---|---|---|
| `tools/ffb_direction_check.ps1` | Helfer startet überhaupt (Quoting), Aufräumen in `finally`, Zeitlimit, Protokolldatei, Profilschutz | `ffb_bridge.err` leer, Helfer meldet „bereit“; Abschnitt 4.1/4.3 |
| `godot_f1/scripts/g29_input.gd` | `APEX_G29_PROFILE` verlegt den Profilpfad, in `_init()` und `_ready()` | `tests/test_g29_profile_path.gd` (6 Prüfungen) |
| `godot_f1/tests/probe_ffb_steer.gd` | setzt den Profilpfad selbst; misst zusätzlich den **Rohwert** der Achse je Phase (vorher war „bewegt sich nicht“ nicht von „Kraft liegt nicht an“ zu unterscheiden) | Ausgabe `Mittelwert Lenkung … (Achse …)` |
| `godot_f1/tests/probe_axis_read.gd` | **neu**: reine Achsenmessung für den Vergleich „mit/ohne Helfer“ | Abschnitt 3 |
| `tools/ffb_hw_probe.py` | **neu**: Kraft und Achse je Phase, plus Urteil `PASS`/`ANDERS`/`FAIL`/`TEILWEISE` | Abschnitt 2/3 |
| `godot_f1/scripts/ffb_model.gd` | NAN-/INF-Härtung (aus der Welle-4-Agentenarbeit): ein einzelner NAN-Tick blieb in der Glättung hängen und vergiftete jeden weiteren Tick | `tests/test_ffb_edge.gd` (6 Prüfungen) |
| `godot_f1/tests/test_ffb_edge.gd` | **neu** (aus dem Agenten-Probe hervorgegangen): 600 Ticks mit NAN/INF/widersprüchlichen Eingaben, dazu Anschlag + Kerb + Einschlag gleichzeitig | 6 Prüfungen PASS |

## 7. Gegenproben dieses Turns (alle grün)

| Prüfung | Ergebnis |
|---|---|
| alle 16 Testdateien in `godot_f1/tests/` | alle PASS, 0 FAIL |
| `tests/test_ffb_model.gd` | 34 Prüfungen PASS (nach der NAN-Härtung unverändert) |
| `tests/test_ffb_settings.gd` | 32 Prüfungen PASS |
| `tests/test_ffb_link.gd` | 18 Prüfungen PASS |
| `tests/test_g29_profile_path.gd` | 6 Prüfungen PASS |
| `tests/test_ffb_edge.gd` | 6 Prüfungen PASS |
| `python tools/g29_ffb.py --check` | 12 Prüfungen, 0 Mängel |
| `tools/ffb_end_to_end.ps1` (Spiel gegen echten Helfer) | 10 Prüfungen, 0 Mängel; Kraftspitze 0,584, Rütteln 0,700 @ 42,2 Hz, Schalter AN/AUS wirkt |
| `tools/ship_check.ps1` (ausgelieferter Build) | 3 Prüfungen, 0 Mängel |

## 8. Offen (ehrlich)

1. **Hardware-Zuverlässigkeit**: Das Rad liefert nur zeitweise Achsdaten und
   Motorkraft (Abschnitt 3). Netzteil, USB-Kabel/-Port und Pedalkabel prüfen;
   danach `python tools/hid_probe.py 046d:c24f` — kommen laufend Reports,
   ist es in Ordnung.
2. **Kraftrichtung**: braucht ein zuverlässig meldendes Rad und 5 Sekunden
   (Abschnitt 5).
3. **Fühltest**: `tools/g29_ffb.py --demo` bzw. eine Runde im Spiel — das ist
   die einzige Aussage, die Software nicht treffen kann.
