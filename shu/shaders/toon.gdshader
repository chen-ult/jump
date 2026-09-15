shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// 卡通 Cel 着色:色阶化漫反射 + 边缘光
uniform vec3 albedo_color : source_color = vec3(0.9, 0.9, 0.9);
uniform float shade_steps : hint_range(1.0, 4.0) = 2.0;
uniform vec3 rim_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float bands = floor(clamp(ndl, 0.0, 1.0) * shade_steps) / max(shade_steps - 1.0, 1.0);
	float diff = mix(0.5, 1.0, clamp(bands, 0.0, 1.0));
	DIFFUSE_LIGHT += diff * ALBEDO * ATTENUATION * LIGHT_COLOR;
}

void fragment() {
	ALBEDO = albedo_color;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color * rim * rim_strength;
}
