extends RefCounted
## Force-feedback settings, shared by the car (model), the wheel (soft lock),
## the menu (editing) and the HUD (display).
##
## The official F1 game exposes exactly this set of knobs (see
## docs/FFB_F1_STYLE_PLAN.md): a master strength, a wheel damper, the
## vibration effects and the maximum wheel rotation. The defaults here are the
## ones the guides arrive at after turning the game's 100 % defaults down:
## enough force to feel the car, not so much that the wheel clips and goes
## numb, and a rotation of 400 degrees instead of the G29's 900.
##
## OWNER: ROOT (workstream "Lenkrad-Gefuehl").

const PATH := "user://ffb_settings.json"
## Version 2: `invert` hat jetzt einen gemessenen Standardwert. Dateien der
## Version 1 kannten die Messung noch nicht und werden beim Laden migriert
## (siehe `load_profile`).
## Version 3: dazu `invert_source` - woher die Kraftrichtung kommt. Steht dort
## "fahrer", hat der Fahrer den Schalter im Menue selbst gestellt; dann darf
## die Selbstmessung (`ffb_link.gd::measure_direction`) ihn nicht mehr
## ueberschreiben. Ohne dieses Feld haette die Automatik eine bewusste
## Entscheidung still umgeworfen.
const VERSION := 3
## Ein Testlauf kann seine eigene Einstellungsdatei mitgeben. Ohne das haengt
## jede Messung an dem, was der Fahrer im Menue zuletzt eingestellt hat - ein
## Prueflauf mit "FFB AUS" hat dann keine Kraft gemessen und die Kette fuer
## kaputt erklaert, obwohl nur der Schalter im Menue aus war.
const ENV_PATH := "APEX_FFB_SETTINGS"

## The G29/G920's own range, i.e. what G HUB must be set to. The game then
## maps `rotation_deg` onto this range in software and makes the end stop
## itself - the same thing F1 24/25 do ("has a proper soft lock").
const WHEEL_RANGE_DEG := 900.0
## Offered steering rotations, in degrees of real wheel turning.
const ROTATIONS := [360.0, 400.0, 450.0, 900.0]
## Master gain steps (percent) and the damper steps.
const GAINS := [0.30, 0.45, 0.60, 0.75, 0.90, 1.00]
const DAMPERS := [0.45, 0.70, 1.00]
const DAMPER_NAMES := ["NIEDRIG", "MITTEL", "HOCH"]
## Die Rüttel-Bänder in 10-%-Schritten, wie der Schieberegler im offiziellen
## Spiel (0 = aus). Drei getrennte Bänder — On Track, Rumble Strip, Off Track —,
## weil F1 24/25 genau diese drei Regler hat und die Guides sie unterschiedlich
## setzen (z. B. On Track 60, Rumble Strip 60, Off Track 55). Ein einzelner
## An/Aus-Schalter kann das nicht abbilden: wer den Kerb behalten, aber das
## grobe Kies-Mahlen loswerden will, braucht zwei Zahlen.
const EFFECT_STEPS := [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

var enabled: bool = true
var gain: float = 0.75
var damper: float = 0.70
var effects: bool = true
## Die drei Rüttel-Bänder (`effects` bleibt der Hauptschalter davor). Standard
## 100 % je Band: damit sind alle im Plan gemessenen Zahlen unverändert gültig,
## und der Fahrer dreht nur das herunter, was ihn stört.
var ontrack_effects: float = 1.0
var kerb_effects: float = 1.0
var offtrack_effects: float = 1.0
var rotation_deg: float = 400.0
## Kraftrichtung umdrehen.
##
## Die ganze Kette ist so definiert: `torque > 0` heisst "drueckt das Lenkrad
## nach rechts". Ob eine positive DirectInput-Kraft das auf **dieser** Hardware
## wirklich tut, ist gemessen worden (`tools/ffb_hw_probe.py`, 21.09.2026):
## eine positive Kraft faehrt die G29-Achse zum **Minimum**, und laut
## Kalibrierung des Fahrers ist "rechts" das **Maximum** (`steer_invert: false`
## im Profil). Auf diesem Lenkrad muss das Vorzeichen also umgedreht werden -
## sonst zieht das Rad im Bogen nach links statt nach rechts.
##
## Der Schalter im Menue bleibt: andere Firmware, ein anderes Rad oder ein
## Treiberwechsel kann das umdrehen. `tools/ffb_direction_check.ps1` misst es
## in ein paar Sekunden nach.
var invert: bool = true
## "auto" (noch von der Messung zu bestaetigen) oder "fahrer" (im Menue
## gestellt). Nur "auto" erlaubt der Selbstmessung, den Wert zu aendern.
var invert_source: String = "auto"
## Diagnostics for the tests: True once a profile was written or read.
var loaded: bool = false
var saved: int = 0
var auto_save: bool = true
var path: String = PATH


func _init() -> void:
	var override: String = OS.get_environment(ENV_PATH)
	if override != "":
		path = override


func load_profile() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	enabled = bool(d.get("enabled", enabled))
	gain = clampf(float(d.get("gain", gain)), 0.0, 1.0)
	damper = clampf(float(d.get("damper", damper)), 0.0, 1.0)
	effects = bool(d.get("effects", effects))
	ontrack_effects = clampf(float(d.get("ontrack_effects", ontrack_effects)), 0.0, 1.0)
	kerb_effects = clampf(float(d.get("kerb_effects", kerb_effects)), 0.0, 1.0)
	offtrack_effects = clampf(float(d.get("offtrack_effects", offtrack_effects)), 0.0, 1.0)
	# Migration: Dateien der Version 1 wurden geschrieben, bevor die
	# Kraftrichtung am echten Lenkrad gemessen war. Ihr `invert` ist deshalb
	# nicht die Meinung des Fahrers, sondern nur der alte Standard - er wird
	# durch den gemessenen ersetzt. Ab Version 2 gilt, was in der Datei steht.
	var file_version: int = int(d.get("version", 1))
	if file_version >= 2:
		invert = bool(d.get("invert", invert))
	# Ab Version 3 steht dabei, woher die Richtung kommt. Dateien der aelteren
	# Staende kennen das Feld nicht; ihre Richtung galt als "noch nicht
	# bestaetigt" und darf von der Selbstmessung nachgezogen werden.
	invert_source = String(d.get("invert_source", invert_source))
	if invert_source != "fahrer":
		invert_source = "auto"
	var rot: float = float(d.get("rotation_deg", rotation_deg))
	rotation_deg = rot if ROTATIONS.has(rot) else 400.0
	loaded = true
	# Eine migrierte Datei wird gleich zurueckgeschrieben: sonst stand auf der
	# Platte weiter `version 1` mit dem alten `invert`, obwohl das Spiel schon
	# mit dem gemessenen Wert faehrt - und niemand konnte von aussen sehen,
	# welche Richtung nun gilt (die Datei des Fahrers stand am 21.09. genau so
	# da). `auto_save` schuetzt Testlaeufe.
	if file_version < VERSION:
		save_profile()
	return true


func save_profile() -> bool:
	if not auto_save:
		return false
	# Ein Testlauf darf die eingestellte Staerke des Fahrers nicht
	# ueberschreiben (dieselbe Regel wie beim Lenkrad-Profil in
	# `g29_input.gd`): im Headless-Betrieb wird die echte Einstellungsdatei
	# nie geschrieben. Wer messen will, gibt mit `APEX_FFB_SETTINGS` eine
	# eigene Datei mit.
	if path == PATH and DisplayServer.get_name() == "headless":
		push_warning("FFB settings: headless run does not write " + PATH)
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"version": VERSION,
		"enabled": enabled,
		"gain": snappedf(gain, 0.001),
		"damper": snappedf(damper, 0.001),
		"effects": effects,
		"ontrack_effects": snappedf(ontrack_effects, 0.001),
		"kerb_effects": snappedf(kerb_effects, 0.001),
		"offtrack_effects": snappedf(offtrack_effects, 0.001),
		"invert": invert,
		"invert_source": invert_source,
		"rotation_deg": rotation_deg,
	}))
	f.close()
	saved += 1
	return true


## How much of the physical wheel travel is used for the game's full lock.
## 400 degrees of 900 means: a quarter turn of the real wheel is already full
## lock, exactly like an F1 car's steering rack.
func lock_fraction() -> float:
	var rot: float = clampf(rotation_deg, 180.0, WHEEL_RANGE_DEG)
	return rot / WHEEL_RANGE_DEG


## Kraftrichtung setzen. `source` sagt, woher sie kommt: "fahrer" (Schalter im
## Menue) oder "gemessen" (Selbstmessung in `ffb_link.gd`). Steht "fahrer" in
## der Datei, laesst die Automatik den Wert in Ruhe - eine bewusste
## Entscheidung darf nicht still umgeworfen werden.
func set_invert(value: bool, source: String = "fahrer") -> void:
	invert = value
	invert_source = source if source == "fahrer" or source == "gemessen" else "auto"
	save_profile()


## Halber physischer Lenkradweg in Grad (G29 in G HUB auf 900 -> 450).
func wheel_half_range_deg() -> float:
	return WHEEL_RANGE_DEG * 0.5


## Halber Lenkbereich des Spiels in Grad (400 -> 200 pro Seite).
func lock_half_deg() -> float:
	return clampf(rotation_deg, 180.0, WHEEL_RANGE_DEG) * 0.5


func cycle_gain() -> void:
	gain = _next_step(GAINS, gain)
	save_profile()


func cycle_damper() -> void:
	damper = _next_step(DAMPERS, damper)
	save_profile()


func cycle_rotation() -> void:
	rotation_deg = _next_step(ROTATIONS, rotation_deg)
	save_profile()


func toggle_enabled() -> void:
	enabled = not enabled
	save_profile()


func toggle_effects() -> void:
	effects = not effects
	save_profile()


## Die drei Bänder des offiziellen Spiels. Ein Klick geht eine Stufe weiter
## (0 %, 10 % … 100 %) und laeuft dann wieder auf 0 zurueck.
func cycle_ontrack_effects() -> void:
	ontrack_effects = _next_step(EFFECT_STEPS, ontrack_effects)
	save_profile()


func cycle_kerb_effects() -> void:
	kerb_effects = _next_step(EFFECT_STEPS, kerb_effects)
	save_profile()


func cycle_offtrack_effects() -> void:
	offtrack_effects = _next_step(EFFECT_STEPS, offtrack_effects)
	save_profile()


## Bequemer Zugriff fuer das Modell: Band 0 = Asphalt-Textur,
## 1 = Kerb, 2 = Gras/Kies.
func band_scale(band: int) -> float:
	match band:
		1:
			return clampf(kerb_effects, 0.0, 1.0)
		2:
			return clampf(offtrack_effects, 0.0, 1.0)
		_:
			return clampf(ontrack_effects, 0.0, 1.0)


func gain_label() -> String:
	return "%d %%" % int(round(gain * 100.0))


func damper_label() -> String:
	return DAMPER_NAMES[clampi(_step_index(DAMPERS, damper), 0, DAMPER_NAMES.size() - 1)]


func rotation_label() -> String:
	return "%d°" % int(round(rotation_deg))


func enabled_label() -> String:
	return "AN" if enabled else "AUS"


func effects_label() -> String:
	return "AN" if effects else "AUS"


func ontrack_label() -> String:
	return _percent_label(ontrack_effects)


func kerb_label() -> String:
	return _percent_label(kerb_effects)


func offtrack_label() -> String:
	return _percent_label(offtrack_effects)


func _percent_label(value: float) -> String:
	return "%d %%" % int(round(value * 100.0))


func _next_step(steps: Array, current: float) -> float:
	var index: int = _step_index(steps, current)
	return float(steps[(index + 1) % steps.size()])


func _step_index(steps: Array, current: float) -> int:
	var best: int = 0
	var best_dist: float = INF
	for i in steps.size():
		var dist: float = absf(float(steps[i]) - current)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best
