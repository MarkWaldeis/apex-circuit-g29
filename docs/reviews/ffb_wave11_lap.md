# Welle 11: die echte Runde - was das Lenkrad im Spiel wirklich bekommt

Stand 21.09.2026. Sonde: `godot_f1/tests/probe_lap_ffb.gd`
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

Drei Abschnitte: **A** reale Runde mit dem Autopiloten, **B** Vollbremsung aus
hoher Geschwindigkeit mit Lenkeinschlag (blockierende Vorderraeder), **C**
absichtlich weit hinaus (Kerb, Kies, Wand).

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
hinaus - und bleiben liegen: 13,9 m Querabstand, 0 km/h, **45 s lang**, bis die
Messung abgebrochen wird. Ursache: die Ideallinie, auf die der Autopilot zielt,
liegt hinter der Bande (15,5 m). Gas geben heisst dort: in die Wand fahren. Der
bestehende Rundentest `test_lap_drive.gd` sah das nie, weil er nach **40 s**
endet - der Ausflug passiert bei Sekunde 46.

### Behoben in `scripts/car_controller.gd`

`_watch_stuck(delta)`: Ein Auto, das **autonom** faehrt (`is_ai` oder
`auto_drive`) und mehr als `STUCK_OFFSET` = 8 m quer neben der Linie steht,
wird zurueckgesetzt - nach **2,5 s** Stillstand (`STUCK_SPEED` = 2 m/s) oder
spaetestens nach **8 s**, wenn es zwar faehrt, aber draussen bleibt. Ein Fahrer
am Lenkrad wird **nie** angefasst: er entscheidet selbst, ob er rueckwaerts
fahert oder den Reset benutzt.

Nachgemessen mit derselben Sonde:

```text
vorher:  Kies 3726 Ticks, laengste Standphase 45,0 s, Wiedereingliederungen 0
nachher: Kies  840 Ticks, laengste Standphase  2,6 s, Wiedereingliederungen 2
         Rundenfortschritt 1439 von 1440 Punkten (vollstaendige Runde)
```

Und mit einem Test, der beide Seiten prueft (`test_stuck_rejoin.gd`):

```text
STUCK platziert: KI 14.50 m (Nase zur Wand), Autopilot 6.00 m (am Rand)
PASS das_ki_auto_wird_zurueckgeholt 1 Wiedereingliederung(en)
PASS das_ki_auto_steht_wieder_auf_der_strecke Abstand=0.00 m
PASS kein_sofortiges_umsetzen_am_streckenrand 0 Wiedereingliederung(en) in 4 s
PASS das_ki_auto_faehrt_wieder_weiter 35.98 m/s
PASS der_fahrer_wird_nie_umgesetzt 0 Wiedereingliederung(en)
PASS der_fahrer_steht_noch_wo_er_war 14.01 m statt 12.00 m
STUCK_REJOIN PASS
```

## Fund 2: ein Fehler in meiner eigenen Messung

Der erste Bericht zeigte "Bogen n=0" und "Untersteuern n=0". Ursache war nicht
das Spiel, sondern die Sonde: sie las `ctx["lat_g"]`, den Schluessel gibt es
nicht - die Querlast steht unter `lateral_g`. Mit dem falschen Schluessel war
jede Querlast 0. Das ist genau die Art Fehler, die eine Messung gruen und
inhaltslos macht; er steht hier, weil er in dieser Welle passiert ist.

Ebenfalls korrigiert: `model.torque` ist mit `invert = true` die **umgedrehte**
Groesse fuer das G29. Die physikalische Aussage "drueckt gegen den Lenkbefehl"
gilt vor dieser Umdrehung; die Sonde rechnet sie zurueck.

## Die Soll-Tabelle in echter Fahrt

Alle Zahlen aus einem Lauf ueber eine vollstaendige Runde (1439/1440 Punkte,
Spitze 283 km/h), Standardeinstellungen (`Staerke 75 %`, `invert=true`,
`400 Grad`):

| Soll (Plan §2) | In echter Fahrt gemessen | Bewertung |
|---|---|---|
| Geradeaus schnell: ruhig, mit Grundgewicht | `torque` max **0,031** ab 198 km/h, Daempfung min **0,242**, Ruetteln max 0,356 | erfuellt |
| Bogen 3-4 g: schwer, gegen den Lenkbefehl | 407 Ticks ab 3 g: Kraft **Mittel 0,455**, **max 0,584**; **2300 von 2414** Bogen-Ticks druecken gegen den Lenkbefehl (95 %) | Richtung erfuellt, Haerte am unteren Rand (siehe unten) |
| Asphalt: feine Textur | Ruetteln max **0,131** @ 22-42 Hz | erfuellt (Soll 0,05-0,12; Spitze 9 % darueber) |
| Kerb: hart und schnell | **0,534** @ 21-27 Hz (35 Ticks) | erfuellt, aber nur bei 60-100 km/h beruehrt |
| Kies: grobes Mahlen | **0,273** @ 8-12 Hz (789 Ticks) | erfuellt, dumpf und langsam |
| Blockierende Vorderraeder: leicht + Rattern | 228 Ticks: Kraft **max 0,175**, Rattern **0,700 @ 29-34 Hz** | erfuellt: "leicht und tot" |
| Schalten: kurzer Anschlag | 421 Pulse, Schaltstoesse 0,45 | erfuellt |
| Kein Clipping im Normalbetrieb | **0 Ticks** ueber 0,97 (max 0,584) | erfuellt |
| Soft Lock | in dieser Fahrt nicht beruehrt (0 Ticks) | offen (Rangieren, nicht Rennfahrt) |
| Untersteuern: Kraft bricht ein | in dieser Fahrt kein Tick mit `understeer > 0,3` | offen - der Autopilot faehrt nicht ueber den Peak |

## Der Fund, der bleibt: die Bogenkraft haengt an der Staerke-Einstellung

Mit der Werkseinstellung **75 %** liegt der schnelle Bogen bei 0,455 (Mittel) /
0,584 (Spitze) - die Soll-Tabelle nennt 0,55-0,75. Dieselbe Sonde mit
`APEX_LAP_GAIN=1.0` gemessen (ein Lauf, gleiche Strecke):

```text
Staerke  75 %: Bogen ab 3 g  Kraft Mittel 0,455  max 0,584   Clipping-Ticks 0
Staerke 100 %: Bogen ab 3 g  Kraft Mittel 0,607  max 0,779   Clipping-Ticks 0
```

Mit **Staerke 100 %** liegt der Bogen also mitten in der Soll-Tabelle, und es
klebt trotzdem nichts am Anschlag (0 von 6690 Ticks ueber 0,97) - die weiche
Begrenzung (SOFT_KNEE 0,72 / SOFT_CEIL 0,90) greift. Das ist kein
Rechenfehler, sondern die Entscheidung "Kopfraum fuer Einschlaege": der Deckel
liegt bewusst unter der Anschlaggrenze, sonst verschluckt die Grundkraft den
Einschlag. **Der Regler im Menue ist damit die ehrliche Antwort auf "das
Lenkrad ist mir zu leicht": `Staerke` auf 100 %.**

## Was diese Welle nicht beweist

* **Eine** Runde, **eine** Fahrweise (Autopilot). Ein Fahrer am Limit fahrt
  spaeter, haerter und haeufiger ueber den Kerb.
* Kerb und Kies wurden nur bei 60-100 km/h beruehrt. Die Baender bei 120 km/h
  sind im Modell gemessen (`tests/test_ffb_model.gd`), in der Szene nicht.
* Untersteuern und Soft Lock kamen in dieser Fahrt nicht vor - sie sind weiter
  nur synthetisch (und im Fuehltest `--demo`) belegt.
* Ueber das **Gefuehl** sagt keine Zahl etwas. Das bleibt der Fahrtest am
  eigenen Lenkrad.
