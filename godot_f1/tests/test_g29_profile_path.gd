extends SceneTree
## Ein Diagnose- oder Messlauf darf das Lenkrad-Profil des Fahrers nicht
## ueberschreiben.
##
## Hintergrund (gemessen am 21.09.2026): `tools/ffb_direction_check.ps1` und
## `tests/probe_ffb_steer.gd` koennen nicht headless laufen - headless zaehlt
## Godot keine Joysticks auf. Der Headless-Schutz in `save_profile()` greift
## dort also nicht, und der Richtungstest schrieb `user://g29_profile.json`
## neu (im Log: "G29 profile saved: ..." mitten im Prueflauf), samt neu
## gelernter Pedal-Ruheposition. Diese Datei prueft den Riegel dagegen:
## `APEX_G29_PROFILE` verlegt den Pfad, der echte bleibt unberuehrt.
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 `
##       --script tests/test_g29_profile_path.gd

const G29Input := preload("res://scripts/g29_input.gd")

const REAL_PATH := "user://g29_profile.json"
const DIAG_PATH := "user://g29_profile_path_test.json"

var failed: int = 0
var checks: int = 0


func _initialize() -> void:
	OS.set_environment("APEX_G29_PROFILE", "")
	_run()
	quit(1 if failed > 0 else 0)


func _check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _run() -> void:
	# 1. Ohne Umgebungsvariable bleibt es beim echten Pfad.
	var plain := G29Input.new()
	plain.sim_enabled = true
	plain.auto_load_profile = false
	_check(plain.profile_path == REAL_PATH, "ohne_umgebungsvariable_bleibt_der_echte_pfad",
		"profile_path=%s" % plain.profile_path)

	# 2. Mit APEX_G29_PROFILE wandert der Pfad, bevor irgendetwas speichert.
	OS.set_environment("APEX_G29_PROFILE", DIAG_PATH)
	var diag := G29Input.new()
	diag.sim_enabled = true
	diag.auto_load_profile = false
	root.add_child(diag)          # _ready() liest die Umgebungsvariable
	_check(diag.profile_path == DIAG_PATH, "umgebungsvariable_verlegt_den_pfad",
		"profile_path=%s" % diag.profile_path)

	# 3. Der Diagnosepfad ist wirklich der, in den geschrieben wird - und der
	#    echte bleibt byte-gleich.
	var real_before: String = _read(REAL_PATH)
	var real_mtime_before: int = _mtime(REAL_PATH)
	diag.steer_axis = 0
	diag.throttle_axis = 2
	diag.brake_axis = 3
	diag.clutch_axis = 1
	if FileAccess.file_exists(DIAG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIAG_PATH))
	diag.save_profile()
	_check(FileAccess.file_exists(DIAG_PATH), "speichern_landet_im_diagnosepfad",
		"Datei %s existiert: %s" % [DIAG_PATH, str(FileAccess.file_exists(DIAG_PATH))])
	_check(FileAccess.file_exists(DIAG_PATH), "diagnosedatei_existiert", DIAG_PATH)
	_check(_read(REAL_PATH) == real_before and _mtime(REAL_PATH) == real_mtime_before,
		"echtes_profil_bleibt_unberuehrt",
		"Inhalt gleich: %s, Zeitstempel %d -> %d" % [
			str(_read(REAL_PATH) == real_before), real_mtime_before, _mtime(REAL_PATH)])

	# 4. Und die Gegenprobe: mit dem echten Pfad plus Simulationsmodus wird
	#    gar nicht geschrieben (der bestehende Riegel).
	var guarded := G29Input.new()
	guarded.sim_enabled = true
	guarded.auto_load_profile = false
	guarded.profile_path = REAL_PATH
	var real_mtime_guarded: int = _mtime(REAL_PATH)
	guarded.save_profile()
	_check(_mtime(REAL_PATH) == real_mtime_guarded,
		"simulationslauf_schreibt_das_echte_profil_nicht",
		"Zeitstempel %d -> %d" % [real_mtime_guarded, _mtime(REAL_PATH)])

	_cleanup()
	print("G29_PROFILE_PATH %s %d Pruefungen" % ["PASS" if failed == 0 else "FAIL", checks])


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _mtime(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	return FileAccess.get_modified_time(path)


func _cleanup() -> void:
	OS.set_environment("APEX_G29_PROFILE", "")
	for path in [DIAG_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
