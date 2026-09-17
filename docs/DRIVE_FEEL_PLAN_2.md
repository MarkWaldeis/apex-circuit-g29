# Apex Circuit — Fahrgefühl-Paket, Welle 2 (verbindlicher Vertrag)

Welle 1 hat die Module *angelegt und verdrahtet*. Welle 2 macht sie **echt**:
heute ist `ideal_line.gd` noch die Mittellinie, `tyre_model.gd` ein
Rechengerüst, `gearbox.gd` noch die alten Platzhalter-Zahlen und `crash.gd`
erkennt nur grob. Diese Datei ist der Auftrag, den jeder Agent liest.

## Umgebung

* Projekt: `C:\Users\Mark Waldeis\Desktop\grok f1 try\godot_f1`
* Godot: `C:\Users\Mark Waldeis\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe`
  (im PATH auch als `godot`)
* Testlauf (immer aus `godot_f1`):

  ```
  godot --headless --path . --script tests/test_car_orientation.gd
  godot --headless --path . --script tests/test_gameplay_input.gd
  godot --headless --path . --script tests/test_lap_drive.gd   # ~45 s Laufzeit
  ```

* Streckenphysik (aus `blender/scripts/05_build_track.py`, **nicht raten**):
  Fahrbahn 12,0 m breit (halbe Breite 6,0), Kerb 0,85 m (6,00…6,85),
  Runoff 10,0 m (6,85…16,85), Barriere bei 16,0 m Offset, 1,15 m hoch.
* Vorzeichen: `racing_line.offset_at()` ist **positiv, wenn das Auto links der
  Fahrtrichtung** der Linie steht. `racing_line.left_at()` zeigt nach links.
* Godot 4.7, GodotPhysics3D, 90 Physik-Ticks/s.

## Harte Leitplanken

1. **Die drei Bestandstests bleiben grün:**
   `test_car_orientation` (Räder/Ausrichtung), `test_gameplay_input`
   (Gas → > 40 km/h nach 2,2 s, Bremse halbiert die Geschwindigkeit in 1,33 s,
   rechts lenken dreht nach rechts), `test_lap_drive` (Spieler fährt vorwärts,
   KI > 200 Punkte Fortschritt in 26,7 s, **KI bleibt < 10 m von der
   Mittellinie**, niemand fällt unter y = −4 m).
2. **Schnittstellen sind eingefroren** (`docs/DRIVE_FEEL_PLAN.md`, Abschnitt
   „Schnittstellen“). Erweitern ja, Signatur ändern nein.
3. **Nur eigene Dateien anfassen.** Braucht ein Agent eine Änderung in einer
   Root-Datei (`car_controller.gd`, `main.gd`, `menu.gd`, `track_loader.gd`,
   `cockpit_camera.gd`, `tyre_model.gd`, `racing_line.gd` Basis), schickt er
   dem Root eine Nachricht mit Datei, Zeile, Vorschlag — und editiert nicht.
4. **Kein `git`-Schreibbefehl, kein Export.** Macht der Root nach der Abnahme.
5. **Jede Behauptung braucht eine Messung.** Ein Modul gilt erst als fertig,
   wenn ein Headless-Test in der echten Szene (`scenes/main.tscn`) Zahlen
   liefert, nicht nur „Node existiert“. Screenshots über das Muster
   `tests/capture_cockpit.gd` (Viewport-Capture) sind für Sichtbares Pflicht.

## Missionsübersicht Welle 2

| Mission | Datei-Eigentum | Ziel in einem Satz |
|---|---|---|
| CRASH-2 | `surfaces.gd`, `crash.gd`, `barriers.gd`, `wheel_feedback.gd`, `hud.gd`, `tests/test_crash_surfaces.gd` | Von der Strecke fliegen kostet echt Zeit, Wandkontakt ist ein Crash mit Schaden und Rückmeldung |
| LINE-2 | `ideal_line.gd`, `racing_line_display.gd`, `tests/test_racing_line.gd`, `racing_line.gd` (nur neue Funktionen) | Eine echte Ideallinie mit Scheitelpunkt-Anfahren, Brems-/Gasphasen und farbiger Anzeige auf der Fahrbahn |
| GEARBOX-2 | `gearbox.gd`, `drivetrain.gd`, `tests/test_gearbox.gd` | 8-Gang-Sequenzgetriebe mit Drehmomentkurve, Schaltzeit, Motorbremse, Runterschalt-Schutz |
| ROOT-2 | `tyre_model.gd`, `car_controller.gd`, `main.gd`, `cockpit_camera.gd`, `menu.gd`, `racing_line.gd` (Basis) | Kurvenverhalten wie in der Formel 1: Abtrieb, Grip-Abfall, Gewichtsverlagerung, Traktion, Fahrhilfen |

## CRASH-2 — Strecke verlassen, einschlagen, fühlen

**Ziel:** Wer neben die Strecke fährt, verliert dort spürbar Zeit und
Rückmeldung; wer in die Mauer fährt, hat einen Crash mit Schaden, Tempo- und
Richtungsverlust — das Auto fährt **nie** durch die Barriere.

Messbar:

* Gras/Kies: Rundenzeit-Verlust messbar — Test beschleunigt aus dem Stand auf
  Asphalt und auf Gras und vergleicht die erreichte Geschwindigkeit nach 3 s
  und die Längsverzögerung beim Rollen.
* Kerb: `sample().rumble` > 0,5 auf dem Kerb, 0 auf Asphalt; eine Rückmeldung
  (`wheel_feedback.strength`) reagiert auf den Kerb.
* Wand: Auto 15 m vor einer Barriere auf die Wand ausgerichtet, Vollgas →
  `crash.crash_count >= 1`, `crash.damage > 0`, Endposition **nicht** jenseits
  des Barriere-Offsets (16 m), Längsgeschwindigkeit eingebrochen.
* Streifschuss bleibt billig: flacher Winkel (unter 15 Grad) entlang der Wand →
  hoechstens ein Crash-Ereignis, Schaden < 0,3.
* HUD zeigt Streckenzustand (Asphalt/Kerb/Kies/Gras), Schaden und einen
  Crash-Hinweis; bei Schaden > 0,6 faehrt das Auto spuerbar langsamer
  (`car_controller` liest `crash.damage` schon).

Dateien: `scripts/surfaces.gd`, `scripts/crash.gd`, `scripts/barriers.gd`,
`scripts/wheel_feedback.gd`, `scripts/hud.gd`, `tests/test_crash_surfaces.gd`.

## LINE-2 — Die Ideallinie

**Ziel:** Die angezeigte Linie ist **nicht** die Mittellinie, sondern die
Linie, mit der man am schnellsten um den Kurs kommt: sie fährt die Kurven von
außen an, clipst den Scheitel innen und läuft auf der Geraden wieder nach
außen. Jeder Punkt trägt eine Phase: grün = Gas, gelb = lupfen, rot = bremsen.

Messbar:

* **Kurvigkeit:** über den ganzen Kurs ist `max|k_ideal| < max|k_mitte|` und
  auch der Mittelwert von `|k|` ist auf der Ideallinie kleiner — die Linie ist
  ruhiger als die Mittellinie.
* **Scheitel:** in einer bekannten Kurve (Index der stärksten Krümmung) hat die
  Ideallinie ein Offset **zur Kurveninnenseite** von mindestens 2,5 m, und auf
  der folgenden Geraden geht das Offset wieder gegen 0. Das Offset bleibt
  immer innerhalb ± 5,5 m (Fahrbahn + Kerb).
* **Geschwindigkeit:** `target_speed[i] <= sqrt(a_lat / |k_i|) + Toleranz` für
  jeden Punkt; das Bremsprofil hält `v[i]^2 <= v[i+1]^2 + 2 * a_brems * ds`;
  vor der Haarnadel liegt `target_speed` deutlich unter der
  Geradengeschwindigkeit.
* **Phasen:** vor jeder Kurve mit `|k| > 0,02` gibt es ein zusammenhaengendes
  rotes Band von mindestens 25 m, nach dem Scheitel grün; auf der
  Start-Ziel-Geraden ist alles grün.
* **Anzeige:** `racing_line_display.build()` zeichnet die Ideallinie (nicht die
  Mittellinie), liegt auf dem Asphalt (max. 0,3 m seitlich daneben), 4 bis 8 cm
  über der Fahrbahn, und bleibt in der Cockpit-Ansicht sichtbar (Screenshot).

Dateien: `scripts/ideal_line.gd`, `scripts/racing_line_display.gd`,
`tests/test_racing_line.gd`, `scripts/racing_line.gd` (nur neue Hilfen,
Basisfunktionen gehören dem Root).

## GEARBOX-2 — Schalten wie in der Formel 1

**Ziel:** Acht Gänge, sequenziell, mit Drehmomentkurve, Schaltpausen,
Motorbremse und Schutz vor Drehzahlschäden. Der Fahrer schaltet mit den
Paddles — das Getriebe schaltet ihm **nicht** dazwischen.

Messbar:

* Hochschalten: Drehzahl fällt, Geschwindigkeit steigt, die Zugkraft ist für
  `SHIFT_TIME` (rund 0,05 s) unterbrochen und danach wieder positiv.
* Runterschalten: Drehzahl steigt; würde die Drehzahl über den Begrenzer
  laufen, wird der Schaltwunsch **abgelehnt** — messbar über
  `request_shift(false) == false` bei gültig bleibender Drehzahl.
* `rpm` bleibt zwischen Leerlauf und Begrenzer; über dem Begrenzer fällt die
  Kraft hart ab; der Gang wird nie kleiner als 1 oder größer als 8.
* Automatik (KI, `auto: true`) schaltet nur sinnvoll: hoch nur mit Gas und ohne
  Schaltpause, runter erst unter rund 60 % der Hochschalt-Drehzahl. Im
  manuellen Modus (`auto: false`) schaltet sie **nie** von selbst.
* Fahrleistung: Höchstgeschwindigkeit in Gang 8 auf der Geraden über 250 km/h,
  0–100 km/h unter 3,5 s (Formel-1-Größenordnung, kein Straßenauto).
* Test: `tests/test_gearbox.gd` fährt die Szene headless, misst Gang, Drehzahl
  und Zugkraft über die Zeit und prüft die Punkte oben.

Dateien: `scripts/gearbox.gd`, `scripts/drivetrain.gd`, `tests/test_gearbox.gd`.
`car_controller.gd` liest `engine_force`, `rpm`, `gear`, `shift_event` — die
Rückgabe bleibt genau so.

## ROOT-2 — Kurven fahren wie in der Formel 1

**Ziel:** Das Auto fährt sich wie ein Formel-1-Auto: Abtrieb wächst mit v^2, in
schnellen Kurven liegt es, in engen Kurven verliert es Grip, zu viel Gas in der
Kurve schiebt das Heck, zu hartes Einlenken schiebt über die Vorderachse,
Bremsen verlagert Gewicht nach vorn (sichtbar im Cockpit), und die Fahrhilfen
am `F`-Knopf machen es für Einsteiger fahrbar.

Messbar:

* Querbeschleunigung in einer schnellen Kurve bei Höchsttempo: 3,5 bis 5,5 g.
* Höchstgeschwindigkeit auf der Geraden 300 bis 340 km/h, 0–100 km/h unter
  3,5 s, 0–200 km/h unter 7 s.
* Bremsweg aus 200 km/h auf Asphalt 60 bis 120 m; auf Gras deutlich länger.
* Untersteuern nimmt mit Lenkwinkel und Tempo zu (`tyres.front_grip` unter
  `tyres.rear_grip` bei großem Lenkwinkel und hohem Tempo).
* Fahrhilfen am `F`-Knopf: an = stabil, aus = übersteuernd/rutschend.
* Cockpit: Nick- und Wankbewegung sichtbar, Kamera bleibt ruhig genug
  (`tests/probe_framing.gd` / `probe_cockpit_metrics.gd` bleiben grün).

Dateien: `scripts/tyre_model.gd`, `scripts/car_controller.gd`, `scripts/main.gd`,
`scripts/cockpit_camera.gd`, `scripts/menu.gd`, `scripts/racing_line.gd` (Basis).

## Kritische Prüfung (Welle 3)

Ein Prüf-Agent sucht Fehler, nicht Bestätigung. Er liest den Code, fährt die
Szene headless mit **eigenen** Messungen (nicht den Tests des Autors), prüft die
Leitplanken, vergleicht gegen die Formel-1-Realität und gegen die drei
Bestandstests, und schreibt reproduzierbare Mängel auf. Ein Punkt gilt erst als
fertig, wenn der Prüfer **100 % zufrieden** ist — auch nach der Nachbesserung.

Prüfer-Regeln:

* Kein „sieht gut aus“ — jede Aussage mit Zahl, Datei und Zeile.
* Mindestens drei eigene Gegenproben pro Mission, inklusive einer, die
  versucht, das Gegenteil zu beweisen.
* Wenn ein Mangel nicht reproduzierbar ist, wird er als solcher gemeldet.
