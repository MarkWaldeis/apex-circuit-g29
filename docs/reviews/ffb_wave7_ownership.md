# Welle 7: Wem gehört das Lenkrad? — die Startreihenfolge war die Ursache

Prüfagent: Root (`/root/wave6_chain`), 21.09.2026, am **echten G29**.

Diese Welle hat nicht das Modell geprüft, sondern die einzige Annahme, die seit
Welle 4 nie belegt war: dass das G29 „unzuverlässig“ sei. Sie ist falsch. Der
Mangel lag in der Reihenfolge, in der sich Spiel und Helfer das Lenkrad
nehmen — und die Anleitung des Spiels gab genau die kaputte Reihenfolge vor.

## 1. Was bisher als Beweis galt

| Behauptung | Worauf sie sich stützte | Urteil |
|---|---|---|
| „Ohne Netzteil sendet das G29 nichts“ | `tools/hid_probe.py`: `report timeout … (no data)` auf allen drei HID-Schnittstellen | **widerlegt** |
| „Godot/SDL sieht die Achse nicht“ | `tests/probe_axis_read.gd`: `a0=0.000 … data=false` | **widerlegt** |
| „der Motor arbeitet, aber die Achse liefert nichts“ | `tools/ffb_hw_probe.py` (DirectInput) gegen HID | **halb richtig**: der Motor arbeitet *und* die Achse lebt |
| „die Kraftrichtung ist gemessen: positive Kraft dreht nach links“ | aus DirectInput + Kalibrierung **geschlossen** | jetzt **direkt gemessen**, siehe §5 |

## 2. Die Messung, die alles gedreht hat

`tools/hid_vs_dinput.py` (neu) liest beide Wege **gleichzeitig**: die rohe
HID-Schnittstelle `mi_00` in einem eigenen Thread und die Lenkachse über
DirectInput, während dieselbe Datei die Kraft setzt.

```text
Phase   DI gueltig                  DI-Spanne  HID-Reports
ruhe            66               32767..33102            1
plus            41                   1..33102          621
ruhe            64                   185..817          101
minus           66                 815..46158          998
aus             66               46865..50672          199
HID-Reports insgesamt: 1920 (erstes 00 08 00 00 00 4f 81 ff ff ff 80 80 94)
```

Damit war der erste Befund da: **der Rohpfad lebt.** `tools/hid_probe.py`
läuft nur deshalb in einen Timeout, weil es das Rad nicht bewegt — das G29
sendet nur bei Änderung. 1 920 Reports auf derselben Schnittstelle, auf der der
Einzelprüfer „kein Report“ meldete. Ein Timeout dort ist **kein** Beweis für
ein fehlendes Netzteil; die Datei sagt das jetzt selbst.

## 3. Die A/B-Messung: die Reihenfolge entscheidet

Gleiche Werkzeuge, gleiche Härte (`--force 0.5`, Rechteck alle 3 s), nur die
Startreihenfolge anders. Links die Soll-Kraft, in der Mitte die
DirectInput-Achse, rechts die Zahl der HID-Reports seit Beginn:

**A) Spiel zuerst, dann der Helfer — beides läuft.**

```text
  t=   1.0s Soll=+0.50 DI=    99 HID=479
  t=   5.0s Soll=-0.50 DI= 59910 HID=1520
  t=   9.0s Soll=-0.50 DI=     - HID=2650
  t=  13.0s Soll=+0.50 DI= 31609 HID=4273
  t=  18.1s Soll=+0.50 DI= 65535 HID=5902
  t=  23.1s Soll=-0.50 DI= 60970 HID=7891
```

Und das Spiel liest dieselbe Achse live mit (`tests/probe_axis_track.gd`, 30 s):

```text
AXIS_TRACK t=08 a0=-1.000 span=1.000 data=true
AXIS_TRACK t=12 a0=+0.996 span=1.996 data=true
AXIS_TRACK t=30 a0=+0.946 span=2.000 data=true
AXIS_TRACK Ende span=2.000 data=true
```

**B) Helfer zuerst, dann das Spiel — das Rad friert ein.**

```text
  t=   6.0s Soll=+0.50 DI= 65535 HID=1674
  t=   8.0s Soll=+0.50 DI= 32607 HID=2620
  t=   9.0s Soll=-0.50 DI= 32607 HID=2620  <-- Achse steht still
  t=  12.1s Soll=+0.50 DI= 32607 HID=2620  <-- Achse steht still
```

In derselben Sekunde, in der das Spiel das Rad öffnet, endet alles: keine
HID-Reports mehr, die DirectInput-Achse bleibt auf 32 607 stehen, und das Spiel
sieht `a0=-0.005 span=0.005 data=false`. Die Kraft kommt nicht mehr an, die
Lenkung auch nicht. **Beide Seiten sterben an derselben Ursache.**

Die Gegenprobe für den Umkehrschluss: SDL liest nicht grundsätzlich falsch,
sondern genau den eingefrorenen Wert. 32 607 im Bereich 0…65 535 sind
`+0.009` in Godots −1…+1 — im Protokoll stand `a0=+0.009`. Das Spiel hatte also
recht.

## 4. Was geändert wurde

1. **`tools/g29_ffb.py` wartet auf das Spiel** (`wait_for_game`, Standard
   `--wait-game -1` = warten, bis das Spiel sendet; `0` schaltet es ab). Das
   Spiel öffnet das Lenkrad beim Start über SDL, lange bevor das Auto das
   erste Paket schickt. „Warte auf das erste Paket“ ist deshalb eine sichere
   Sperre: wer wartet, kann nicht der Erste sein. **Das Paket, das den Helfer
   aus dem Warten holt, geht nicht verloren** (`carry`).
2. **`Apex Circuit FFB starten.cmd`** startet jetzt von sich aus erst das Spiel
   und dann die Kraft (`--nur-helfer` für „Spiel läuft schon“) und nennt die
   Reihenfolge als erste Fehlerursache. Vorher stand dort „Helfer läuft. Spiel
   starten und fahren.“ — genau die Reihenfolge, die das Spiel blind macht.
3. **`Lenkrad pruefen.cmd`** dreht das Rad jetzt mit Kraft und liest beide
   Wege (`tools/hid_vs_dinput.py`) statt nur zu warten; die Checkliste nennt
   die Reihenfolge zuerst und sagt ausdrücklich, dass ein „report timeout“ im
   Einzelprüfer nichts beweist.
4. **Die Hinweise im Spiel** (`g29_input.gd`, `hud.gd`, `menu.gd`,
   `ffb_link.gd`) nennen zuerst „Spiel neu starten“ und erst danach Netzteil
   und Kabel. Zwei Tests halten den Wortlaut fest
   (`test_input_mapping.gd`: `der_stille_lenkrad_hinweis_nennt_zuerst_die_startreihenfolge`,
   `test_ffb_settings.gd`: `der_stille_lenkrad_hinweis_nennt_zuerst_den_neustart`).
5. **`python tools/g29_ffb.py --check` prüft die Reihenfolge selbst**
   (`der_helfer_wartet_auf_das_spiel`, 16 Prüfungen) — mit Ersatz-Rad und
   Gegenprobe: mit `--wait-game 0` muss das Rad *vor* dem ersten Paket offen
   sein (`die_reihenfolgepruefung_kann_fehlschlagen`). Damit ist die Prüfung
   falsifizierbar, nicht nur grün.

## 5. Was jetzt am Lenkrad gemessen ist

`tools/ffb_direction_check.ps1` — der Test, der seit Welle 4 nie ein Ergebnis
hatte, weil er den Helfer zuerst startete:

```text
FFB_STEER device=Logitech G29 Driving Force Racing Wheel live=true
FFB_STEER phase=0 Ruhe (keine Kraft):        Mittelwert Lenkung +0.000 (Achse +0.000)
FFB_STEER phase=1 positive Kraft +0.35:      Mittelwert Lenkung -0.883 (Achse -0.786)
FFB_STEER phase=3 negative Kraft -0.35:      Mittelwert Lenkung -0.320 (Achse -0.246)
PASS das_lenkrad_bewegt_sich_ueberhaupt
PASS die_achse_folgt_der_kraft
FFB_STEER ERGEBNIS: positive Kraft dreht nach LINKS
```

Damit ist die Kraftrichtung **im Spiel, am echten Rad** entschieden und nicht
mehr aus zwei Einzelmessungen zusammengeschlossen: positiv („rechts“ im Modell)
kommt links an, `invert = true` ist richtig — der Wert, der seit Welle 5
ausgeliefert wird. Die Automatik im Spiel (`ffb_link.gd::measure_direction`)
kann jetzt ebenfalls laufen, weil sie Achsdaten bekommt.

## 6. Was offen bleibt

Der **Fühltest**: ob sich schwerer Bogen, leichtes Untersteuern, Kerb und
Anschlag am eigenen Rad richtig anfühlen, kann nur der Fahrer sagen:

```cmd
"Apex Circuit FFB starten.cmd"          :: startet Spiel + Kraft
"Apex Circuit FFB starten.cmd" --demo   :: nur das Rad, alle Fahrsituationen
```

Nicht geprüft (kein Zugriff): ob sich das Einfrieren aus §3 auch mit einem
anderen Rad (G920/G923) oder einem anderen DirectInput-Client reproduzieren
lässt. Der Warteschritt verhindert es unabhängig davon, weil der Helfer das Rad
nie zuerst öffnet.

## 7. Nachtrag: die Prüfwerkzeuge selbst hatten drei Mängel

Aufgefallen beim Nachfahren der Auslieferung — jeder einzelne hätte eine
**falsche** Aussage über das Spiel erzeugt bzw. die Auslieferung verhindert:

**7.1 `export_windows.cmd` brach mit einem kryptischen Fehler ab.**
Gemessen: `EXIT=1`, `Get-FileHash : Die Benennung "Get-FileHash" wurde nicht
als Name eines Cmdlet erkannt`. Ursache: das Skript startet Windows PowerShell
5.1, und der Aufrufer (hier ein PowerShell-7-Fenster) vererbt seinen
`PSModulePath`. In dem liegt der Modulordner der Codex-Laufzeit mit
`Microsoft.PowerShell.Utility` für .NET 7 — 5.1 scheitert daran und hat danach
kein `Get-FileHash` mehr. Der Export lief durch, die Auslieferung starb, und
zurück blieb eine **alte Desktop-Kopie**. Behoben: `export_windows.cmd` setzt
einen sauberen Modulpfad, `export_and_deliver.ps1` rechnet den SHA256 mit .NET
(keine Modulabhängigkeit) und meldet ein **laufendes Spiel** ausdrücklich als
Grund, statt eines nackten `Copy-Item: IOException`.

**7.2 Die Prüfung des ausgelieferten Builds konnte grundlos rot werden.**
Zweimal gemessen: `FAIL der Build kennt APEX_FFB_SETTINGS`, angeblich Reibung
0,050 bzw. 0,030 — bei einem Build, der in Wahrheit korrekt `Quelle=aus` mit
0,00/0,00 sandte. Zwei Ursachen, beide aus dem Protokoll belegt:

* Die **Ruhezeile** des Helfers trägt den *letzten* Paketzähler und dazu sein
  Ruhegewicht (`[idle] … damp=0.10 fric=0.05`). Die Prüfung las das als
  Messung. Gemessen am 21.09.2026, 20:22: `458 Pakete … damp=0.10 fric=0.05
  [idle]` → Fehlalarm.
* Die ersten Pakete sind **Übergang**: das Ruhegewicht klingt auf die Werte des
  Spiels ab. Gemessen, 20:13: bei 6 Paketen noch `damp=0.06 fric=0.03`, ab 127
  Paketen 0,00/0,00.

Behoben: Ruhezeilen zählen nicht, Zeilen unter 120 Paketen zählen nicht, ein
Lauf unter 300 Paketen wird wiederholt — und die Prüfung verlangt jetzt
zusätzlich `pakete ≥ 300`, damit ein Lauf, der nicht stattgefunden hat, nicht
als „0 = aus“ durchgeht. Zwei aufeinanderfolgende Läufe: **PASS 7 Prüfungen**.

**7.3 Zwei Läufe ließen Prozesse als Waisen zurück.** Gemessen: ein headless
`Apex Circuit.exe` (PID 17704, Elternprozess weg, gestartet 20:10:01) und ein
Helfer (`--port 5632`, gestartet 20:12:21). Folgen: die laufende `.exe` sperrt
ihre eigene Datei (→ 7.1), der alte Helfer hält das Lenkrad und seine Logdatei
(→ `Remove-Item: … wird von einem anderen Prozess verwendet`, bevor überhaupt
gemessen wurde). Behoben: beide Prüfskripte **räumen vor dem Messen auf**,
beenden Prozesse mit Nachkontrolle (`Wait-Process`, zweiter Versuch, laute
Meldung) und benutzen je Versuch einen **eigenen Logdateinamen**; `ship_check`
prüft am Ende ausdrücklich, dass kein Spielprozess stehen bleibt (7.
Prüfung).
