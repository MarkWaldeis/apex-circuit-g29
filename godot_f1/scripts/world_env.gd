extends RefCounted
## Sonne, Himmel und Nebel für beide Welten (Apex Circuit und die Fahrschule).
## Früher stand das in main.gd::_build_world(); jetzt teilen sich beide Szenen
## denselben Nachmittag.


static func build(parent: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# Warm, low-ish afternoon sun with a soft edge.
	sun.rotation_degrees = Vector3(-42, 38, 0)
	sun.light_color = Color(1.0, 0.95, 0.87)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_max_distance = 600.0
	parent.add_child(sun)

	var env := WorldEnvironment.new()
	env.name = "World"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# Late-afternoon race light: warm horizon, deeper blue overhead.
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.78)
	sky_mat.sky_horizon_color = Color(0.85, 0.80, 0.72)
	sky_mat.ground_bottom_color = Color(0.07, 0.12, 0.06)
	sky_mat.ground_horizon_color = Color(0.24, 0.32, 0.18)
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.75
	environment.fog_enabled = true
	environment.fog_density = 0.0009
	environment.fog_light_color = Color(0.78, 0.80, 0.86)
	environment.fog_sky_affect = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_radius = 3.0
	environment.ssao_intensity = 1.4
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.15
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	environment.adjustment_contrast = 1.05
	env.environment = environment
	parent.add_child(env)
