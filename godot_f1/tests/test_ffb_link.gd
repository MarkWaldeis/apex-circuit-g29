extends SceneTree
## End-to-end proof for the force feedback channel.
##
## The game cannot make a G29 move by itself (Godot has no FFB API), so the
## whole feature rests on one seam: `scripts/ffb_link.gd` has to put the right
## numbers on UDP 127.0.0.1:5601, where `tools/g29_ffb.py` picks them up and
## turns them into real force.
##
## This test plays the part of that helper: it opens the port the helper
## listens on, drives the real scene headless and checks the packets that
## arrive. A silent seam (packets never sent, wrong keys, values out of range)
## fails here instead of failing at the wheel.
##
## Der Lauf muss lang genug sein, um in einen schnellen Bogen zu kommen: in den
## ersten Sekunden rollt der Wagen nur an, dort ist die Kraft klein. Vorher
## stand hier eine Schwelle von 0,02 - die haette auch dann noch bestanden,
## wenn die Kraft im Bogen auf zwei Prozent zusammengebrochen waere (gemessen
## in der Welle-2-Pruefung: 0,163 nach 3,6 s, Schwelle 0,02). Jetzt laeuft der
## Wagen 14 s (der erste schnelle Bogen liegt bei rund 430 m) und die Kraft
## muss im Bogen wirklich anliegen.
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/test_ffb_link.gd

## Eigener Port: laeuft parallel ein Spiel oder ein anderer Lauf, wuerde dieser
## Test sonst fremde Pakete mitzaehlen (und sie als "kaputt" melden).
const PORT := 5611
## Ist der Wunschport belegt - z. B. weil der Helfer fuer das Spiel laeuft -
## weicht der Test auf den naechsten freien Port aus und sagt das im Bericht.
## Ein Test, der deshalb rot wird, obwohl der Kanal in Ordnung ist, waere ein
## Fehlalarm; ein Test, der deshalb *gruen* wird, waere schlimmer (genau das
## war das alte "SKIP" mit Exit 0). Deshalb: ausweichen oder ehrlich FAIL.
const PORT_FALLBACKS := [5612, 5613, 5614, 5721, 5722, 5723]
## 14 s bei 90 Hz: der Autopilot hat dann den ersten schnellen Bogen erreicht.
const RUN_FRAMES := 1260
## Wann der Test einen Schaltstoss ausloest (muss vor RUN_FRAMES liegen).
const SHIFT_FRAME := 300
## Das Lenkrad ist im Bogen schwer: die Grundkraft aus `ffb_model.gd` liegt bei
## 1 g Querlast 0,47 und bei 3,5 g 0,83 (tests/test_ffb_model.gd), die
## Standardstaerke im Menue ist 0,75. Im Bogen muss also deutlich mehr als
## nichts ankommen - 0,30 ist die Untergrenze, gemessen wird der Ist-Wert.
const CORNER_FLOOR := 0.30
## Ein Schaltstoss (`poke("shift", 0.6)`) muss als Puls ankommen, nicht als
## Dauerzustand.
const PULSE_FLOOR := 0.30

var listener: PacketPeerUDP
var main: Node3D
var car
var frames: int = 0
var packets: int = 0
var bad: int = 0
var max_force: float = 0.0
var max_damp: float = 0.0
var max_rumble: float = 0.0
var min_hz: float = 999.0
var max_hz: float = 0.0
## Kraft gegen den Lenkbefehl: das Lenkrad zieht dagegen, es dreht sich nicht
## von selbst in die Kurve hinein.
var corner_ticks: int = 0
var corner_oppose: int = 0
var max_pulse: float = 0.0
var pulse_packets: int = 0
var events: Dictionary = {}
var real_sources: Dictionary = {}
var gains: Dictionary = {}
var sources: Dictionary = {}
var versions: Dictionary = {}
var seen_keys: Dictionary = {}
var failed: int = 0
## Der Port, auf dem dieser Lauf wirklich gemessen hat.
var port_used: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	listener = PacketPeerUDP.new()
	for candidate in [PORT] + PORT_FALLBACKS:
		if listener.bind(int(candidate), "127.0.0.1") == OK:
			port_used = int(candidate)
			break
	if port_used == 0:
		# Frueher stand hier ein "SKIP" mit Exit-Code 0. Damit konnte ein
		# kaputter Kanal unbemerkt durchgehen, sobald irgendein alter Prozess
		# den Port hielt: der Test hat dann nichts gemessen und trotzdem
		# Erfolg gemeldet. Ein Test, der nicht messen kann, ist kein
		# bestandener Test - er weicht aus, und wenn auch das nicht geht, FAIL.
		push_error("FFB FAIL Ports %s alle belegt - laeuft noch ein Helfer oder ein alter Lauf? "
			% str([PORT] + PORT_FALLBACKS)
			+ "Ohne freien Port kann dieser Test die Kette nicht pruefen.")
		print("FFB FAIL port_busy ", str([PORT] + PORT_FALLBACKS))
		quit(1)
		return
	# Muss vor dem Laden der Szene stehen: `ffb_link.setup()` liest den Port.
	OS.set_environment("APEX_FFB_PORT", str(port_used))
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	car = main.get("player")
	# Diesen Lauf darf die gespeicherte Fahrer-Einstellung nicht steuern.
	# Beim Pruefen von Welle 3 stand im echten Profil
	# `user://ffb_settings.json` ein `enabled:false` (jemand hatte im Menue
	# abgeschaltet, und das Spiel speichert das). Danach lieferte dieser Test
	# `Kraftspitze 0.000 | Quellen ["aus"]` und war rot - obwohl die Kette in
	# Ordnung war. Ein Test, dessen Ergebnis davon abhaengt, was der Fahrer
	# zuletzt im Menue gedrueckt hat, misst nicht die Kette. Also: Eingang
	# festnageln (Kraft an, Baender voll, Standardstaerke) und im Testlauf
	# nichts speichern (`main.gd` setzt `auto_save` headless auf false).
	var pinned = main.get("ffb_settings")
	if pinned != null:
		pinned.enabled = true
		pinned.gain = 0.75
		pinned.effects = true
		pinned.ontrack_effects = 1.0
		pinned.kerb_effects = 1.0
		pinned.offtrack_effects = 1.0
		pinned.invert = false
		pinned.rotation_deg = 400.0
	var menu = main.get("menu")
	if menu and menu.has_method("headless_autostart"):
		menu.headless_autostart()
	if car:
		# Der Autopilot faehrt die Ideallinie - nur so kommt der Wagen in die
		# schnellen Boegen, in denen das Lenkrad schwer wird. Ohne ihn faehrt
		# der Wagen geradeaus (frueher stand hier nur ein `script_throttle`):
		# gemessen kam dabei eine Kraftspitze von 0,05 bis 0,16 an, und die
		# Schwelle von 0,02 im alten Test war nie in Gefahr.
		car.auto_drive = true
		car.remove_meta("headless_gas")
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	_drain()
	if frames == SHIFT_FRAME:
		# Einen Schaltstoss ausloesen: er muss als Puls im Paket ankommen.
		# (Frueher stand hier ein `car.steering = 0.18` - das war wirkungslos:
		# der Autopilot schreibt `steering` in seinem eigenen `_physics_process`
		# und ueberschreibt den Wert sofort wieder. Der Wagen faehrt ohnehin
		# selbst in die Boegen, genau das wird jetzt gemessen.)
		if car and car.ffb:
			car.ffb.poke("shift", 0.6)
	if frames >= RUN_FRAMES:
		_drain()
		_report()


func _drain() -> void:
	if listener == null:
		return
	while listener.get_available_packet_count() > 0:
		var raw: PackedByteArray = listener.get_packet()
		var txt: String = raw.get_string_from_utf8()
		var data = JSON.parse_string(txt)
		if typeof(data) != TYPE_DICTIONARY:
			bad += 1
			continue
		packets += 1
		var d: Dictionary = data
		if packets % 6 == 1:
			# Wie der echte Helfer antworten: `tools/g29_ffb.py` schickt mit
			# `ACK_PERIOD` 0,1 s ein Lebenszeichen zurueck, also etwa jedes
			# sechste Paket bei 60 Hz. Das Spiel muss das lesen - daran haengt
			# der HUD-Hinweis "kein Helfer", und ohne ihn waere ein totes
			# Lenkrad unsichtbar. (Nur einmal zu antworten reicht nicht: dann
			# waere der Helfer nach 1,5 s "verschwunden", obwohl er laeuft.)
			listener.set_dest_address(listener.get_packet_ip(),
				listener.get_packet_port())
			listener.put_packet(JSON.stringify({
				"v": 2, "ack": 1, "mode": "wheel",
			}).to_utf8_buffer())
		for key in ["v", "torque", "damper", "friction", "rumble", "rumble_hz",
				"pulse", "pulse_dir", "spring", "gain", "source"]:
			seen_keys[key] = true
			if not d.has(key):
				bad += 1
		versions[str(int(d.get("v", 0)))] = true
		sources[str(d.get("source", "-"))] = true
		gains[str(snappedf(float(d.get("gain", -1.0)), 0.01))] = true
		var torque: float = float(d.get("torque", 0.0))
		var pulse: float = float(d.get("pulse", 0.0))
		var source: String = String(d.get("source", "-"))
		var event: String = String(d.get("event", ""))
		if source != "-" and source != "":
			real_sources[source] = true
		if event != "":
			events[event] = int(events.get(event, 0)) + 1
		max_force = maxf(max_force, absf(torque))
		max_damp = maxf(max_damp, float(d.get("damper", 0.0)))
		max_rumble = maxf(max_rumble, float(d.get("rumble", 0.0)))
		max_pulse = maxf(max_pulse, pulse)
		if pulse > 0.02:
			pulse_packets += 1
		# Das Lenkrad zieht gegen den Lenkbefehl: der Wagen steht im Bogen,
		# also muss die Kraft gegen die eingeschlagene Richtung druecken.
		var steer_now: float = float(car.last_steer) if car else 0.0
		if absf(torque) > 0.05 and absf(steer_now) > 0.05:
			corner_ticks += 1
			if signf(torque) != signf(steer_now):
				corner_oppose += 1
		var hz: float = float(d.get("rumble_hz", 0.0))
		min_hz = minf(min_hz, hz)
		max_hz = maxf(max_hz, hz)
		if absf(torque) > 1.001:
			bad += 1
		for key in ["damper", "friction", "rumble", "pulse"]:
			if float(d.get(key, 0.0)) < 0.0 or float(d.get(key, 0.0)) > 1.001:
				bad += 1
		if hz < 5.0 or hz > 60.0:
			bad += 1
		if absf(float(d.get("pulse_dir", 0.0))) > 1.001:
			bad += 1


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _report() -> void:
	var seconds: float = float(frames) / float(Engine.physics_ticks_per_second)
	var sent_count: int = int(car.ffb.sent_packets) if car and car.ffb else -1
	# Die Rate wird gerechnet, nicht geschaetzt: 60 Hz im Protokoll heisst
	# 60 Pakete je Sekunde. Frueher stand hier nur "sent > 50", und der Kanal
	# sendete real 45 Hz (jeder zweite 90-Hz-Tick), ohne dass es auffiel.
	var rate: float = float(sent_count) / maxf(seconds, 0.001)
	_check(packets > 40, "udp_packets_arrive", "%d Pakete in %.1f s" % [packets, seconds])
	_check(rate >= 55.0 and rate <= 65.0, "the_car_sends_at_60_hz",
		"%.1f Pakete/s (sent=%d in %.1f s)" % [rate, sent_count, seconds])
	_check(bad == 0, "packets_are_well_formed", "bad=%d" % bad)
	_check(seen_keys.size() >= 10, "protocol_v2_keys_present", str(seen_keys.keys()))
	_check(versions.keys() == ["2"], "protocol_version_is_2", str(versions.keys()))
	# Die eine Zahl, die im offiziellen Spiel das Fahrgefuehl ausmacht: im
	# Bogen ist das Lenkrad schwer. 0,02 waere auch bei einem toten Kanal
	# bestanden (gemessen in Welle 2: 0,163 nach 3,6 s).
	_check(max_force >= CORNER_FLOOR, "the_wheel_gets_heavy_in_the_corner",
		"Spitze %.3f (Schwelle %.2f) ueber %d Ticks" % [max_force, CORNER_FLOOR,
			corner_ticks])
	# Kriterium 2/3 des Plans: die Kraft zieht gegen den Lenkbefehl, sie dreht
	# sich nicht in die Kurve hinein.
	_check(corner_ticks >= 30
			and float(corner_oppose) >= 0.80 * float(corner_ticks),
		"the_force_pulls_against_the_steering",
		"%d von %d Ticks (%.0f %%)" % [corner_oppose, corner_ticks,
			100.0 * float(corner_oppose) / maxf(float(corner_ticks), 1.0)])
	_check(max_damp > 0.15, "damping_grows_with_speed", "max_damp=%.3f" % max_damp)
	# Vorher stand hier `max_rumble >= 0.0` - das kann nie fehlschlagen und
	# haette einen toten Ruettel-Kanal durchgehen lassen. Die Asphalt-Textur
	# allein liegt bei rund 0,11 (tests/probe_review_root.gd).
	_check(max_rumble > 0.03, "rumble_channel_available", "max_rumble=%.3f" % max_rumble)
	_check(min_hz >= 5.0 and max_hz <= 60.0 and max_hz > 0.0,
		"rumble_frequency_is_sent", "%.1f .. %.1f Hz" % [min_hz, max_hz])
	# Kriterium 7: der Schaltstoss kommt als Puls an - und als Puls, nicht als
	# Dauerzustand (er klingt im Helfer in rund 200 ms ab).
	_check(max_pulse >= PULSE_FLOOR and max_pulse <= 1.001,
		"a_jolt_reaches_the_wheel", "Puls %.2f in %d Paketen" % [max_pulse, pulse_packets])
	_check(events.has("shift"), "the_packet_names_the_event", str(events.keys()))
	# Das Feld `gain` im Paket ist die Zusatzverstaerkung des Helfers und bleibt
	# neutral (1.0) - die Staerke aus dem Menue steckt schon in `torque`. Sonst
	# wuerde sie zweimal angewendet (das war ein echter Mangel, siehe
	# docs/reviews/ffb_f1_style.md).
	_check(gains.size() == 1 and gains.has("1.0"),
		"the_packet_does_not_scale_the_force_twice", "gain=%s" % str(gains.keys()))
	# Der Rueckkanal: der Helfer antwortet, das Spiel liest die Antwort. Ohne
	# das koennte das HUD nicht sagen, ob ueberhaupt jemand zuhoert (ein totes
	# Lenkrad war bis Welle 3 unsichtbar).
	_check(int(car.ffb.helper_acks) > 0, "the_game_reads_the_helpers_life_sign",
		"%d Lebenszeichen, Modus %s" % [int(car.ffb.helper_acks), car.ffb.helper_mode])
	_check(String(car.ffb.helper_mode) == "wheel" and bool(car.ffb.helper_alive()),
		"the_life_sign_is_understood", "mode=%s alive=%s" % [
			car.ffb.helper_mode, str(car.ffb.helper_alive())])
	# `source` ist der Grund, warum das Lenkrad gerade tut, was es tut. "-"
	# heisst "keine Angabe" - das reicht nicht.
	_check(real_sources.size() >= 1, "the_packet_says_where_the_force_comes_from",
		"%s (alle: %s)" % [str(real_sources.keys()), str(sources.keys())])
	# Und der Kanal darf nicht stummgeschaltet sein: `source` "aus" heisst, das
	# Modell hat die Kraft selbst abgeschaltet. Dann sind alle Zahlen darunter
	# Null, und der Lauf misst nichts. Genau das passierte in Welle 3, als im
	# gespeicherten Profil `enabled:false` stand - dieser Test war rot, obwohl
	# die Kette in Ordnung war. Jetzt wird der Zustand ausdruecklich geprueft.
	_check(not real_sources.has("aus") and not sources.has("aus"),
		"the_channel_is_not_muted", str(sources.keys()))
	# Und im Paket steht genau die Kraft, die das Modell gerechnet hat - keine
	# zweite Verstaerkung auf dem Weg (das war ein echter Mangel, gemessen:
	# 30 % Einstellung kamen als 9 % am Lenkrad an).
	var sent: float = absf(float(car.ffb.last_packet.get("torque", 0.0))) if car and car.ffb else -1.0
	var computed: float = absf(float(car.ffb.last_state.get("torque", 0.0))) if car and car.ffb else -2.0
	# Das Paket schneidet die Kraft auf 0,001 ab (`snappedf`), das Modell nicht.
	# `is_equal_approx` mit seiner 1e-5-Toleranz konnte deshalb nur zufaellig
	# bestehen - in der Welle-2-Pruefung schlug genau das fehl, obwohl Paket und
	# Modell auf drei Stellen gleich waren (0,044). Verglichen wird jetzt mit
	# der halben Schnittstelle.
	var force_gap: float = absf(sent - computed)
	_check(force_gap <= 0.0006, "packet_carries_the_force_unchanged",
		"Paket %.3f = Modell %.3f (Abweichung %.4f)" % [sent, computed, force_gap])
	print("FFB_KETTE %.1f s: Kraftspitze %.3f | gegen Lenkbefehl %d/%d (%.0f %%)"
		% [seconds, max_force, corner_oppose, corner_ticks,
			100.0 * float(corner_oppose) / maxf(float(corner_ticks), 1.0)]
		+ " | Puls %.2f in %d Paketen | Quellen %s | Rütteln %.3f"
		% [max_pulse, pulse_packets, str(real_sources.keys()), max_rumble]
		+ " (Port %d)" % port_used)
	if failed > 0:
		print("FFB FAIL count=", failed)
		quit(1)
	else:
		print("FFB PASS packets=", packets, " sent=", int(car.ffb.sent_packets))
		quit(0)
