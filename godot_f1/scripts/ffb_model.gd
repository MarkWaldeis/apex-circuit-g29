extends RefCounted
## Was der Fahrer am Lenkrad fuehlt - als reine Rechnung.
##
## Das offizielle F1-Spiel (F1 24/25) gibt dem Lenkrad ein Signal, das aus der
## Vorderachse kommt: dem Nachlauf (self-aligning torque) der Vorderreifen.
## Solange die Vorderraeder arbeiten, zieht das Lenkrad gegen den Lenkwinkel
## zurueck; geht die Vorderachse ueber den Peak, **bricht die Kraft ein** und
## das Lenkrad wird leicht - das ist die Untersteuer-Warnung. Uebersteuert das
## Heck, wandert der Schlupfwinkel durch die Null und die Kraft **dreht ihr
## Vorzeichen**: das Lenkrad zieht von selbst in die Gegenlenkrichtung.
## Dazu kommen die Koerper-Signale: Kerb, Gras/Kies, blockierende Vorderraeder,
## durchdrehende Raeder, Schaltstoesse, Einschlaege und der Lenkanschlag.
##
## Alles hier ist eine Funktion von `ctx` (Telemetrie des Autos) auf Zahlen fuer
## den Helfer `tools/g29_ffb.py`. Diese Datei ist die EINZIGE Quelle der
## Wahrheit: HUD, Kamera, Gamepad-Vibration und das echte Lenkrad lesen
## dieselben Zahlen. Nichts wird "verstaerkt", nichts erfunden - was hier
## ankommt, kommt aus der Physik (siehe docs/FFB_F1_STYLE_PLAN.md, Abschnitt 2).
##
## Vorzeichen: `torque` ist +, wenn die Kraft das Lenkrad nach RECHTS drueckt -
## dieselbe Welt wie `g29.steer` und der Lenkbefehl des Fahrers (+ = rechts).
##
## OWNER: ROOT (workstream "Lenkrad-Gefuehl").

const Tyre := preload("res://scripts/tyre_model.gd")
const Settings := preload("res://scripts/ffb_settings.gd")

## Ab hier traegt der Reifen: unterhalb rollt er nur, ohne Seitenkraft.
const SPEED_FULL := 9.0
## 300 km/h, die Referenzgeschwindigkeit fuer das Aero-Gewicht.
const V_REF := 83.3
## Querlast, ab der die Vorderachse als voll belastet gilt (g).
const LOAD_REF_G := 3.5
## Abtrieb, ab dem der Fluegel voll zusaetzlich drueckt (Faktor ueber 1.0).
const AERO_REF := 2.5
## Schlupfwinkel, ab dem die Kraft ihre volle Richtung hat. Darunter wird sie
## weich eingeblendet, damit das Vorzeichen bei fast geradem Rad nicht
## hin und her springt (ein Zahnradantrieb macht daraus sonst Zappeln).
const SLIP_DIR_REF := 0.030
## Wie stark der Anschlag (Soft Lock) gegendrueckt.
const ENDSTOP := 0.95
## Ein G29/Zahnradlenkrad liefert rund 2-3 Nm; ein echter Formel-1-Wagen
## arbeitet in einer ganz anderen Liga. Die Zahl steht hier, damit die
## Diagnose ehrlich sagen kann, was ein echtes Auto an dieser Stelle haette.
const WHEEL_MAX_NM := 2.4
const F1_REF_NM := 25.0
## Zeitkonstante der Glattung. Kurz genug fuer einen Schlag, lang genug, dass
## der Zahnradantrieb nicht zappelt (F1 24: "itching to oscillate"). Gemessen:
## bei 90 Hz bleibt der groesste Sprung zwischen zwei Ticks unter 0.13.
const SMOOTH_TAU := 0.045
## Wie stark ein blockierendes Vorderrad (Bremsen + Lenken) den Nachlauf
## wegnehmen. 0.82 heisst: ein blockierendes Vorderrad laesst knapp ein
## Fuenftel der Bogenkraft uebrig - das Lenkrad wird leicht und tot, aber
## nicht ganz kraftlos (gemessen in tests/test_ffb_model.gd).
const LOCK_COLLAPSE := 0.82
## Wie lange ein Puls (Schalten, Einschlag) nachklingt.
const PULSE_DECAY := 5.0
## Ab hier gilt ein Tick als "am Anschlag" (Clipping-Anzeige fuer das HUD).
const CLIP_LEVEL := 0.97
## Weiche Begrenzung der Grundkraft. Unterhalb KNEE ist die Kraft unveraendert
## (die Mitte bleibt schwer), darueber wird sie gestaucht, damit die Spitze
## nicht flach an der 1,0 klebt. Genau das ist im Plan Kriterium 10: im
## Normalbetrieb darf nichts am Anschlag haengen, sonst wird das Lenkrad
## "heavy but dead" (Sim Racing Manual: Clipping = "lost feel, not extra
## strength"). Gegenprobe vorher: 4,5 g bei 90 m/s mit viel Abtrieb ergab
## |torque| = 1,000 - 12 von 375 Gitterpunkten klebten am Anschlag.
##
## Der Deckel liegt bewusst unter der Anschlaggrenze: die schnellste Kurve
## laesst ~14 % Kopfraum, sonst verschluckt sie den Einschlag (gemessen in
## Wellen 2: Grundkraft 0,93, Einschlag 1,00 - kaum zu spueren).
const SOFT_KNEE := 0.72
const SOFT_CEIL := 0.90
## Kruemmungsexponent der weichen Begrenzung, so gewaehlt, dass die Steigung am
## Knick genau 1.0 bleibt: SOFT_K = (1 - SOFT_KNEE) / (SOFT_CEIL - SOFT_KNEE)
## = 0.28 / 0.18. Die Kraft geht damit stufenlos und ohne Ruck in die Stauung
## ueber - kein Sprung, kein Knick, keine flache Spitze.
const SOFT_K := 1.5556
## Ein Einschlag ist nicht nur ein Stoss: das Lenkrad schuettelt kurz nach.
## Das ist der Unterschied zwischen "Kraft" und "Aufprall" - und er ist auch
## dann zu spueren, wenn die Grundkraft gerade hoch liegt.
const IMPACT_RUMBLE_DECAY := 3.0
## Ab diesem Schaden (0..1) ist das Rad nicht mehr rund: das Lenkrad bekommt
## eine Unwucht zu spueren, die mit dem Tempo schneller wird. Genau das macht
## das offizielle Spiel nach einem Platten oder einem harten Einschlag - die
## Kraft ist weg, das Ruetteln bleibt.
const FLAT_FROM := 0.05
## Schaden, ab dem die Unwucht voll anliegt.
const FLAT_FULL := 0.45

var settings
## Letzte Rechnung - alles, was HUD, Kamera und Tests lesen.
var torque: float = 0.0
var damper: float = 0.0
var friction: float = 0.0
var rumble: float = 0.0
var rumble_hz: float = 0.0
var pulse: float = 0.0
var pulse_dir: float = 0.0
var source: String = "-"
var clip: float = 0.0
## Diagnose der einzelnen Anteile (fuer probe_ffb und die Pruefagenten).
var sat: float = 0.0
var trail: float = 0.0
var lock: float = 0.0
var spin: float = 0.0
var flat: float = 0.0
var endstop: float = 0.0
var reference_nm: float = 0.0
var wheel_nm: float = 0.0
var last_ctx: Dictionary = {}

var _smooth_torque: float = 0.0
var _pulse: float = 0.0
var _pulse_dir: float = 0.0
var _pulse_kind: String = ""
var _impact: float = 0.0
## Kurzer, grober Schlag von einer Bodenwelle (gestauchte Feder). Eigener
## Kanal, damit eine Welle auch dann zu spueren ist, wenn gleichzeitig ein
## Schaltstoss den Puls-Kanal belegt - das staerkste Ereignis gewinnt dort.
var _bump: float = 0.0
var _clip_run: float = 0.0
var _events: Array = []

## Was ein Stoss ausgeloest hat, fuer die Quellen-Zeile im HUD und im Helfer.
const _SOURCE_NAMES := {
	"shift": "Schalten",
	"crash": "Aufprall",
	"contact": "Kontakt",
	"bump": "Bodenwelle",
	"kerb": "Kerbschlag",
}


func setup(ffb_settings = null) -> void:
	settings = ffb_settings
	if settings == null:
		settings = Settings.new()


## Einmaliges Ereignis (Schalten, Einschlag, Kerbschlag). `direction` ist in
## der Lenkradwelt (+ = rechts); 0 heisst "gegen den Lenkbefehl".
func poke(kind: String, severity: float, direction: float = 0.0) -> void:
	var s: float = clampf(_safe(severity, 0.0), 0.0, 1.0)
	if s <= 0.0:
		return
	direction = clampf(_safe(direction, 0.0), -1.0, 1.0)
	_events.append(kind)
	if s > _pulse:
		_pulse = s
		_pulse_dir = direction
		_pulse_kind = kind
	if kind == "crash" or kind == "contact":
		# Kontakt schuettelt nach: das ist der Teil, den man auch dann merkt,
		# wenn die Grundkraft gerade am Deckel liegt.
		_impact = maxf(_impact, s)
	elif kind == "bump":
		_bump = maxf(_bump, s)


func take_events() -> Array:
	var out: Array = _events
	_events = []
	return out


func update(delta: float, ctx: Dictionary) -> Dictionary:
	last_ctx = ctx
	var on: bool = settings == null or bool(settings.enabled)
	var gain: float = 1.0 if settings == null else clampf(_safe(settings.gain, 1.0), 0.0, 1.0)
	var effects_on: bool = settings == null or bool(settings.effects)
	# Die drei Ruettel-Baender des offiziellen Spiels (On Track = Asphalt-
	# Textur, Rumble Strip = Kerb, Off Track = Gras/Kies). Standard 100 %.
	var band_ontrack: float = 1.0
	var band_kerb: float = 1.0
	var band_offtrack: float = 1.0
	if settings != null:
		band_ontrack = clampf(_safe(settings.ontrack_effects, 1.0), 0.0, 1.0)
		band_kerb = clampf(_safe(settings.kerb_effects, 1.0), 0.0, 1.0)
		band_offtrack = clampf(_safe(settings.offtrack_effects, 1.0), 0.0, 1.0)
	var damper_scale: float = 1.0 if settings == null else clampf(_safe(settings.damper, 1.0), 0.0, 1.0)

	# Jede Zahl kommt ueber `_num`: ein NAN oder unendlich aus der Physik darf
	# nicht bis ans Lenkrad durchlaufen. Ohne diese Zeilen blieb ein einziger
	# NAN-Tick fuer immer haengen (die Glaettung mittelt ihn weiter), das HUD
	# zeigte "nan" und der Helfer bekam ein Paket, das er nicht mehr deuten
	# kann. Gemessen in tests/probe_wave4_edge.gd.
	var speed: float = maxf(_num(ctx, "speed", 0.0), 0.0)
	var steer: float = clampf(_num(ctx, "steer", 0.0), -1.0, 1.0)
	var steer_angle: float = _num(ctx, "steer_angle", 0.0)
	var slip_front: float = _num(ctx, "slip_front", 0.0)
	var slip_rear: float = _num(ctx, "slip_rear", 0.0)
	var lat_g: float = _num(ctx, "lateral_g", 0.0)
	var downforce: float = maxf(_num(ctx, "downforce", 1.0), 0.5)
	var understeer: float = clampf(_num(ctx, "understeer", 0.0), 0.0, 1.0)
	var oversteer: float = clampf(_num(ctx, "oversteer", 0.0), 0.0, 1.0)
	var brake: float = clampf(_num(ctx, "brake", 0.0), 0.0, 1.0)
	var throttle: float = clampf(_num(ctx, "throttle", 0.0), 0.0, 1.0)
	var lock_pressure: float = clampf(_num(ctx, "lock_pressure", 0.0), 0.0, 1.0)
	var damage: float = clampf(_num(ctx, "damage", 0.0), 0.0, 1.0)
	## Senkrechte Last in g: 1.0 = Auto steht auf den Raedern, darunter hebt die
	## Vorderachse ab (Kuppe), darueber ist die Feder gestaucht (Bodenwelle).
	var vertical_g: float = clampf(_num(ctx, "vertical_g", 1.0), -1.0, 4.0)
	var surface: Dictionary = ctx.get("surface", {})
	var tc_on: bool = bool(ctx.get("traction_control", true))

	# Ein Reifen baut Seitenkraft erst mit rollendem Rad auf; darueber waechst
	# der Nachlauf mit der Last (Abtrieb) weiter. Beides zusammen ist die
	# Tempoabhaengigkeit: unten "das Rad dreht sich erst", oben der Fluegel.
	var rolling: float = clampf(speed / SPEED_FULL, 0.0, 1.0) \
		* (0.55 + 0.45 * clampf(speed / 45.0, 0.0, 1.0))
	var v_ratio: float = clampf(speed / V_REF, 0.0, 1.15)

	# --- Nachlauf der Vorderachse --------------------------------------------
	# Die Kraft am Lenkrad ist Seitenkraft mal Nachlauf: wie hart die Vorderachse
	# arbeitet - und wie viel Nachlauf der Reifen davon noch hat.
	#
	# Die Arbeit kommt aus der Querlast, die das Auto wirklich faehrt (lat_g):
	# die Vorderraeder uebertragen sie, ob sie dabei 1 Grad oder 6 Grad
	# Schraeglauf stehen. Nur so wird das Lenkrad in einem schnellen Bogen
	# schwer, wie im offiziellen Spiel - eine Kraft, die allein am Schraeglauf
	# haengt, bleibt auf der Ideallinie bei 2 % und fuehlt sich tot an (genau so
	# gemessen in tests/probe_ffb.gd vor dieser Aenderung).
	#
	# Was der Schraeglauf beitraegt, ist die Warnung: `understeer` aus dem
	# Reifenmodell sagt, dass die Vorderachse ueber ihrem Peak ist - dann faellt
	# der Nachlauf weg und das Lenkrad wird leicht.
	trail = clampf(1.0 - 0.90 * understeer, 0.10, 1.0)
	var load: float = clampf(absf(lat_g) / LOAD_REF_G, 0.0, 1.25)
	var aero: float = clampf((downforce - 1.0) / AERO_REF, 0.0, 1.0)
	var weight: float = clampf(0.12 + 0.55 * load + 0.33 * aero, 0.0, 1.0)
	# Ueber einer Kuppe hebt die Vorderachse ab: "it lightens over a crest as
	# the front unloads" (Sim Racing Manual). Unter 0.80 g nimmt die Kraft ab,
	# bei 0.25 g sind es rund 45 % weniger - mehr waere ein Ruck, kein
	# Leichtwerden, und ein Zahnradlenkrad macht daraus Zappeln.
	var unload: float = clampf((0.80 - vertical_g) / 0.55, 0.0, 1.0)
	weight *= 1.0 - 0.45 * unload
	# Das rueckstellende Moment folgt dem Schlupfwinkel: M = t * F_y, also
	# +alpha => Moment gegen den Uhrzeigersinn => in unserer Welt nach links.
	# Gemessen heisst das: normales Einlenken -> Kraft gegen den Lenkbefehl;
	# Schlupfwinkel dreht durch die Null (Heck bricht aus) -> Kraft dreht mit.
	var align_dir: float = 0.0
	if absf(slip_front) > 0.004:
		align_dir = -clampf(slip_front / SLIP_DIR_REF, -1.0, 1.0)
	elif absf(steer_angle) > 0.004:
		align_dir = clampf(steer_angle / 0.05, -1.0, 1.0)
	sat = align_dir * trail * weight * rolling

	# --- Vorderraeder am Limit ------------------------------------------------
	# Ein Formel-Wagen hat kein ABS: je haerter der Fahrer **in die Kurve**
	# bremst, desto naeher sind die Vorderraeder am Blockieren. Ein
	# blockierender Reifen erzeugt keinen Nachlauf mehr - das Lenkrad wird
	# leicht und tot, statt hart zu ziehen. Das ist im offiziellen Spiel die
	# "die Vorderachse hat nichts mehr"-Warnung.
	#
	# Die Rechnung benutzt dieselbe Groesse wie das Reifenmodell: den
	# Schraeglauf der Vorderraeder. `PEAK_SLIP` ist genau der Punkt, an dem der
	# Reifen sein Maximum hat - also der Punkt, ab dem Bremsen und Lenken sich
	# den Reifen wirklich teilen (Friction Circle).
	#
	# Geradeaus voll bremsen (0.9) lastet die Vorderachse, nimmt aber nur rund
	# die Haelfte des Nachlaufs weg - das Lenkrad wird schwer und lebendig, so
	# wie beim Anbremsen vor der Kurve. Erst der volle Tritt **mit** Schraeglauf
	# bringt die Vorderraeder ans Blockieren: die Kraft faellt dann auf unter
	# ein Fuenftel, und das Rattern uebernimmt.
	var steer_use: float = clampf(absf(slip_front) / maxf(Tyre.PEAK_SLIP, 0.001), 0.0, 1.0)
	var front_demand: float = brake * (0.55 + 0.65 * steer_use)
	lock = clampf((front_demand - 0.30) / 0.55, 0.0, 1.0)
	# Im Schritttempo blockiert nichts - dort rollt der Reifen ohnehin nur.
	lock *= clampf(speed / 12.0, 0.0, 1.0)

	# --- durchdrehende Hinterraeder ------------------------------------------
	spin = clampf(oversteer * 1.2 + maxf(oversteer - 0.2, 0.0) * throttle, 0.0, 1.0)
	spin *= clampf(throttle * 1.4, 0.0, 1.0)
	if tc_on:
		spin *= 0.25
	spin *= clampf(speed / 25.0, 0.0, 1.0)

	# --- Unwucht durch Schaden (Platter, Einschlag) ---------------------------
	# Kein neuer Kraftkanal: derselbe Reifen, der den Nachlauf liefert, ist
	# jetzt nicht mehr rund. Die Amplitude waechst mit dem Schaden, die
	# Frequenz mit dem Tempo - wie eine Unwucht am echten Auto.
	flat = clampf((damage - FLAT_FROM) / maxf(FLAT_FULL - FLAT_FROM, 0.001), 0.0, 1.0)

	# --- Grundkraft -----------------------------------------------------------
	# Die Grundkraft bekommt die weiche Begrenzung, der Anschlag und ein
	# Aufprall nicht: die duerfen den Anschlag wirklich beruehren.
	var raw: float = _soft_limit(sat * (1.0 - LOCK_COLLAPSE * lock))
	# Der Anschlag sitzt auf einem echten Lenkeinschlag: er draengt zurueck in
	# die Mitte, auch im Stand (dort ohne Nachlauf).
	endstop = -signf(steer) * lock_pressure * ENDSTOP * (0.45 + 0.55 * rolling)
	raw += endstop

	# --- Daempfung, Reibung, Ruetteln ----------------------------------------
	damper = clampf((0.10 + 0.30 * v_ratio + 0.12 * aero) * damper_scale, 0.0, 1.0)
	var roughness: float = clampf(_num(surface, "rough", 0.0), 0.0, 1.0)
	friction = clampf(0.09 + 0.30 * roughness + 0.10 * (1.0 - rolling) + 0.12 * flat, 0.0, 1.0)
	var r := _rumble_for(speed, v_ratio, surface, lock, spin, flat, _bump, _impact,
		effects_on, band_ontrack, band_kerb, band_offtrack)
	_impact = maxf(_impact - delta * IMPACT_RUMBLE_DECAY, 0.0)
	_bump = maxf(_bump - delta * IMPACT_RUMBLE_DECAY, 0.0)
	rumble = float(r["level"])
	rumble_hz = float(r["hz"])
	source = String(r["source"])

	# --- Puls (Schalten, Einschlag, Kerbschlag) -------------------------------
	# Wichtig: der Stoss steckt **nicht** zusaetzlich in `torque`. Er ist ein
	# eigener Kanal (`pulse`/`pulse_dir`) und wird genau an einer Stelle
	# angewendet: vom Helfer (`tools/g29_ffb.py`) als sofortiger Schlag ohne
	# Rampe. Frueher lag er hier *und* im Helfer - zusammen 111 % eines
	# Schaltstosses, beim vollen Einschlag ueber 1.0 und damit gekappt. Im
	# Spiel lesen Kamera und HUD denselben `pulse`-Kanal, also geht auch dort
	# nichts verloren.
	if _pulse > 0.0:
		pulse = _pulse
		pulse_dir = _pulse_dir if absf(_pulse_dir) > 0.01 else -signf(steer)
		# Die Quelle sagt, was den Stoss ausgeloest hat - das ist die Zeile, die
		# im HUD und im Helfer steht.
		source = _SOURCE_NAMES.get(_pulse_kind, "Stoss")
		_pulse = maxf(_pulse - delta * PULSE_DECAY, 0.0)
	else:
		pulse = 0.0
		pulse_dir = 0.0
		_pulse_kind = ""

	# --- Glattung und Grenzen -------------------------------------------------
	var tau: float = clampf(delta / maxf(SMOOTH_TAU, 0.001), 0.0, 1.0)
	# Selbstheilung: falls doch einmal etwas Unendliches in die Glaettung
	# geraten ist, wird sie hier zurueckgesetzt statt fuer immer NAN zu bleiben.
	if not is_finite(_smooth_torque):
		_smooth_torque = 0.0
	if not is_finite(raw):
		raw = 0.0
	_smooth_torque = lerpf(_smooth_torque, clampf(raw, -1.2, 1.2), tau)
	var commanded: float = clampf(_smooth_torque, -1.0, 1.0)
	torque = commanded * gain
	if settings != null and bool(settings.invert):
		# Nicht nur die Grundkraft: ein Stoss (Einschlag, Schalten, Bodenwelle)
		# faehrt denselben Weg zum Lenkrad und muss mitgedreht werden. Sonst
		# haette das Rad in der Kurve in die richtige Richtung gedrueckt, der
		# Einschlag aber in die falsche - gemessen und behoben nach der
		# Hardwaremessung (tools/ffb_hw_probe.py).
		torque = -torque
		pulse_dir = -pulse_dir
	if not on:
		torque = 0.0
		damper = 0.0
		friction = 0.0
		rumble = 0.0
		pulse = 0.0
		source = "aus"
	reference_nm = absf(commanded) * F1_REF_NM
	wheel_nm = absf(torque) * WHEEL_MAX_NM
	# Clipping-Anzeige: was WIRKLICH ans Lenkrad geht, nicht was das Modell
	# vorher gerechnet hat - sonst warnt die Anzeige bei kleiner Staerke
	# dauerhaft "AM ANSCHLAG", obwohl das Lenkrad weit von seiner Grenze weg
	# ist.
	var over: float = 1.0 if absf(torque) >= CLIP_LEVEL and on else 0.0
	_clip_run = clampf(_clip_run + (over - _clip_run) * clampf(delta / 0.25, 0.0, 1.0), 0.0, 1.0)
	clip = _clip_run

	return last_state()


## Holt eine Zahl aus `ctx` und ersetzt alles, was keine endliche Zahl ist,
## durch den Ersatzwert. `NAN`, `INF` und fehlende Schluessel duerfen nicht bis
## ans Lenkrad durchlaufen: ein einziges NAN blieb sonst in der Glaettung
## haengen und vergiftete jeden weiteren Tick (HUD "nan", Paket unlesbar).
func _num(ctx: Dictionary, key: String, fallback: float) -> float:
	var value = ctx.get(key, fallback)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	var number: float = float(value)
	if not is_finite(number):
		return fallback
	return number


## Dasselbe fuer einen einzelnen Wert (Einstellungen, gemerkte Groessen).
func _safe(value, fallback: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	var number: float = float(value)
	return number if is_finite(number) else fallback


func last_state() -> Dictionary:
	return {
		"torque": torque,
		"damper": damper,
		"friction": friction,
		"rumble": rumble,
		"rumble_hz": rumble_hz,
		"pulse": pulse,
		"pulse_dir": pulse_dir,
		"source": source,
		"clip": clip,
		"sat": sat,
		"trail": trail,
		"lock": lock,
		"spin": spin,
		"flat": flat,
		"endstop": endstop,
		"reference_nm": reference_nm,
		"wheel_nm": wheel_nm,
	}


## Weiche Begrenzung: unterhalb SOFT_KNEE linear, darueber gestaucht bis
## SOFT_CEIL. Die Kurve ist am Knick stetig **und** knickfrei (`SOFT_K` ist so
## gewaehlt, dass die Steigung dort genau 1.0 bleibt): kein Sprung, kein Ruck,
## nur eine Spitze, die nicht mehr flach an der 1,0 klebt.
func _soft_limit(x: float) -> float:
	var a: float = absf(x)
	if a <= SOFT_KNEE:
		return x
	var over: float = clampf((a - SOFT_KNEE) / maxf(1.0 - SOFT_KNEE, 0.001), 0.0, 1.0)
	var mapped: float = SOFT_KNEE + (SOFT_CEIL - SOFT_KNEE) * (1.0 - pow(1.0 - over, SOFT_K))
	return signf(x) * mapped


## Ein Rütteln, eine Frequenz: die stärkste Quelle gewinnt, damit sich nicht
## zwei Frequenzen im Zahnradantrieb gegenseitig wegmitteln. Kerb ist hart und
## schnell, Kies/Gras grob und langsam, blockierende Raeder rattern, ein
## geschaedigter Reifen wuchtet, Asphalt gibt nur leise Textur.
func _rumble_for(speed: float, v_ratio: float, surface: Dictionary,
		lock: float, spin: float, flat: float, bump: float, impact: float,
		effects_on: bool, band_ontrack: float, band_kerb: float,
		band_offtrack: float) -> Dictionary:
	var level: float = 0.0
	var hz: float = 24.0
	var src: String = "-"
	var kind: int = int(surface.get("surface", 0))
	var surf_rumble: float = clampf(_num(surface, "rumble", 0.0), 0.0, 1.0)
	if effects_on and surf_rumble > 0.01:
		var speed_gain: float = 0.35 + 0.65 * clampf(speed / 45.0, 0.0, 1.2)
		# Der Band-Regler skaliert nur sein eigenes Rütteln - Kerb leise machen
		# darf das Kies-Mahlen nicht mitnehmen (sonst wäre es kein Band).
		var amp: float = surf_rumble * speed_gain * (band_kerb if kind == 1 else band_offtrack)
		if kind == 1:
			level = amp
			hz = 16.0 + 26.0 * clampf(speed / 60.0, 0.0, 1.3)
			src = "Kerb"
		elif kind == 2:
			level = amp * 0.85
			hz = 8.0 + 6.0 * clampf(speed / 40.0, 0.0, 1.2)
			src = "Kies"
		else:
			level = amp * 0.75
			hz = 7.0 + 5.0 * clampf(speed / 40.0, 0.0, 1.2)
			src = "Gras"
	# Blockierende Vorderraeder: feines, hartes Rattern ueber der Grundkraft.
	if effects_on and lock > 0.15:
		var chat: float = 0.25 + 0.45 * lock
		if chat > level:
			level = chat
			hz = 24.0 + 10.0 * lock
			src = "Blockiert"
	# Durchdrehende Hinterraeder: dumpfer, langsamer als ein Kerb.
	if effects_on and spin > 0.25:
		var grind: float = 0.18 + 0.35 * spin
		if grind > level:
			level = grind
			hz = 15.0 + 9.0 * spin
			src = "Räder drehen durch"
	# Unwucht (Platter nach dem Blockieren, verbogenes Rad nach dem Einschlag):
	# dumpf im Stand, mit dem Tempo schneller und staerker.
	if effects_on and flat > 0.01:
		var wobble: float = (0.20 + 0.42 * flat) * clampf(speed / 25.0, 0.0, 1.0)
		if wobble > level:
			level = wobble
			hz = 11.0 + 16.0 * clampf(speed / 60.0, 0.0, 1.2)
			src = "Unwucht"
	# Asphalt-Textur: leise, aber mit dem Tempo feiner und staerker.
	if effects_on and surf_rumble <= 0.01:
		var tex: float = (0.04 + 0.07 * clampf(speed / 60.0, 0.0, 1.3)) * band_ontrack
		if tex > level:
			level = tex
			hz = 22.0 + 18.0 * clampf(speed / 70.0, 0.0, 1.2)
			src = "Asphalt"
	# Bodenwelle: dumpfer, grober Schlag von gestauchter Feder - langsamer als
	# ein Kerb, haerter als Kies. Ein echter Aufprall uebertoent ihn.
	if effects_on and bump > 0.02:
		var thud: float = 0.20 + 0.40 * clampf(bump, 0.0, 1.0)
		if thud > level:
			level = thud
			hz = 14.0 + 12.0 * clampf(bump, 0.0, 1.0)
			src = "Bodenwelle"
	# Aufprall: harter Schlag mit kurzem, grobem Nachschuetteln. Steht ganz
	# hinten, weil er jede andere Rueckmeldung in diesem Moment uebertoent.
	if effects_on and impact > 0.02:
		var jolt: float = 0.35 + 0.50 * clampf(impact, 0.0, 1.0)
		if jolt > level:
			level = jolt
			hz = 18.0 + 14.0 * clampf(impact, 0.0, 1.0)
			src = "Aufprall"
	# Ein auf 0 % gedrehtes Band darf keine Quelle mehr melden: sonst stünde im
	# HUD "Asphalt 0 %" und im Helfer eine Herkunft, die es nicht gibt.
	if level <= 0.005:
		level = 0.0
		src = "-"
	return {"level": clampf(level, 0.0, 1.0), "hz": clampf(hz, 5.0, 60.0), "source": src}
