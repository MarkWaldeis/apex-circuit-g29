# Welle 11: die echte Runde - was das Lenkrad im Spiel wirklich bekommt

Stand 21.09.2026, Commit `7c28fc9` (Sonde), Zahlen nachgezogen.

Sonde: `godot_f1/tests/probe_lap_ffb.gd`
Prufung fuer den Fund: `godot_f1/tests/test_stuck_rejoin.gd`
Messprotokoll: `tools/testlogs/wave11_lap.log`

## Warum diese Welle

Bis hierher stammten fast alle Zahlen der Soll-Tabelle aus **synthetischen**
Szenarien: das Modell wurde direkt mit einem `ctx` gefuettert ("Bogen:
lateral_g = 3,2"). Das beweist, dass `ffb_model.gd` rechnen kann - aber nicht,
dass diese Situation im Spiel **vorkommt** und dass dort dieselben Werte
herauskommen. Diese Sonde faehrt deshalb das **echte Spielerauto auf der echten
Strecke** (dieselbe Physik, dieselben Kerbs, dieselbe Ideallinie, dieselben
Schaltvorgaenge) und liest jeden Physik-Tick genau die Zahlen, die
`ffb_link.gd` an `tools/g29_ffb.py` schickt.

```cmd
powershell -File tools/run_godot.ps1 --fixed-fps 300 --headless ^
    --path godot_f1 --script tests/probe_lap_ffb.gd
```

`--fixed-fps` laesst Godot die Physik schneller als in Echtzeit rechnen; der
Physik-Schritt bleibt 1/60 s. Sechs Abschnitte:

| Abschnitt | Was passiert | Ausgangslage |
|---|---|---|
| A | reale Runde mit dem Autopiloten | Startaufstellung |
| B1 | beschleunigen auf der Linie | nach A |
| D | **Untersteuern**: Vollgas und voller Lenkeinschlag bei 252 km/h | auf die Linie gesetzt, 70 m/s angestossen |
| E | **Uebersteuern**: Vollgas im langsamen Bogen, Traktionskontrolle aus | auf die Linie gesetzt, 18 m/s |
| B2 | **Blockieren**: Vollbremsung mit Lenkeinschlag | auf die Linie gesetzt, 70 m/s |
| B3 | ausrollen | nach B2 |
| C | **weit hinaus**: Kerb, Kies, Wandkontakt | auf die Linie gesetzt, 45 m/s |

Nur die **Ausgangslage** der Abschnitte D, E, B2 und C ist gestellt (zurueck auf
die Linie, angestossen). Was danach gemessen wird, ist echte Physik auf der
echten Strecke, kein gestelltes `ctx`.

## Fund 1: das Auto blieb im Kies liegen - 45 Sekunden lang

Der erste Lauf dieser Sonde ergab:

```text
LAP_FFB Oberflaechen { "Asphalt": 2960, "Kerb": 4, "Kies": 3726 }
LAP_FFB Abschnitt A  Querabstand max=13.89 m Mittel=7.57 m Tempo max=283 km/h
LAP_FFB Spur f=3150  Tempo=1 km/h    Abstand=13.84 m  Kies
LAP_FFB Spur f=3600  Tempo=0 km/h    Abstand=13.86 m  Kies
LAP_FFB Spur f=4050  Tempo=0 km/h    Abstand=13.86 m  Kies
... bis f=5400 (Ende der Messung)
```

KI-Auto **und** Autopilot des Spielerautos fahren nach rund 46 s einmal weit
hinaus - und bleiben liegen: 13,9 m Querabstand, 0 km/h, **45 s lang**. Die
Ideallinie, auf die der Autopilot zielt, liegt hinter der Bande (15,5 m). Gas
geben heisst dort: in die Wand fahren. Der bestehende Rundentest
`test_lap_drive.gd` sah das nie, weil er nach **40 s** endet - der Ausflug
passiert bei Sekunde 46.

### Behoben in `scripts/car_controller.gd`

`_watch_stuck(delta)`: Ein Auto, das **autonom** faehrt (`is_ai` oder
`auto_drive`) und mehr als `STUCK_OFFSET` = 8 m quer neben der Linie steht,
wird zurueckgesetzt - nach **2,5 s** Stillstand (`STUCK_SPEED` = 2 m/s) oder
spaetestens nach **8 s**, wenn es zwar faehrt, aber draussen bleibt. Ein Fahrer
am Lenkrad wird **nie** angefasst: er entscheidet selbst, ob er rueckwaerts
faehrt oder den Reset benutzt.

Dabei zaehlt **Fortschritt**: kommt das Auto von allein mindestens einen halben
Meter naeher an die Strecke, beginnt die Uhr von vorn. Ein Auto, das sich
gerade zurueckarbeitet, wird also nicht mitten in der Bewegung auf die Linie
gesetzt (in der Messung: ein Auto, das in Schritten von 14,0 m auf 8,4 m
zurueckkam, wurde **nicht** umgesetzt; dasselbe Auto, das anschliessend knapp
ausserhalb der Grenze stehen blieb, wurde nach 2,5 s geholt).

Nachgemessen mit derselben Sonde:

```text
vorher:  Kies 3726 Ticks, laengste Standphase 45,0 s, Wiedereingliederungen 0
nachher: Kies  965 Ticks, laengste Standphase  2,6 s, Wiedereingliederungen 5
         Rundenfortschritt 1439 von 1440 Punkten (vollstaendige Runde)
```

Und mit einem Test, der beide Seiten prueft (`test_stuck_rejoin.gd`, 8
Pruefungen, in der Suite):

```text
STUCK platziert: KI 14.50 m (Nase zur Wand), Autopilot 6.00 m (am Rand)
PASS das_ki_auto_wird_zurueckgeholt 1 Wiedereingliederung(en)
PASS das_ki_auto_steht_wieder_auf_der_strecke Abstand=0.00 m
PASS kein_sofortiges_umsetzen_am_streckenrand 0 Wiedereingliederung(en) in 4 s
PASS das_ki_auto_faehrt_wieder_weiter 35.98 m/s
PASS der_fahrer_wird_nie_umgesetzt 0 Wiedereingliederung(en)
PASS der_fahrer_steht_noch_wo_er_war 14.01 m statt 12.00 m
PASS wer_sich_selbst_naehert_wird_nicht_umgesetzt 0 Wiedereingliederung(en)
PASS auch_knapp_ausserhalb_wird_geholt 1 Wiedereingliederung(en) bei 0.00 m
STUCK_REJOIN PASS
```

## Fund 2: Fehler in meiner eigenen Messung

Der erste Bericht zeigte "Bogen n=0" und "Untersteuern n=0". Ursache war nicht
das Spiel, sondern die Sonde: sie las `ctx["lat_g"]`, den Schluessel gibt es
nicht - die Querlast steht unter `lateral_g`. Mit dem falschen Schluessel war
jede Querlast 0.

Drei weitere Stellen wurden nachgeschaerft, weil sie sonst etwas behauptet
haetten, das sie nicht gemessen haben:

* `model.torque` ist mit `invert = true` die **umgedrehte** Groesse fuer das
  G29. Die Aussage "drueckt gegen den Lenkbefehl" gilt vor dieser Umdrehung.
* "Geradeaus schnell" zaehlte zuerst auch Ticks mit Wandkontakt aus spaeteren
  Abschnitten mit (Ruetteln 0,700 auf der Geraden). Jetzt zaehlt nur, was die
  Asphalt-Textur als lauteste Quelle hat: Ruetteln max **0,131**.
* "Blockiertes Rad" zaehlte zuerst jedes Ruetteln mit, auch Kerb (0,844 @ 39
  Hz). Jetzt getrennt: Quelle "Blockiert" = **0,700 @ 29-34 Hz**.

## Fund 3: mein Uebersteuer-Test war falsch angesetzt

Nachdem Abschnitt E (Vollgas im langsamen Bogen, Traktionskontrolle aus)
**282 Uebersteuer-Ticks** lieferte, forderte mein erster Test fuer **jeden**
dieser Ticks, dass die Kraft in die Gegenlenkrichtung dreht. Ergebnis: 66 von
282 - und der Test schlug fehl. Der Fehler lag im Test, nicht im Modell: die
Soll-Tabelle nennt die Umdrehung fuer den Moment, in dem der **Schlupfwinkel
der Vorderraeder durch die Null** dreht. Solange das nicht passiert ist,
drueckt die Vorderachse weiter gegen den Lenkbefehl - das ist die Kraft, mit
der man den Wagen ueberhaupt erst faengt.

Getrennt gezaehlt (dieselbe Messung, dieselben Ticks):

```text
Uebersteuern n=282  Kraft max 0,604
  Vorderachse durch die Null: n=67  davon dreht die Kraft mit: 64 (96 %)
  noch nicht durch         : n=215 davon drueckt sie gegen    : 213 (99 %)
```

Beide Aussagen sind jetzt einzeln geprueft, und die Zeile der Soll-Tabelle ist
damit **in echter Fahrt** belegt statt nur synthetisch.

## Die Soll-Tabelle in echter Fahrt

Vollstaendige Runde (1439/1440 Punkte), Spitze 283 km/h,
Standardeinstellungen (`Staerke 75 %`, `invert = true`, `400 Grad`):

| Soll (Plan §2) | In echter Fahrt gemessen | Bewertung |
|---|---|---|
| Geradeaus schnell: ruhig, Grundgewicht | n=381 (nur Asphalt): Kraft max **0,031**, Daempfung min **0,244**, Ruetteln max **0,131** @ 22-42 Hz | erfuellt |
| Bogen 3-4 g: schwer, gegen den Lenkbefehl | n=469 ab 3 g (Spitze 3,97 g): Kraft **Mittel 0,452**, **max 0,673**; **2390 von 2508** Bogen-Ticks druecken gegen den Lenkbefehl (95 %) | Richtung erfuellt, Haerte am unteren Rand (siehe unten) |
| Enger Bogen, Vorderachse am Limit: bricht ein | **Untersteuern** n=152: Kraft **Mittel 0,075** gegenueber 0,452 im Bogen = **83 % leichter** | erfuellt (Soll: 30-60 % leichter) |
| Heck bricht aus: Kraft dreht in die Gegenlenkrichtung | **Uebersteuern** n=282: mit Vorderachse durch die Null **64 von 67 (96 %)** gedreht, vorher **213 von 215 (99 %)** gegen den Lenkbefehl; durchdrehende Raeder 213 Ticks, Ruetteln max **0,833** | erfuellt, und zwar genau in dem Moment, den die Soll-Tabelle nennt |
| Vorderrad blockiert: leicht/tot + Rattern | n=262, Kraft max **0,215**; als lauteste Quelle **0,700 @ 29-34 Hz** (177 Ticks) | erfuellt |
| Kerb: hart und schnell | **0,795** @ 27-37 Hz (17 Ticks) | erfuellt (Soll 0,6-0,9) |
| Kies: grobes Mahlen | **0,399** @ 8-15 Hz (815 Ticks) | erfuellt (Soll 0,3-0,5; 9-14 Hz) |
| Asphalt: feine Textur | max **0,131** @ 22-42 Hz | Spitze 9 % ueber dem Soll-Band (0,05-0,12) |
| Schalten / Bodenwelle / Aufprall | 614 Pulse: Schalten 539, Aufprall 42, Bodenwelle 33 | erfuellt |
| Kein Clipping im Normalbetrieb | **0 von 6990** Ticks ueber 0,97 (Kraft max 0,673) | erfuellt |
| Am Lenkanschlag (Soft Lock) | **0 Ticks** - der Soft Lock braucht den Lenkdruck des Fahrers (`lock_pressure` kommt aus dem G29) | headless nicht messbar, nur im Fuehltest |
| Stillstand: keine Kraft | Abschnitte B3/C: Kraft 0,000-0,167 | erfuellt |

## Der Fund, der bleibt: die Bogenkraft haengt an der Staerke-Einstellung

Mit der Werkseinstellung **75 %** liegt der schnelle Bogen bei 0,452 (Mittel) /
0,673 (Spitze) - die Soll-Tabelle nennt 0,55-0,75. Dieselbe Sonde mit
`APEX_LAP_GAIN` (jedes Mal ein Lauf, gleiche Strecke, gleiche Fahrweise, gleiche
Abschnitte):

```text
Staerke  75 % (Werk): Bogen ab 3 g  Mittel 0,452  max 0,673   Gesamt max 0,673  Clipping 0
Staerke  85 %       : Bogen ab 3 g  Mittel 0,512  max 0,763   Gesamt max 0,763  Clipping 0
Staerke  90 %       : Bogen ab 3 g  Mittel 0,543  max 0,808   Gesamt max 0,808  Clipping 0
Staerke 100 %       : Bogen ab 3 g  Mittel 0,603  max 0,898   Gesamt max 0,898  Clipping 0
```

Damit ist der Regler keine Gefuehlsfrage mehr, sondern gemessen:

* **90 %** ist die kleinste **waehlbare** Stufe (`GAINS` in
  `ffb_settings.gd`: 30/45/60/75/90/100 %), die den Bogen an die Soll-Tabelle
  bringt: Mittel 0,543 (Soll 0,55-0,75), Spitze 0,808, und bis zum Deckel
  (SOFT_CEIL 0,90) bleibt Luft fuer Einschlaege.
* **85 %** waere der genauere Treffer (Spitze 0,763), ist im Menue aber nicht
  einstellbar - der Regler springt von 75 auf 90 %.
* **100 %** fuellt den Deckel aus (0,898 von 0,90). Der Bogen ist dann am
  schwersten, aber ein Einschlag hat kaum noch Platz, obwohl er weiterhin nicht
  gekappt wird (0 Clipping-Ticks).
* **75 %** (Werkseinstellung) ist bewusst die zahmere Wahl: die Spitze bleibt
  bei 0,673, also rund 10 % unter dem Soll-Band.

Das ist die Entscheidung aus Welle 2 ("Kopfraum fuer Einschlaege": Grundkraft
0,93 liess den Einschlag verschwinden). **Wenn sich der Bogen zu leicht
anfuehlt: `Staerke` im Menue auf 90 % - gemessen 0,543 statt 0,452 im Mittel,
ohne Clipping. Noch mehr Kraft gibt 100 % (0,603), dann aber ohne Kopfraum.**

## Was diese Welle nicht beweist

* **Fuenf Abschnitte, ein Lauf, eine Fahrweise.** Wiederholungen koennen
  streuen; die Zahlen sind Momentaufnahmen einer Messung, nicht Mittelwerte.
* **Kerb und Kies** wurden in der Runde selbst kaum beruehrt (4 Ticks Kerb in
  5400); die belastbaren Kerb-/Kies-Zahlen stammen aus den Abschnitten B2 und
  C, die absichtlich hinausfahren.
* **Untersteuern** (Abschnitt D) und **Uebersteuern** (Abschnitt E) sind mit
  gestellter Ausgangslage gemessen (252 km/h bzw. 18 m/s auf der Linie),
  danach echte Physik. Kein Fahrer hat das Auto absichtlich dorthin getrieben,
  und die Traktionskontrolle war in Abschnitt E **aus** - im Spiel ist sie
  standardmaessig an (`spin` wird dann mit 0,25 gerechnet, das Ausbrechen ist
  also seltener und leiser).
* **Soft Lock** und **Stillstand ohne Motor** brauchen den Lenkdruck des
  Fahrers bzw. einen Fensterstart - headless nicht messbar.
* Ueber das **Gefuehl** sagt keine Zahl etwas. Das bleibt der Fahrtest am
  eigenen Lenkrad (`Apex Circuit FFB starten.cmd` bzw. `--demo`).
