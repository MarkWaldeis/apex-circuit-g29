extends Node3D
## Blitzer: ueberwacht eine Strassenstelle; loest er aus, blitzt das
## Licht kurz auf und der Fahrlehrer bekommt ein Signal.

var watch := Vector2.ZERO    ## ueberwachte Fahrbahnstelle
var limit := 50              ## erlaubte km/h
var _flash := 0.0
var _cool := 0.0
var _flash_light: OmniLight3D


func setup(p_watch: Vector2, p_limit: int) -> void:
	watch = p_watch
	limit = p_limit


func _ready() -> void:
	# Mast.
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.06
	cyl.height = 3.0
	pole.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.57, 0.6)
	pole.material_override = m
	pole.position = Vector3(0, 1.5, 0)
	add_child(pole)
	# Gehaeuse (Radarkasten) in Richtung Fahrbahn.
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.8, 0.4)
	box.mesh = bm
	var mb := StandardMaterial3D.new()
	mb.albedo_color = Color(0.8, 0.8, 0.75)
	box.material_override = mb
	box.position = Vector3(0, 2.9, 0)
	add_child(box)
	# Linse zeigt zum Beobachtungspunkt.
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.09
	lm.bottom_radius = 0.09
	lm.height = 0.06
	lens.mesh = lm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.05, 0.05, 0.07)
	lens.material_override = mm
	lens.position = Vector3(0, 2.9, 0.23)
	lens.rotation.x = PI / 2.0
	add_child(lens)
	_flash_light = OmniLight3D.new()
	_flash_light.omni_range = 22.0
	_flash_light.light_energy = 30.0
	_flash_light.position = Vector3(0, 3.2, 0)
	_flash_light.visible = false
	add_child(_flash_light)


func _physics_process(delta: float) -> void:
	_cool = maxf(_cool - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	if is_instance_valid(_flash_light):
		_flash_light.visible = _flash > 0.0


## Rueckgabe true = ausgeloest (Fahrlehrer darf schimpfen).
func check(p2: Vector2, kmh: float) -> bool:
	if _cool > 0.0:
		return false
	if absf(p2.x - watch.x) < 7.0 and absf(p2.y - watch.y) < 5.0 \
			and kmh > float(limit) + 4.0:
		_cool = 8.0
		_flash = 0.35
		return true
	return false
