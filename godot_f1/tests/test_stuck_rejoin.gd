extends SceneTree
## Ein autonomes Auto, das neben der Strecke liegen bleibt, muss von allein
## zurueckfinden - ein Fahrer am Lenkrad aber nie angefasst werden.
##
## Gemessen am 21.09.2026 mit `tests/probe_lap_ffb.gd`: KI-Auto und Autopilot
## des Spielerautos fuhren nach rund 46 s einmal weit hinaus und standen dann
## **45 s lang bei 0 km/h im Kies** (13,9 m Querabstand, Nase zur Bande). Die
## Ideallinie liegt hinter der Wand, also steuerte der Autopilot dauerhaft in
## die Bande. Der alte Rundentest sah das nie, weil er nach 40 s endet.
##
## Geprueft werden drei Dinge:
##   1. ein autonomes Auto weit draussen wird zurueckgeholt und faehrt wieder,
##   2. ein Auto am Streckenrand (innerhalb der Grenze) wird **nicht** sofort
##      umgesetzt,
##   3. der Fahrer ohne Autopilot wird **nie** umgesetzt - er entscheidet
##      selbst, ob er rueckwaerts faehrt oder den Reset benutzt.
##
##   powershell -File tools/run_godot.ps1 --fixed-fps 300 --headless `
##       --path godot_f1 --script tests/test_stuck_rejoin.gd

const RacingLine = preload("res://scripts/racing_line.gd")

var main: Node3D
var line = RacingLine.new()
var player
var ai
var frames: int = 0
var failed: int = 0
var ai_placed_frame: int = 0
var player_placed_frame: int = 0
var ai_rejoin_before: int = 0
var player_rejoin_before: int = 0
var player_off_placed: float = 0.0
var ai_off_placed: float = 0.0


func _initialize() -> void:
	call_deferred("_boot")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _boot() -> void:
	if not line.load_json("res://assets/track/racing_line.json"):
		_check(false, "racing_line_loads")
		_finish()
		return
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	physics_frame.connect(_on_phys)


## Setzt ein Auto still und querab neben die Linie - so, wie es nach einem
## Ausflug liegen bleibt. `facing_wall` dreht die Nase von der Strecke weg;
## genau so stand das Auto in der echten Messung, und genau deshalb kam es
## nicht von allein weg (Gas geben hiess: in die Bande fahren).
func _strand(car, offset_m: float, facing_wall: bool) -> void:
	var i: int = line.closest_index(car.global_position)
	var left: Vector3 = line.left_at(i)
	var pos: Vector3 = line.points[i] + left * offset_m + Vector3(0.0, 0.35, 0.0)
	var t: Vector3 = line.flat_tangent(i)
	# Die Nase des Autos ist +Z; `looking_at` schaut nach -Z.
	var nose: Vector3 = left if facing_wall else t
	var basis := Basis.looking_at(-nose, Vector3.UP)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.global_transform = Transform3D(basis, pos)
	car.engine_force = 0.0


func _offset_of(car) -> float:
	if car == null or car.surfaces == null:
		return -1.0
	var s: Dictionary = car.surfaces.sample(car.global_position)
	return absf(float(s.get("offset", 0.0)))


func _on_phys() -> void:
	frames += 1
	if frames == 5:
		player = main.get("player")
		ai = main.get("ai_car")
		_check(player != null and ai != null, "beide_autos_existieren",
			"player=%s ai=%s" % [str(player != null), str(ai != null)])
		if player == null or ai == null:
			_finish()
			return
		ai_rejoin_before = int(ai.rejoin_count)
		player_rejoin_before = int(player.rejoin_count)
		return

	if frames == 10:
		# Notfall: das KI-Auto liegt weit draussen an der Bande, Nase zur Wand.
		_strand(ai, 14.5, true)
		ai.auto_drive = true
		ai_off_placed = _offset_of(ai)
		ai_placed_frame = frames
		# Und der Autopilot des Spielerautos am Streckenrand - hier darf nichts
		# sofort passieren.
		_strand(player, 6.0, true)
		player.auto_drive = true
		player_off_placed = _offset_of(player)
		print("STUCK platziert: KI %.2f m (Nase zur Wand), Autopilot %.2f m (am Rand)" % [
			ai_off_placed, player_off_placed])
		return

	# 4 s spaeter: das KI-Auto ist zurueck auf der Linie.
	if frames == ai_placed_frame + 240:
		var ai_off: float = _offset_of(ai)
		print("STUCK KI nach 4 s: Abstand=%.2f m Tempo=%.2f m/s Wiedereingliederungen=%d" % [
			ai_off, ai.linear_velocity.length(), int(ai.rejoin_count) - ai_rejoin_before])
		_check(int(ai.rejoin_count) - ai_rejoin_before >= 1,
			"das_ki_auto_wird_zurueckgeholt",
			"%d Wiedereingliederung(en)" % (int(ai.rejoin_count) - ai_rejoin_before))
		_check(ai_off >= 0.0 and ai_off <= 6.85,
			"das_ki_auto_steht_wieder_auf_der_strecke", "Abstand=%.2f m" % ai_off)
		_check(int(player.rejoin_count) - player_rejoin_before == 0,
			"kein_sofortiges_umsetzen_am_streckenrand",
			"%d Wiedereingliederung(en) in 4 s" % (int(player.rejoin_count) - player_rejoin_before))
		return

	# 8 s nach dem Ausflug faehrt das KI-Auto wieder richtig.
	if frames == ai_placed_frame + 480:
		var ai_speed: float = ai.linear_velocity.length()
		print("STUCK KI nach 8 s: Tempo=%.2f m/s Abstand=%.2f m" % [ai_speed, _offset_of(ai)])
		_check(ai_speed > 3.0, "das_ki_auto_faehrt_wieder_weiter",
			"%.2f m/s" % ai_speed)
		# Der Fahrer selbst: weit draussen, stehend, ohne Autopilot.
		_strand(player, 12.0, true)
		player.auto_drive = false
		player_off_placed = _offset_of(player)
		player_placed_frame = frames
		print("STUCK Fahrer platziert: %.2f m, Autopilot aus" % player_off_placed)
		return

	if player_placed_frame > 0 and frames == player_placed_frame + 240:
		var player_off: float = _offset_of(player)
		var rejoins: int = int(player.rejoin_count) - player_rejoin_before
		print("STUCK Fahrer nach 4 s: Abstand=%.2f m Wiedereingliederungen=%d" % [
			player_off, rejoins])
		_check(rejoins == 0, "der_fahrer_wird_nie_umgesetzt",
			"%d Wiedereingliederung(en)" % rejoins)
		_check(absf(player_off - player_off_placed) < 4.0,
			"der_fahrer_steht_noch_wo_er_war",
			"%.2f m statt %.2f m" % [player_off, player_off_placed])
		_finish()
		return

	if player_placed_frame > 0 and frames > player_placed_frame + 400:
		_check(false, "die_messung_haette_enden_muessen",
			"Frame %d erreicht, ohne dass die Pruefung lief" % frames)
		_finish()


func _finish() -> void:
	if failed > 0:
		print("STUCK_REJOIN FAIL count=%d" % failed)
		quit(1)
	else:
		print("STUCK_REJOIN PASS")
		quit(0)
