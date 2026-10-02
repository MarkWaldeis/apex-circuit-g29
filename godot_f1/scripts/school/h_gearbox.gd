extends RefCounted
## Handgeschaltetes 6-Gang-Getriebe mit H-Schaltung, Rückwärtsgang und echter
## Kupplung — das Kernstück der Fahrschule: wer die Kupplung schleudern lässt,
## würgt den Motor ab.
##
## Konventionen:
##   gear     -1 = R, 0 = Leerlauf, 1..6
##   clutch_pedal  0.0 = Fuß weg (Kupplung eingekuppelt), 1.0 = durchgetreten
##   engage   0 = getrennt, 1 = geschlossen; Schleifpunkt in der Pedalmitte
##
## Das Modell rechnet in Newton am Rad: Motormoment -> Übersetzung -> Radradius.

const GEARS := [-1, 0, 1, 2, 3, 4, 5, 6]
## Übersetzungen (Kompaktklasse, z. B. Golf 1.6). Index = Gang + 1 (R=0, N=1).
const RATIOS := {-1: 3.55, 0: 0.0, 1: 3.45, 2: 1.96, 3: 1.30, 4: 0.97, 5: 0.80, 6: 0.66}
const FINAL_DRIVE := 3.9
const WHEEL_RADIUS := 0.32
const IDLE_RPM := 800.0
const REDLINE := 6200.0
const MAX_TORQUE_NM := 155.0
const TORQUE_PEAK_RPM := 3900.0
## Unterhalb dieser geforderten Drehzahl würgt der Motor ab — der Fahrlehrer-
## Moment: bis fast zum Stillstand ohne Kupplung bremsen ist genau das.
const STALL_RPM := 350.0
## Schleifbereich des Pedals: unter BITE_IN ist die Kupplung fest
## eingekuppelt, über BITE_OUT getrennt — dazwischen liegt der Schleifpunkt.
const BITE_IN := 0.25
const BITE_OUT := 0.72
## Wie schnell die Kupplung kommen darf (engage/s), ohne dass es beim Anfahren
## direkt den Motor abwürgt — der klassische "Kupplung schleudern lassen".
const SNAP_RATE := 2.6
const SHIFT_MIN_CLUTCH := 0.70   ## Pedal so weit runter = getrennt genug zum Schalten

var gear: int = 0
var rpm: float = IDLE_RPM
var motor_on: bool = true
var stalled: bool = false
## Zündschloss: aus -> der Motor bleibt aus, bis er per Zündung gestartet
## wird (abstellen ist kein Abwürgen — der Stalls-Zähler bleibt unberührt).
var ignition: bool = true
## Diagnosezähler für den Fahrlehrer.
var stalls: int = 0
var grinds: int = 0
var _prev_engage: float = 1.0
var _stall_kick: float = 0.0     ## Rest-Ruck nach dem Abwürgen
var _crank: float = 0.0          ## Anlasser läuft


func setup() -> void:
	gear = 0
	rpm = IDLE_RPM
	motor_on = true
	stalled = false
	stalls = 0
	grinds = 0
	_prev_engage = 1.0
	ignition = true
	_crank = 0.0


func reset() -> void:
	setup()


func ratio(g: int) -> float:
	return float(RATIOS.get(g, 0.0))


## Drehzahl, die die Räder dem Motor bei dieser Geschwindigkeit aufzwingen
## (ohne Leerlauf-Boden: darunter muss der Motor wirklich drehen, sonst
## würgt er ab — genau das Modell der echten Kupplung).
func rpm_for(g: int, speed_ms: float) -> float:
	if g == 0:
		return IDLE_RPM
	return absf(speed_ms) / WHEEL_RADIUS * ratio(g) * FINAL_DRIVE * 60.0 / TAU


## Gang einlegen — geht nur bei getretener Kupplung (Schleifpunkt ausreichend),
## sonst "Knirschen": der Gang springt nicht rein und der Fahrlehrer meckert.
## R sperrt über ~2 km/h vorwärts oder rückwärts.
func request_gear(g: int, clutch_pedal: float, speed_ms: float) -> bool:
	if g == gear:
		return true
	if not g in GEARS:
		return false
	if g == -1 and absf(speed_ms) > 1.5:
		return false
	# Rausnehmen nach Leerlauf geht ohne Kupplung (Schieben), nur
	# das Einlegen eines Gangs braucht getretene Kupplung.
	if g != 0 and clutch_pedal < SHIFT_MIN_CLUTCH:
		grinds += 1
		return false
	gear = g
	return true


## Anlasser: bei stehendem Motor mit voll getretener Kupplung starten —
## nach dem Abwürgen genauso wie nach dem Abstellen an der Zündung.
func start_motor(clutch_pedal: float) -> void:
	if motor_on or not ignition:
		return
	if clutch_pedal < 0.75:
		return
	if _crank <= 0.0:
		_crank = 0.45


## Zündung aus: der Motor geht aus — kein Abwürgen, der Zähler bleibt stehen.
func ignition_off() -> void:
	ignition = false
	motor_on = false
	stalled = false
	rpm = 0.0
	_crank = 0.0


## Zündung an: der Anlasser dreht — durchstarten haengt an der Kupplung.
func ignition_on(clutch_pedal: float) -> void:
	ignition = true
	start_motor(clutch_pedal)


func torque_at(r: float) -> float:
	var n: float = clampf((r - IDLE_RPM) / maxf(TORQUE_PEAK_RPM - IDLE_RPM, 1.0), 0.0, 1.0)
	var rise: float = 1.0 - pow(1.0 - clampf(n, 0.0, 1.0), 2.0)
	var fall: float = 1.0
	if r > TORQUE_PEAK_RPM:
		fall = 1.0 - 0.35 * clampf((r - TORQUE_PEAK_RPM) / maxf(REDLINE - TORQUE_PEAK_RPM, 1.0), 0.0, 1.0)
	return MAX_TORQUE_NM * lerpf(0.30, 1.0, rise) * fall


## ctx: speed (m/s vorwärts, kann negativ), throttle 0..1, brake 0..1,
##      clutch 0..1 = Pedalstellung (0 = Fuß weg, 1 = durchgetreten),
##      auto (Automatik-Assistent)
func update(delta: float, ctx: Dictionary) -> Dictionary:
	var speed: float = float(ctx.get("speed", 0.0))
	var throttle: float = clampf(float(ctx.get("throttle", 0.0)), 0.0, 1.0)
	var brake: float = clampf(float(ctx.get("brake", 0.0)), 0.0, 1.0)
	var clutch_pedal: float = clampf(float(ctx.get("clutch", 0.0)), 0.0, 1.0)
	var auto: bool = bool(ctx.get("auto", false))

	# ---- Anlasser ----------------------------------------------------------
	if _crank > 0.0:
		_crank -= delta
		if _crank <= 0.0 and not motor_on:
			stalled = false
			motor_on = true
			rpm = IDLE_RPM

	if not motor_on:
		rpm = 0.0

	# ---- Kupplungsweg -------------------------------------------------------
	# engage = wie stark Kraft fließt: 0 = getrennt, 1 = geschlossen.
	# Pedal 0 = Fuß weg -> 1; ab Pedal BITE_IN öffnet sie, ab BITE_OUT getrennt.
	var pedal_engage: float = clampf((BITE_OUT - clutch_pedal) / maxf(BITE_OUT - BITE_IN, 0.01), 0.0, 1.0)
	var engage := pedal_engage
	if auto:
		# Automatik: die Wandler-Automatik kuppelt selbst ein — im Stand mit
		# Gang kriecht das Auto leicht, beim Schalten trennt sie kurz.
		engage = 1.0
		clutch_pedal = 1.0

	# ---- Automatik-Gangwahl ------------------------------------------------
	if auto and motor_on:
		_auto_shift(speed, throttle)

	# ---- Drehzahl -----------------------------------------------------------
	# gas_rpm: was der Motor ohne Last aus dem Gas macht. lock: wie fest die
	# Kupplung die Drehzahl an die Räder bindet (erst über der Hälfte des
	# Schleifpunkts — darunter schlüpft sie und der Motor läuft frei).
	# geared_rpm auch für die Abwürg-Erkennung weiter unten.
	var geared_rpm: float = rpm_for(gear, speed)
	if motor_on:
		var gas_rpm: float = IDLE_RPM + throttle * (REDLINE - IDLE_RPM) * 0.85
		if auto:
			# Wandler: das Motordrehzahl folgt Gas + etwas Radkupplung.
			rpm = lerpf(rpm, gas_rpm * 0.8 + geared_rpm * 0.45, clampf(delta * 6.0, 0.0, 1.0))
		elif engage < 0.5 or gear == 0:
			rpm = lerpf(rpm, gas_rpm, clampf(delta * 7.0, 0.0, 1.0))
		else:
			var lock := clampf((engage - 0.5) / 0.45, 0.0, 1.0)
			rpm = lerpf(rpm, lerpf(gas_rpm, maxf(geared_rpm, 0.0), lock), clampf(delta * 12.0, 0.0, 1.0))
		rpm = clampf(rpm, 0.0, REDLINE + 300.0)

	# ---- Abwürgen -----------------------------------------------------------
	if motor_on and not stalled and not auto:
		# Abwürgen nur bei (fast) geschlossener Kupplung: eingekuppelt im Stand
		# bzw. bis zum Stillstand gebremst ohne zu treten. Geschliffene Kupplung
		# stirbt nicht — dafuer ist der Schleifpunkt da.
		var too_slow: bool = gear != 0 and engage > 0.92 and geared_rpm < STALL_RPM and throttle < 0.18
		var snapped_clutch: bool = (engage - _prev_engage) / maxf(delta, 0.0001) > SNAP_RATE \
			and gear != 0 and absf(speed) < 1.2 and throttle < 0.45
		if too_slow or snapped_clutch:
			stalled = true
			motor_on = false
			stalls += 1
			_stall_kick = 0.35
			rpm = 0.0
	_prev_engage = engage

	# ---- Kraft --------------------------------------------------------------
	var torque_nm: float = 0.0
	if motor_on and not stalled:
		torque_nm = torque_at(rpm) * throttle
		# Leerlauf-Kriechen: mit eingekuppeltem 1./2. Gang schiebt der Motor
		# im Leerlauf weiter — auch ganz ohne Gas (Anfahren nur mit
		# Kupplung, Kriechen im Stau). Gebremst zum Stand wuergt er ab.
		if engage > 0.05 and throttle < 0.12 and gear > 0 and absf(speed) < 2.5:
			torque_nm = maxf(torque_nm, 60.0 * engage)
		# Automatik-Kriechen wie ein Wandler: im Stand mit Gang rollt das Auto
		# langsam los, ohne dass man Gas gibt.
		if auto and gear > 0 and throttle < 0.05 and absf(speed) < 2.0 and brake < 0.3:
			torque_nm = maxf(torque_nm, 48.0)
	var engine_force: float = 0.0
	if gear != 0:
		var dir := -1.0 if gear == -1 else 1.0
		engine_force = dir * torque_nm * ratio(gear) * FINAL_DRIVE / WHEEL_RADIUS * engage
	# Motorbremse: Gas weg + eingekuppelt -> bremst auf die Drehzahl ein.
	if motor_on and not stalled and throttle < 0.05 and gear != 0 and engage > 0.5:
		var rev := clampf((rpm - IDLE_RPM) / (REDLINE - IDLE_RPM), 0.0, 1.0)
		var dir2 := -1.0 if gear == -1 else 1.0
		engine_force += -dir2 * minf(400.0 + 2600.0 * rev, absf(speed) * 800.0 + 60.0) * 0.45
	if brake > 0.05:
		engine_force = minf(engine_force, 0.0)

	# Der Ruck beim Abwürgen: kurzer harter Stoß vorwärts.
	var judder: float = 0.0
	if _stall_kick > 0.0:
		_stall_kick -= delta
		judder = 900.0

	return {
		"engine_force": engine_force,
		"rpm": rpm,
		"gear": gear,
		"stalled": stalled,
		"motor_on": motor_on,
		"judder": judder,
	}


## Automatik-Modus (Fahrlehrer-Hilfe): schaltet wie eine Wandler-Automatik.
func _auto_shift(speed: float, throttle: float) -> void:
	if gear == -1:
		return   # Rückwärtsgang bleibt Handwahl
	var v := absf(speed)
	var best := gear
	if gear <= 0:
		best = 1 if v < 30.0 else gear
	elif rpm_for(gear, v) > 4300.0 and gear < 6:
		best = gear + 1
	elif rpm_for(gear, v) < 1250.0 and gear > 1:
		best = gear - 1
	if throttle > 0.85 and gear > 1 and rpm_for(gear - 1, v) < REDLINE - 300.0:
		best = gear - 1     # Kickdown
	if best != gear and best > 0:
		gear = best
