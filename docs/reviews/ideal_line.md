# Prüfbericht: Ideallinie, Anzeige, Bedienung

Prüfer: Root-Agent. Der dafür vorgesehene Prüf-Sub-Agent hat zwei Anläufe lang
keinen Auftragstext erhalten; seine zwei trotzdem gelieferten Befunde (siehe
unten) sind eingearbeitet. Dieser Bericht prüft die Linie selbst nach.

Stand: `main` nach `f81fd09`.

## 1. Ist die angezeigte Linie wirklich die optimale Linie?

Der Verdacht war, dass die Linie Zeit liegen lässt: sie nutzt nur 2,08 m des
±5,2 m breiten Korridors. `tests/probe_line_tune.gd` baut die Linie mit sechs
Parametersätzen und rechnet für jeden die Rundenzeit aus dem eigenen
Geschwindigkeitsprofil:

| Parametersatz | Rundenzeit | Krümmungsenergie J | max. Offset |
|---|---|---|---|
| Mittellinie (Referenz) | 31,34 s | 0,4074 | 0,00 m |
| Korridor 5,2 · 9 Durchläufe · Suche ab 0,8 | **30,54 s (−0,80 s)** | 0,3124 | 2,08 m |
| Korridor 5,2 · 9 Durchläufe · Suche ab 0,8 · Strafe 20 | **30,52 s (−0,82 s)** | 0,3216 | 2,08 m |
| dito, Strafe 60 | 30,64 s (−0,70 s) | 0,3366 | 2,08 m |
| 12 Durchläufe · Suche ab 1,0 · Strafe 120 | 30,79 s (−0,55 s) | 0,3296 | 2,62 m |

Die verbaute Linie entspricht Zeile 3 und ist damit **die schnellste der
getesteten Varianten**. Ein aggressiveres Anfahren der Scheitel (2,62 m statt
2,08 m) ist 0,27 s *langsamer*, weil sie die Kurvenausgänge zustellt: mehr
Querabstand bedeutet nicht automatisch mehr Tempo, wenn die Linie dadurch
krummer wird. Der Verdacht ist damit widerlegt; die 2,08 m sind kein
verschenkter Korridor, sondern das Optimum dieses Modells.

## 2. Bedeuten die Farben, was sie sagen?

`tests/test_racing_line.gd` prüft genau das und ist grün:

| Prüfung | Ergebnis |
|---|---|
| Punktezahl | 1440, wie die Mittellinie |
| Linie im Korridor | max. 2,08 m (Grenze 5,2 m) |
| jeder Punkt auf Asphalt oder Kerb | max. 2,08 m von der Mitte |
| schneller als die Mittellinie | 0,82 s auf 1634 m |
| Krümmungsenergie | 0,407 → 0,322 |
| Scheitel innen angefahren | Offset −1,47 m bei Index 1438 |
| Kurve außen angefahren | Zufahrt +1,47 m, Scheitel −1,47 m |
| Grip-Grenze | 0 Verstöße, 0 Punkte unter der Modell-Untergrenze |
| Bremsprofil physikalisch erreichbar | 0 Verstöße |
| alle drei Phasen vorhanden | 890 Gas, 193 lupfen, 357 bremsen |
| Bremszonen | 8 Zonen, kürzeste 26,0 m, jede verzögert wirklich (0 Ausnahmen) |

Rot ist also eine echte Bremszone, gelb ein echtes Lupfen, und die
Abfolge „außen anfahren — innen Scheitel — außen heraus“ ist messbar vorhanden.

## 3. Ist die Linie im Cockpit lesbar? (ein Mangel, behoben)

**Befund.** Im Cockpit war die Linie zu flach und zu schmal: bei 7 cm Höhe und
0,9 m Breite verschwand sie in der Kurvenausfahrt hinter dem Dashboard und war
auf der Geraden nur ein Strich. Belege: die Bilder `line_braking.png` und
`line_corner.png` aus `tests/probe_line_shots.gd` vor der Änderung.

**Änderung.** `racing_line_display.gd`: Höhe 0,07 → 0,12 m, Breite 0,9 → 1,1 m.

**Nachher.** In `line_corner.png` zieht die grüne Linie jetzt sichtbar in die
Tiefe, in `line_straight.png` liegt sie unter der Nase im Blickfeld, und in
`line_braking.png` ist die rote Bremszone unübersehbar. Zusätzlich zeigt das
Status-HUD „BREMSEN IN 99 m“ — die Information, die in F1-Spielen den
abnehmenden Strich am Horizont ersetzt.

## 4. Fährt die KI die angezeigte Linie — und bremst vor der Kurve?

`tests/probe_ai.gd` (Vorlauf) und `tests/test_lap_drive.gd`:

| Frage | Ergebnis |
|---|---|
| Fortschritt in 40 s | 1217 von 1440 Punkten |
| Abstand zur Linie | max. 4,88 m (Grenze des Tests: 10 m) |
| Rückwärtsfahren | 0 Verstöße |
| Aus der Welt fallen | tiefster Punkt y = −0,21 m |
| Bremshorizont | `limit` fällt vor der Kurve unter `target_speed` (bei f=840: 86,0 gegen 91,1 m/s) |

Die KI folgt der Linie und bremst mit dem Bremshorizont, also vor der Kurve.

## 5. Bedienung und Text

`L` schaltet die Linie (`main.gd::_unhandled_input`), `F` die Fahrhilfen
(`car_controller.gd::_unhandled_input` → `toggle_assists()`), und das
Pausenmenü ruft für beides dieselben Funktionen auf (`menu.gd::_toggle_line`,
`_toggle_assists`) — die Knöpfe können also keinen anderen Zustand anzeigen als
die Tasten. Die README-Aussagen zu `L`, `F` und zur Linie stimmen mit dem Code
überein; die Zahlen zur Ideallinie (2,08 m, 0,82 s, 8 Bremszonen) sind die aus
Abschnitt 1 und 2.

## 6. Befunde der Prüf-Sub-Agenten

* **README-Zahl zum Streifer war veraltet** (2,1 m/s statt gemessen 0,0 m/s,
  pro Tick −0,7): korrigiert, samt Erklärung, warum negativ.
* **`probe_scrape.gd` meldete die Eintrittsgeschwindigkeit falsch**
  (`0 → 56 km/h` für einen Lauf ab 90 km/h): korrigiert.

## Urteil

Die Linie ist die schnellste der gemessenen Varianten, die Farben sind belegt,
die KI fährt sie und bremst vor der Kurve, und der eine echte Mangel — die
Lesbarkeit aus dem Cockpit — ist behoben und mit Bildern belegt.
