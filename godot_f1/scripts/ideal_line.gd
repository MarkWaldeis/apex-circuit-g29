extends RefCounted
## Die Ideallinie: wo der Fahrer wirklich fahren soll, und wie schnell.
##
## Die Streckendatei (`racing_line.json`) ist die geometrische MITTE der 12 m
## breiten Fahrbahn. Die Linie, mit der man schnell ist, liegt aber nicht in
## der Mitte: sie faehrt die Kurve aussen an, clipst den Scheitel innen und
## laeuft zum Ausgang wieder nach aussen. Genau diese Linie wird hier
## gerechnet, zusammen mit der Geschwindigkeit, die an jedem Punkt moeglich
## ist, und der Phase (Gas / lupfen / bremsen) fuer die Anzeige.
##
## Verfahren (kein Fremdcode, laeuft in Sekundenbruchteilen):
##
##  1. Ausgangspunkt ist die Mittellinie. Jeder Punkt bekommt einen seitlichen
##     Versatz (`offsets`), positiv nach links in Fahrtrichtung.
##  2. Eine Relaxation zieht jeden Punkt zur INNENSEITE seiner Kurve (dorthin,
##     wo der Kruemmungsmittelpunkt liegt) und glaettet gleichzeitig die
##     Nachbarn. Randbedingung ist der Korridor `corridor` (Fahrbahn plus Kerb,
##     mit Sicherheitsrand) - die Linie kann die Strecke nie verlassen.
##  3. Aus der neuen Geometrie werden Laengen, Tangenten und Kruemmungen neu
##     gerechnet. Ein Geschwindigkeitsprofil entsteht daraus in Durchgaengen:
##     Kurvengrenze v = sqrt(a_lat/|k|), rueckwaerts Bremsen
##     (v0^2 = v1^2 + 2*a*s), vorwaerts Beschleunigen.
##  4. Aus dem Profil wird die Phase: rot, wo wirklich gebremst werden muss
##     (Verzoegerung ueber ~6 m/s^2), gelb beim Lupfen, sonst gruen.
##
## OWNER: agent LINE.

const THROTTLE := 0
const LIFT := 1
const BRAKE := 2

## Fahrzeug, mit dem das Profil gerechnet wird: ~3,5 g in der Kurve, ~4,3 g
## beim Bremsen (Formel-1-Groessenordnung; damit liegt der Bremsweg aus
## 200 km/h bei ~110 m).
const DEFAULT_PARAMS := {
	"lat_accel": 34.0,      ## m/s^2 Querbeschleunigung, die die Linie nutzen darf
	"brake_decel": 42.0,    ## m/s^2 Bremsverzoegerung
	"accel": 13.0,          ## m/s^2 Beschleunigung aus der Kurve heraus
	"corridor": 5.2,        ## m seitlicher Spielraum (Fahrbahn 6,0 m halb; der
	                        ## Rest ist Sicherheitsrand zum Fahrbahnrand)
	"v_max": 96.0,          ## m/s (~345 km/h) Deckel auf Geraden
	"v_min": 13.0,          ## m/s Untergrenze, damit sqrt() nie nach 0 laeuft
	"control_step": 12,     ## Punkte zwischen zwei Stellpunkten der Linie
	"passes": 9,            ## Suchdurchgaenge der Optimierung
	"search_start": 0.8,    ## m Schrittweite im ersten Durchgang
	"curvature_span": 10.0, ## m links/rechts fuer die Kruemmung. Bewusst in
	                        ## Metern, nicht in Punkten: die Mittellinie ist
	                        ## am Rundenende feiner abgetastet, und eine
	                        ## Kruemmung ueber "6 Punkte" meldete dort eine
	                        ## 7-m-Haarnadel, die es nicht gibt.
	"brake_threshold": 6.0, ## m/s^2 ab hier ist es eine Bremszone
	"lift_threshold": 1.5,  ## m/s^2 ab hier wird gelupft
	"min_brake_zone": 25.0, ## m Mindestlaenge einer roten Zone
	"curvature_penalty": 20.0, ## Strafe, wenn die Linie eine Kurve enger macht
	                           ## als die Mittellinie (dann kostet sie Zeit)
}

var points: PackedVector3Array = PackedVector3Array()
var offsets: PackedFloat32Array = PackedFloat32Array()
var curvature: PackedFloat32Array = PackedFloat32Array()
var target_speed: PackedFloat32Array = PackedFloat32Array()
var phase: PackedInt32Array = PackedInt32Array()
## Abstand von Punkt i zu Punkt i+1 (m). Die Laenge der Runde ist die Summe.
var segments: PackedFloat32Array = PackedFloat32Array()
var length: float = 0.0
var source_point_count: int = 0
var params: Dictionary = DEFAULT_PARAMS.duplicate()
## Summe |k| der Mittellinie: die Zahl, gegen die die Ideallinie gewinnen muss.
var centre_curvature_sum: float = 0.0
var ideal_curvature_sum: float = 0.0
## Kruemmung der Mittellinie, Punkt fuer Punkt (fuer die Strafe oben).
var _centre_k: PackedFloat32Array = PackedFloat32Array()


## Kruemmung der Mittellinie an Punkt `i`, gemessen ueber +/- span METER (nicht
## ueber eine feste Punktzahl).
##
## Der Unterschied ist wichtig: `racing_line.json` tastet die Strecke nicht
## gleichmaessig ab - am Rundenende liegen die Punkte nur ~2 m auseinander.
## Eine Kruemmung ueber "6 Punkte" meldete dort eine 7-m-Haarnadel, die es gar
## nicht gibt, und verdarb damit das Geschwindigkeitsprofil und die Bewertung
## der Linie. In Metern gerechnet ist die Kruemmung unabhaengig davon, wie fein
## die Datei abgetastet ist.
func _centre_curvature(line, i: int) -> float:
	var span: float = float(params["curvature_span"])
	var n: int = line.points.size()
	var back: int = _walk_s(line, i, -1, span)
	var ahead: int = _walk_s(line, i, 1, span)
	var a: Vector3 = line.flat_tangent(back)
	var b: Vector3 = line.flat_tangent(ahead)
	return a.signed_angle_to(b, Vector3.UP) / (2.0 * span)


## Index, der `span` Meter vor (dir = -1) oder hinter (dir = +1) Punkt `i`
## liegt. Doppelte Punkte (am Rundenende liegt der letzte Punkt auf dem ersten)
## werden uebersprungen, sonst kaeme die Schleife nie voran.
func _walk_s(line, i: int, dir: int, span: float) -> int:
	var n: int = line.points.size()
	var index: int = wrapi(i, 0, n)
	var travelled := 0.0
	var guard := 0
	while travelled < span and guard < 500:
		guard += 1
		var nxt: int = wrapi(index + dir, 0, n)
		var ds: float = line.points[index].distance_to(line.points[nxt])
		index = nxt
		if ds < 0.01:
			continue
		travelled += ds
	return index



func build(line, overrides: Dictionary = {}) -> bool:
	params = DEFAULT_PARAMS.duplicate()
	for k in overrides.keys():
		params[k] = overrides[k]
	if line == null or line.points.size() < 32:
		push_warning("IdealLine: keine Mittellinie")
		return false
	source_point_count = line.points.size()
	var n: int = line.points.size()
	var centre_k := PackedFloat32Array()
	centre_k.resize(n)
	centre_curvature_sum = 0.0
	for i in n:
		centre_k[i] = _centre_curvature(line, i)
		centre_curvature_sum += absf(centre_k[i])
	_centre_k = centre_k
	_optimise_offsets(line, centre_k)
	_rebuild_path(line)
	_speed_profile()
	_classify_phases()
	print("IdealLine pts=%d len=%.1f m max|k|=%.4f sum|k|=%.1f (Mitte %.1f, %+.1f%%) max|offset|=%.2f" % [
		n, length, _max_abs(curvature), ideal_curvature_sum, centre_curvature_sum,
		100.0 * (ideal_curvature_sum - centre_curvature_sum) / maxf(centre_curvature_sum, 0.001),
		_max_abs(offsets)])
	return true


## Schritt 2: die Linie legen.
##
## Gesucht sind die seitlichen Versaetze, die die Kruemmungsenergie
## J = Summe k^2 * ds der Runde minimieren - das ist die uebliche Definition
## der Ideallinie (minimale Kruemmung im Korridor), und sie ist genau die
## Linie, die in jedem Punkt die hoechste Kurvengeschwindigkeit erlaubt.
##
## Verfahren: Koordinatensuche ueber Stellwerte (`control_step` Punkte
## auseinander, dazwischen weich interpoliert). In jedem Durchgang wird jeder
## Stellwert um +-delta verschoben; behalten wird nur, was J senkt. delta
## schrumpft von Durchgang zu Durchgang (0,8 m -> ~4 cm), der Korridor ist die
## harte Randbedingung. Ausgewertet wird nur das Fenster um den Stellwert - die
## Aenderung wirkt lokal, deshalb ist das schnell genug fuer jeden Start.
func _optimise_offsets(line, _centre_k: PackedFloat32Array) -> void:
	var n: int = line.points.size()
	var limit: float = float(params["corridor"])
	var step: int = maxi(int(params["control_step"]), 4)
	var count: int = int(ceil(float(n) / float(step)))
	var values := PackedFloat32Array()
	values.resize(count)                      # Start: Mittellinie (0.0)
	var delta: float = float(params["search_start"])
	for _pass_index in int(params["passes"]):
		for j in count:
			var best: float = values[j]
			var best_cost: float = _window_cost(line, values, step, j * step)
			for trial_sign in [1.0, -1.0]:
				values[j] = clampf(best + trial_sign * delta, -limit, limit)
				var cost: float = _window_cost(line, values, step, j * step)
				if cost < best_cost - 1e-9:
					best_cost = cost
					best = values[j]
			values[j] = best
		delta *= 0.62
	offsets = PackedFloat32Array()
	offsets.resize(n)
	for i in n:
		offsets[i] = _offset_from_controls(values, step, i)


## Weiche Interpolation zwischen zwei Stellwerten (Smoothstep): die Linie ist
## damit C1-stetig, sie hat an den Stellwerten keinen Knick.
func _offset_from_controls(values: PackedFloat32Array, step: int, i: int) -> float:
	var count: int = values.size()
	if count == 0:
		return 0.0
	var x: float = float(i) / float(step)
	var j: int = int(floor(x))
	var t: float = x - float(j)
	var a: float = values[posmod(j, count)]
	var b: float = values[posmod(j + 1, count)]
	var s: float = t * t * (3.0 - 2.0 * t)
	return a + (b - a) * s


## Kosten im Fenster um `centre`: die Zeit, die dieses Stueck kostet,
## Summe ds / v mit v = sqrt(a_lat / |k|).
##
## Das ist bewusst NICHT die Kruemmungsenergie: die waere minimal, wenn die
## Linie einfach aussen herum faehrt (groesster Radius, laengster Weg). Gemessen
## auf dieser Strecke ist genau das langsamer. Die Zeit kostet dagegen sowohl
## die Laenge als auch die Enge, und deshalb kommt dabei die Linie heraus, die
## die Kurve schneidet statt sie weit zu umfahren.
##
## Das Fenster ist so breit, dass die Nachbar-Stellwerte und die
## Kruemmungsfenster hineinpassen.
func _window_cost(line, values: PackedFloat32Array, step: int, centre: int) -> float:
	var n: int = line.points.size()
	var span: float = float(params["curvature_span"])
	# Das Fenster muss die Nachbar-Stellwerte UND die Kruemmungsmessung
	# (+/- span Meter) enthalten.
	var spacing: float = maxf(line.length / float(maxi(n, 1)), 0.1)
	var reach: int = maxi(step * 2, int(ceil(span / spacing)) + 4)
	var count: int = reach * 2 + 1
	var a_lat: float = float(params["lat_accel"])
	var v_max: float = float(params["v_max"])
	var v_min: float = float(params["v_min"])
	var penalty: float = float(params["curvature_penalty"])
	var pts := PackedVector3Array()
	pts.resize(count)
	for k in count:
		var i: int = wrapi(centre - reach + k, 0, n)
		var p: Vector3 = line.points[i] + line.left_at(i) * _offset_from_controls(values, step, i)
		p.y = line.points[i].y
		pts[k] = p
	var cost := 0.0
	for k in range(1, count - 1):
		if k < reach - step or k > reach + step:
			continue
		# Kruemmung ueber +/- span Meter auf den Fensterpunkten - dieselbe
		# Messung wie _curvature_at, nur lokal.
		var lo: int = _walk_local(pts, k, -1, span)
		var hi: int = _walk_local(pts, k, 1, span)
		var t0: Vector3 = _local_tangent(pts, lo)
		var t1: Vector3 = _local_tangent(pts, hi)
		if t0 == Vector3.ZERO or t1 == Vector3.ZERO:
			continue
		var kappa: float = t0.signed_angle_to(t1, Vector3.UP) / (2.0 * span)
		var v: float = v_max if absf(kappa) < 1e-6 else sqrt(a_lat / absf(kappa))
		var ds: float = maxf(pts[k + 1].distance_to(pts[k]), 0.01)
		cost += ds / clampf(v, v_min, v_max)
		# Eine Stelle, die enger wird als die Mittellinie, kostet ueberproportional
		# Zeit (dort faellt die Geschwindigkeit mit der Wurzel, aber der
		# Bremsweg davor waechst quadratisch). Ohne diese Strafe schneidet die
		# Optimierung die Haarnadel so weit, dass der Wagen dort kriecht.
		if penalty > 0.0 and _centre_k.size() > 0:
			var gi: int = wrapi(centre - reach + k, 0, n)
			var allowed: float = absf(_centre_k[gi]) * 1.05
			var excess: float = maxf(absf(kappa) - allowed, 0.0)
			cost += penalty * excess * excess * ds
	return cost


## Tangente auf dem lokalen Fenster-Array (y = 0, normiert).
func _local_tangent(pts: PackedVector3Array, k: int) -> Vector3:
	var count: int = pts.size()
	if k <= 0 or k >= count - 1:
		return Vector3.ZERO
	var t: Vector3 = pts[k + 1] - pts[k - 1]
	t.y = 0.0
	if t.length() < 0.001:
		return Vector3.ZERO
	return t.normalized()


## Wie _walk_path, aber auf dem lokalen Fenster-Array.
func _walk_local(pts: PackedVector3Array, k: int, dir: int, span: float) -> int:
	var count: int = pts.size()
	var index: int = clampi(k, 0, count - 1)
	var travelled := 0.0
	var guard := 0
	while travelled < span and guard < count:
		guard += 1
		var nxt: int = clampi(index + dir, 0, count - 1)
		if nxt == index:
			break
		travelled += pts[index].distance_to(pts[nxt])
		index = nxt
	return index


## Schritt 3a: die neue Bahn und ihre Geometrie.
func _rebuild_path(line) -> void:
	var n: int = line.points.size()
	points = PackedVector3Array()
	points.resize(n)
	for i in n:
		var p: Vector3 = line.points[i] + line.left_at(i) * offsets[i]
		# Hoehe der Mittellinie behalten: die Linie soll auf dem Asphalt
		# liegen, nicht in Steilkurven schweben.
		p.y = line.points[i].y
		points[i] = p
	segments = PackedFloat32Array()
	segments.resize(n)
	length = 0.0
	for i in n:
		var after: int = wrapi(i + 1, 0, n)
		segments[i] = maxf(points[i].distance_to(points[after]), 0.01)
		length += segments[i]
	curvature = PackedFloat32Array()
	curvature.resize(n)
	ideal_curvature_sum = 0.0
	for i in n:
		curvature[i] = _curvature_at(i)
		ideal_curvature_sum += absf(curvature[i])


func _tangent_at_index(i: int) -> Vector3:
	var n := points.size()
	var t: Vector3 = points[wrapi(i + 1, 0, n)] - points[wrapi(i - 1, 0, n)]
	t.y = 0.0
	if t.length() < 0.001:
		return Vector3(0, 0, -1)
	return t.normalized()


## Vorzeichenbehaftete Kruemmung 1/m des neuen Pfades: positiv = Linkskurve.
## Gemessen ueber +/- `curvature_span` Meter, damit die feine Abtastung am
## Rundenende keine Scheinkurven erzeugt (siehe _centre_curvature).
func _curvature_at(i: int) -> float:
	var span: float = float(params["curvature_span"])
	var back: int = _walk_path(i, -1, span)
	var ahead: int = _walk_path(i, 1, span)
	var a: Vector3 = _tangent_at_index(back)
	var b: Vector3 = _tangent_at_index(ahead)
	return a.signed_angle_to(b, Vector3.UP) / (2.0 * span)


## Wie _walk_s, nur auf dem eigenen Pfad (Punktabstaende in `segments`).
func _walk_path(i: int, dir: int, span: float) -> int:
	var n := points.size()
	var index: int = wrapi(i, 0, n)
	var travelled := 0.0
	var guard := 0
	while travelled < span and guard < 500:
		guard += 1
		var step: int = index if dir > 0 else wrapi(index - 1, 0, n)
		var nxt: int = wrapi(index + dir, 0, n)
		travelled += maxf(segments[step], 0.01)
		index = nxt
	return index


## Schritt 3b: wie schnell darf es hier sein?
func _speed_profile() -> void:
	var n := points.size()
	var a_lat: float = float(params["lat_accel"])
	var a_brake: float = float(params["brake_decel"])
	var a_accel: float = float(params["accel"])
	var v_max: float = float(params["v_max"])
	var v_min: float = float(params["v_min"])
	target_speed = PackedFloat32Array()
	target_speed.resize(n)
	for i in n:
		var k: float = absf(curvature[i])
		var v: float = v_max if k < 1e-6 else sqrt(a_lat / k)
		target_speed[i] = clampf(v, v_min, v_max)
	# rueckwaerts: bremsen, damit der Scheitel wirklich langsam genug ist
	for _pass in 2:
		for step in n:
			var i: int = n - 1 - step
			var after: int = wrapi(i + 1, 0, n)
			var reach: float = sqrt(target_speed[after] * target_speed[after]
				+ 2.0 * a_brake * segments[i])
			target_speed[i] = minf(target_speed[i], reach)
	# vorwaerts: eine Gerade darf nicht von der Kurve davor gebremst bleiben
	for _pass in 2:
		for i in n:
			var before: int = wrapi(i - 1, 0, n)
			var reach: float = sqrt(target_speed[before] * target_speed[before]
				+ 2.0 * a_accel * segments[before])
			target_speed[i] = minf(target_speed[i], reach)


## Schritt 4: Gas / lupfen / bremsen.
##
## Nicht der Lenkwinkel entscheidet, sondern die Verzoegerung, die das Profil
## verlangt: a = v * dv/ds. Was ueber der Schwelle liegt, ist eine Bremszone -
## und die wird auf eine Mindestlaenge gestreckt, damit die Farbe auf dem
## Asphalt nicht flackert.
func _classify_phases() -> void:
	var n := points.size()
	phase = PackedInt32Array()
	phase.resize(n)
	var a_lat: float = float(params["lat_accel"])
	var v_max: float = float(params["v_max"])
	# 1. Verzoegerung des Profils, geglaettet: das rohe Signal hat an einzelnen
	#    Punkten Spitzen, und ohne Glaettung wuerde die Anzeige in lauter
	#    Ein-Punkt-Bremszonen zerfallen.
	var decel := PackedFloat32Array()
	decel.resize(n)
	for i in n:
		var after: int = wrapi(i + 1, 0, n)
		var dv: float = maxf(target_speed[i] - target_speed[after], 0.0)
		decel[i] = target_speed[i] * dv / maxf(segments[i], 0.1)
	decel = _smooth(decel, 5)
	# 2. "Hier ist es eng" gegen "hier muss gebremst werden" trennen: eine
	#    Kurvengrenze, die das Profil nicht ausschoepft, heisst Bremsen fuer
	#    eine spaetere Kurve.
	var brake_cut: float = float(params["brake_threshold"])
	var lift_cut: float = float(params["lift_threshold"])
	for i in n:
		var k: float = absf(curvature[i])
		var corner_limit: float = v_max if k < 1e-6 else sqrt(a_lat / k)
		var brake_limited: bool = target_speed[i] < corner_limit - 1.0
		var slowing: bool = decel[i] >= 1.0
		if brake_limited and slowing and decel[i] >= brake_cut * 0.5:
			phase[i] = BRAKE
		elif decel[i] >= lift_cut:
			phase[i] = LIFT
		else:
			phase[i] = THROTTLE
	_merge_gaps(BRAKE, 12.0)
	_min_zone(BRAKE, LIFT, float(params["min_brake_zone"]))


## Gleitender Mittelwert ueber +/-half Punkte (zirkulaer).
func _smooth(values: PackedFloat32Array, half: int) -> PackedFloat32Array:
	var n := values.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var sum := 0.0
		var count := 0
		for k in range(-half, half + 1):
			sum += values[wrapi(i + k, 0, n)]
			count += 1
		out[i] = sum / float(count)
	return out


## Kurze Unterbrechungen zwischen zwei Zonen derselben Phase schliessen: zwei
## Bremszonen mit 8 m Gas dazwischen sind in Wirklichkeit eine.
func _merge_gaps(kind: int, max_gap: float) -> void:
	var n := phase.size()
	var i := 0
	while i < n:
		if phase[i] != kind:
			i += 1
			continue
		var j := i
		while j < n and phase[j] == kind:
			j += 1
		if j >= n:
			break
		# Abstand bis zur naechsten Zone derselben Phase messen.
		var gap := 0.0
		var m := j
		while m < n and phase[m] != kind:
			gap += segments[m]
			m += 1
		if m < n and gap <= max_gap:
			for f in range(j, m):
				phase[f] = kind
		i = m


## Jede Zone der Phase `kind` mindestens `min_length` Meter lang machen.
## Verlaengert wird nach hinten (in Fahrtrichtung gesehen vor die Zone), weil
## der Fahrer frueher bremsen muss, nicht spaeter.
func _min_zone(kind: int, _filler: int, min_length: float) -> void:
	var n := phase.size()
	# Weil die Zonen ueber den Rundenanfang laufen koennen, wird in zwei
	# Durchgaengen gearbeitet: erst die linearen Zonen, dann der Rest, der ueber
	# Index 0 hinausragt.
	for _round in 2:
		var i := 0
		while i < n:
			if phase[i] != kind:
				i += 1
				continue
			var start := i
			var span := 0.0
			var j := i
			while j < n and phase[j] == kind:
				span += segments[j]
				j += 1
			# Tempo am Ende der Zone: weiter nach hinten verlaengert wird nur,
			# solange das Auto dort noch schneller ist. Sonst wuerde die rote
			# Zone in den Kurvenausgang hineinwachsen, wo der Fahrer schon
			# wieder beschleunigt.
			var v_end: float = target_speed[wrapi(j - 1, 0, n)]
			var steps := 0
			while span < min_length and steps < n:
				steps += 1
				var back: int = wrapi(start - 1, 0, n)
				if phase[back] == kind or target_speed[back] <= v_end + 0.5:
					break
				phase[back] = kind
				span += segments[back]
				start = back
			# Eine Zone, die sich nicht auf die Mindestlaenge strecken laesst
			# oder in der das Auto kaum langsamer wird, ist keine echte
			# Bremszone: sie wird zu "lupfen" herabgestuft, statt den Fahrer zu
			# einer Bremsung zu schicken, die nichts bringt.
			var drop: float = target_speed[wrapi(start - 1, 0, n)] - v_end
			if span < min_length or drop < 3.0:
				for f in range(start, j):
					phase[f] = LIFT
			i = maxi(j, start + 1)


## Der Punkt, auf den ein Auto in `look` Metern zielen soll.
func sample_ahead(pos: Vector3, look: float, hint: int = -1) -> Dictionary:
	var n := points.size()
	if n < 8:
		return {}
	var index: int = hint
	if index < 0 or index >= n:
		index = closest_index(pos)
	var spacing: float = maxf(length / float(n), 0.1)
	var steps: int = maxi(int(round(look / spacing)), 0)
	var i: int = wrapi(index + steps, 0, n)
	return {
		"point": points[i],
		"index": i,
		"tangent": _tangent_at_index(i),
		"target_speed": target_speed[i],
		"phase": phase[i],
	}


func closest_index(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in points.size():
		var d: float = points[i].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func closest_index_near(pos: Vector3, hint: int, span: int = 64) -> int:
	var n := points.size()
	if n == 0:
		return 0
	if hint < 0 or hint >= n:
		return closest_index(pos)
	var best := hint
	var best_d: float = points[hint].distance_squared_to(pos)
	for k in range(1, span + 1):
		var after: int = wrapi(hint + k, 0, n)
		var d_a: float = points[after].distance_squared_to(pos)
		if d_a < best_d:
			best_d = d_a
			best = after
		var before: int = wrapi(hint - k, 0, n)
		var d_b: float = points[before].distance_squared_to(pos)
		if d_b < best_d:
			best_d = d_b
			best = before
	if posmod(best - hint, n) >= span or posmod(hint - best, n) >= span:
		return closest_index(pos)
	return best


func tangent_at(i: int) -> Vector3:
	return _tangent_at_index(i)


## Meter bis zum naechsten Bremsbeginn. Steht das Auto schon in der Bremszone,
## kommt die Restlaenge der Zone heraus (0 = jetzt bremsen).
func brake_distance_from(index: int) -> float:
	var n := phase.size()
	if n == 0:
		return 0.0
	var i: int = wrapi(index, 0, n)
	if phase[i] == BRAKE:
		var rest := 0.0
		var j := i
		for _step in n:
			if phase[j] != BRAKE:
				break
			rest += segments[j]
			j = wrapi(j + 1, 0, n)
		return rest
	var total := 0.0
	for _step in n:
		i = wrapi(i + 1, 0, n)
		total += segments[wrapi(i - 1, 0, n)]
		if phase[i] == BRAKE:
			return total
	return INF


func offset_limit() -> float:
	return float(params["corridor"])


## Meter, die von diesem Punkt aus noch gebremst wird (fuer Tests/HUD).
func braking_distance(index: int) -> float:
	return brake_distance_from(index)


func phase_name(value: int) -> String:
	match value:
		BRAKE:
			return "BREMSEN"
		LIFT:
			return "LUPFEN"
		_:
			return "GAS"


func _max_abs(values: PackedFloat32Array) -> float:
	var m := 0.0
	for v in values:
		m = maxf(m, absf(v))
	return m
