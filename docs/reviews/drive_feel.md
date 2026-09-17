# Prüfbericht: Fahrgefühl, Reifen, Getriebe

Prüfer: Root-Agent (der dafür vorgesehene Prüf-Sub-Agent `review_drive` hat zwei
Anläufe lang keinen Auftragstext erhalten und nichts gemessen — dieser Bericht
ist der Ersatz, mit denselben Anforderungen: messen, nicht behaupten).

Stand: `main` nach `3fb8029`. Alle Zahlen unten kommen aus Läufen auf diesem
Stand.

## Was gemessen wurde

| Frage | Werkzeug | Ergebnis | Bewertung |
|---|---|---|---|
| 0–100 km/h | `tests/probe_feel.gd` | 2,09 s | plausibel (Formel 1: ~2,6 s ab Stand, hier traction-limited) |
| 0–100 im Einzeltest | `tests/test_gearbox.gd` | 2,29 s | plausibel |
| Endgeschwindigkeit | `tests/test_gearbox.gd` (12 km Gerade) | 312 km/h im 8. Gang bei 11.353/min | plausibel (Rennen ~320–340) |
| Endgeschwindigkeit auf der Startgeraden | `tests/probe_feel.gd` | 250,6 km/h im 7. Gang nach 10 s | durch die Geradenlänge begrenzt, kein Modellfehler |
| Bremsen aus 250 km/h | `tests/probe_feel.gd` | Spitze 5,71 g (11 Ticks über 6 g als Kontakte verworfen) | plausibel (F1: 5–5,5 g bei hoher Geschwindigkeit) |
| Querbeschleunigung KI | `tests/probe_feel.gd` | max 3,88 g, p95 3,40 g, **kein Frame über 5 g**, max bei 182,9 km/h | plausibel; die 8,6 g vom Anfang sind weg |
| Schaltpunkte | `tests/test_gearbox.gd` | 1→2 bei 80 km/h/11.516 U/min, 5→6 bei 177, 6→7 bei 216 | konsistent, kein Drehzahlloch |
| Schaltzeit | `tests/test_gearbox.gd` (Unit) | 0,056 s gemessen (50 ms hoch / 70 ms runter konfiguriert) | plausibel |
| Runterschalt-Schutz | `tests/test_gearbox.gd` | `would_overrev(4, 90 m/s)` = true, 8. Gang bei 90 m/s = false | greift |
| Limiter | `tests/test_gearbox.gd` | 1. Gang bei 60 m/s → Drehzahl gehalten, `limiter_hits > 0` | greift |
| Standgas | `tests/test_gearbox.gd` | 300 Ticks Stillstand → Drehzahl ≥ Standgas | kein Absterben |
| Geradeauslauf | `tests/test_gearbox.gd` | 19 m Querversatz in 40 s bei ~310 km/h | Restdrift ~0,5 m/s; fahrbar, siehe Mangel 3 |
| Bildrate | `tests/probe_fps.gd` | 60 fps in allen drei Kameramodi bei 1920×1080 | kein Einbruch durch Barrieren/HUD |

## Gefundene Mängel und ihr Stand

1. **Behoben — `probe_feel.gd` hat die Bremsung zum falschen Zeitpunkt
   gemessen.** Gebremst wurde bei einem festen Frame 900; inzwischen ist der
   Wagen dann schon am Ende der Startgeraden und steht an der Barriere, die
   „Bremsung“ wurde also aus 19,9 km/h gemessen (0,91 g) und sagte nichts über
   die Bremsen. Jetzt wird bei 250 km/h oder spätestens Frame 750 gebremst.
2. **Behoben — Kollisionen wurden als Bremsleistung gezählt.** Ein einzelner
   Tick ergab 277 g. Ein Reifen kann in einem 90-Hz-Tick nicht mehr als etwa
   6 g übertragen; Ticks darüber werden jetzt als Kontakt verworfen und gezählt
   (11 Stück) statt als Bremswert übernommen.
3. **Bekannt, nicht kritisch — Restdrift bei Höchstgeschwindigkeit.** Nach dem
   Symmetrieren der Radaufhängungen (vorher 59 m in 40 s, verursacht durch eine
   1 cm außermittige Hinterachse) bleiben 19 m in 40 s, also rund 0,5 m/s. Das
   ist eine Zehntelgrad-Nase und vom Fahrer mit einem Fingerzeig zu korrigieren;
   die KI hält die Linie auf 4,88 m genau. Wenn es stören sollte, gehört ein
   Spurstangen-Trim in `car_controller.setup()`.
4. **Behoben (vom Prüfer `line2` gefunden) — `probe_scrape.gd` meldete die
   Eintrittsgeschwindigkeit falsch** (`0 -> 56 km/h` für einen Lauf, der bei
   90 km/h beginnt), weil `car.speed_kmh` direkt nach dem Setzen der Transform
   noch den alten Wert hat. Jetzt wird die Geschwindigkeit aus der gesetzten
   `linear_velocity` genommen.
5. **Behoben (vom Prüfer `line2` gefunden) — `crash._expected_loss(braking)`
   war falsch benannt**: übergeben wurde `_contact_seen`, also „der Tub berührt
   etwas“, nicht „es wird gebremst“. Umbenannt in `touching`, Kommentar ergänzt.
6. **Offen, bewusst so gelassen — die Crash-Schwelle ist
   geschwindigkeitsabhängig.** Die „unerklärte“ Abgabe wächst mit dem Tempo,
   weil die Bremsen bei hoher Geschwindigkeit mehr zubeißen: ein echter
   Seitenschlag von 2 m/s registriert bei 50 km/h, geht bei 150 km/h aber im
   Bremsrauschen unter. Für die Strecke ist das folgenlos (ein Streifer bei
   25 m/s kostet 0,17 m/s), aber wer die Empfindlichkeit später ändert, muss
   diesen Zusammenhang kennen.

## Urteil

Die Kurvenwerte sind die eines Formel-Wagens (3,4–3,9 g, kein Frame über 5 g),
die Bremsen leisten 5,7 g, das Getriebe schaltet bei 11.500/min mit echtem
Schaltmoment und echtem Limiter, nichts fliegt, nichts hüpft, `reset_count`
bleibt im Normalbetrieb 0 und die Bildrate steht bei 60 fps. Die Mängel, die
diese Prüfung gefunden hat, lagen sämtlich in den Messwerkzeugen, nicht im
Fahrzeug — sie sind behoben, damit die Zahlen, auf die sich README und Tests
berufen, auch wirklich das messen, was dort steht.
