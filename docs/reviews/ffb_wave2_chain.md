# Prüfbericht Welle 2: Kette Spiel → Helfer → Lenkrad

Prüfer: fremder Agent (`wave2_chain`), nicht der Autor der Dateien.
Auftrag: nachsehen, ob das, was Welle 1 als „behoben" abgelegt hat, auch
wirklich hält — und ob der Test, der es absichern soll, überhaupt fehlschlagen
**kann**. Alle Zahlen unten stammen aus Läufen dieses Turns.

Stand: `docs/FFB_F1_STYLE_PLAN.md`, `docs/reviews/ffb_chain_review.md` (Welle 1).

---

## 1. Gefundene Mängel

| Nr. | Mangel | Messung | Status |
|---|---|---|---|
| 1 | **Der Kettentest konnte die Kraft nicht verlieren.** `tests/test_ffb_link.gd` prüfte `max_force > 0.02`. | Der Testlauf brachte **0,163** — und zwar, weil der Wagen die ganzen 3,6 s **geradeaus** fuhr: `car.auto_drive` war aus, `car.steering = 0.18` (Zeile 75) war wirkungslos, weil der Autopilot `steering` in seinem eigenen `_physics_process` schreibt und den Wert sofort überschreibt. Die Schwelle von 0,02 hätte auch einen auf 2 % zusammengebrochenen Kanal bestanden. | behoben |
| 2 | **`max_rumble >= 0.0` kann nie fehlschlagen** — ein toter Rüttel-Kanal wäre durchgegangen. | tautologisch (jeder Wert ist ≥ 0). | behoben |
| 3 | **`packet_carries_the_force_unchanged` war zufallsabhängig.** Es verglich das auf 0,001 geschnittene Paketfeld mit dem ungeschnittenen Modellwert über `is_equal_approx` (Toleranz 1e-5). | Es bestand nur, weil der Wert zufällig genau 0,000 war; im echten Fahrtlauf schlug es fehl, obwohl Paket und Modell auf drei Stellen gleich waren: **Paket 0,044 = Modell 0,044**. | behoben |
| 4 | **Der Schaltstoss wurde ausgelöst, aber nie geprüft.** Der Test rief `car.ffb.poke("shift", 0.6)` — und keine einzige Prüfung sah im Paket nach einem Puls. Kriterium 7 des Plans war auf der Kette damit ungeprüft. | — | behoben |
| 5 | **`event` und `speed` waren im Helfer blinde Passagiere.** Welle 1 hatte das für `source`, `clip`, `damage` behoben und diese zwei Felder übersehen: `tools/g29_ffb.py` las sie nie. | Code las `event`/`speed` an keiner Stelle. | behoben |
| 6 | **Die Herkunftsprüfung war zu schwach:** `sources.size() >= 1` ist mit dem Platzhalter `"-"` immer wahr. | — | behoben |
| 7 | **Doku gegen Code.** Plan §2 nannte `SOFT_KNEE` 0,78 / `SOFT_CEIL` 0,94, der Code rechnet mit **0,72 / 0,90**; Plan §3.4 versprach „Angriff ~5 ms für Stöße, Release ~150 ms", gemessen sind **25 ms** (`TORQUE_RISE` 40/s) und **125 ms** (`TORQUE_FALL` 8/s) — nur der Puls umgeht die Rampe. Dazu veraltete Zahlen in §7. | | behoben (Plan nachgezogen) |

### 1.1 Was Mangel 1 und 3 über den alten Test sagen

Der Test war grün, weil er **nichts** gemessen hat: kein Lenkwinkel, keine
Kurve, kein Beweis für „das Lenkrad wird im Bogen schwer". Genau das ist die
eine Aussage, um die es im Auftrag geht. Ein Test, der nur „es kommen Pakete
an" zeigt, sichert die Kette, aber nicht das Fahrgefühl.

---

## 2. Was ich selbst geändert habe

`godot_f1/tests/test_ffb_link.gd`

* `RUN_FRAMES = 1260` (14 s): der Autopilot fährt, bis er die schnellen Bögen
  erreicht (der erste liegt bei rund 430 m — mit den alten 3,6 s war der Wagen
  noch auf der Startgeraden).
* `car.auto_drive = true` statt `script_throttle`, damit der Wagen wirklich
  lenkt; die wirkungslose Zeile `car.steering = 0.18` ist ersetzt und im
  Kommentar erklärt.
* Neue Messgrößen: Kraftspitze, „Kraft gegen den Lenkbefehl", Puls, Ereignis,
  echte Quellen. Am Ende eine Messzeile `FFB_KETTE …`.
* Neue/scharfe Prüfungen: `the_wheel_gets_heavy_in_the_corner` (Schwelle 0,30),
  `the_force_pulls_against_the_steering` (≥ 80 % der Ticks gegen den
  Lenkbefehl), `rumble_channel_available` (0,03 statt „≥ 0"), `a_jolt_reaches_the_wheel`
  (Puls ≥ 0,30), `the_packet_names_the_event` („shift" steht im Paket),
  `the_packet_says_where_the_force_comes_from` (echte Quelle statt `"-"`),
  `packet_carries_the_force_unchanged` mit der halben Schnittstellenbreite
  (0,0006) statt 1e-5.

`tools/g29_ffb.py`

* Der Helfer liest `event` und `speed`, schreibt sie in seinen Bericht
  (`events`, `last_event`, `peak_speed`, `last_speed`) und zeigt sie an:
  `--dry-run` druckt „Ereignisse {'shift': 174} bei bis 180 km/h", `--verbose`
  im Betrieb „Ereignis=shift Tempo=180km/h".
* `--check` prüft das mit (neue Prüfung `ereignis_und_tempo_kommen_an`,
  jetzt **10 Prüfungen, 0 Mängel**).

---

## 3. Messungen dieses Turns

| Prüfung | Werkzeug | Ergebnis |
|---|---|---|
| Kette, echter Fahrtlauf | `tests/test_ffb_link.gd` | **839 Pakete in 14,0 s = 59,9 Hz**, 0 kaputt, v2-Schlüssel vollständig |
| Kraft im Bogen | derselbe Lauf | Spitze **0,577** über 293 Ticks (Schwelle 0,30) |
| Kraft gegen den Lenkbefehl | derselbe Lauf | **291 von 293 Ticks = 99 %** (Plan fordert „zieht gegen den Lenkbefehl") |
| Stoss | derselbe Lauf | Puls **0,60** in 55 von 839 Paketen, Ereignis „shift" im Paket |
| Herkunft | derselbe Lauf | `["Asphalt", "Aufprall", "Blockiert"]` |
| Rütteln | derselbe Lauf | Spitze 0,495, 22,0 … 42,0 Hz |
| Wiederholbarkeit | zwei Läufe hintereinander | identisch: 0,577 / 291:293 / 0,60 / 839 Pakete |
| Rampe, Puls, Loslassen, kaputte Pakete, Stärke genau einmal | `python tools/g29_ffb.py --check` | **10 Prüfungen, 0 Mängel** |
| Ereignis/Tempo | `--dry-run` mit synthetischem Sender | `Ereignisse {'shift': 174} bei bis 180 km/h` |
| Bestand | alle 15 Testdateien | **alle PASS** (u. a. `FFB_MODEL 27`, `FFB_SETTINGS 21`, `REVIEW_ROOT 18`) |

### 3.1 Nicht widerlegen konnte ich

* 60 Hz Sendetakt auch im echten Fahrtlauf (59,9 gemessen).
* Die Trennung „`torque` = Grundkraft, Stoss nur auf `pulse`" — im Modell
  (`einschlag_laesst_die_grundkraft_unveraendert`) und in der Kette
  (`grundkraft_und_stoss_kommen_getrennt`: 0,40 + 0,40 → 0,680).
* `gain` im Paket bleibt neutral (1,0 im ganzen Lauf): die Stärke wirkt genau
  einmal, im Modell.
* Kein Wert außerhalb der Grenzen in 839 Paketen, keine kaputten Pakete.
* Der Helfer lässt nach 0,5 s ohne Paket los (0,000 an der Geräte-Sonde).

---

## 4. Was weiterhin NICHT geprüft ist (ehrlich)

**Die Kraft am eigenen Lenkrad.** Das G29 meldet sich am PC an, liefert aber
keine HID-Reports (`python tools/hid_probe.py 046d:c24f`: auf allen drei
Schnittstellen `report timeout … (no data)`) — der Fall, den die README
beschreibt: **Netzteil nicht angeschlossen**. Belegt ist damit alles bis zum
DirectInput-Aufruf; nicht belegt ist, dass sich das Lenkrad wirklich so
anfühlt wie im offiziellen Spiel. Dafür gibt es den Fühltest:

```
"Apex Circuit FFB starten.cmd" --demo     # alle Fahrsituationen am Rad
tools/ffb_direction_check.ps1             # Kraftrichtung nachmessen
```

**Zwei Läufe gleichzeitig.** Ein zweiter Lauf auf Port 5611 scheitert mit
`FFB FAIL port_busy 5611` (richtig so — vorher war es ein „SKIP" mit Exit 0).
Parallele Läufe müssen `APEX_FFB_PORT` setzen; genau das war die Ursache eines
Fehlalarms in diesem Turn (der Test hielt den Port eines anderen Laufes).
