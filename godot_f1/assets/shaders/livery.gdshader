// F1 livery: coloured bodywork over a carbon floor pan, with a waist-line
// accent stripe. The GLB exports no base colour at all (its paint material is
// a procedural Blender node graph), so the paint is applied here in model space.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 paint_color : source_color = vec3(0.72, 0.05, 0.08);
uniform vec3 accent_color : source_color = vec3(0.95, 0.95, 0.95);
uniform vec3 carbon_color : source_color = vec3(0.020, 0.020, 0.024);
uniform float floor_split = 0.34;
uniform float waist_height = 0.60;
uniform float waist_width = 0.028;
uniform float paint_metallic = 0.28;
uniform float paint_roughness = 0.18;

varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	float carbon = 1.0 - smoothstep(floor_split - 0.03, floor_split + 0.03, model_pos.y);
	vec3 base = mix(paint_color, carbon_color, carbon);
	float stripe = 1.0 - smoothstep(waist_width, waist_width + 0.014, abs(model_pos.y - waist_height));
	base = mix(base, accent_color, stripe * (1.0 - carbon) * 0.8);
	ALBEDO = base;
	METALLIC = mix(paint_metallic, 0.30, carbon);
	ROUGHNESS = mix(paint_roughness, 0.45, carbon);
	CLEARCOAT = 0.85 * (1.0 - carbon);
	CLEARCOAT_ROUGHNESS = 0.06;
}
