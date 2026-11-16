shader_type spatial;
// Накладає малюнок скіна (вид збоку) на модель без UV-розгортки: проєкція збоку.
// Позиція на малюнку рахується з розмірів моделі, які передає weapon_switch.gd (_apply_ak_skin).
// Малюнок: ліворуч — приклад, праворуч — дульний зріз, зверху — верх зброї.

uniform sampler2D skin_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 u_axis = vec3(0.0, 1.0, 0.0);      // напрям «назад -> вперед» (вісь ствола)
uniform vec3 v_axis = vec3(0.0, 0.0, -1.0);     // напрям «вгору -> вниз»
uniform vec3 side_axis = vec3(1.0, 0.0, 0.0);   // вісь ширини (бічні грані = ті, що дивляться вздовж неї)
uniform vec2 u_range = vec2(-4.8648, 9.7781);   // (мінімум, розмір) уздовж u_axis
uniform vec2 v_range = vec2(-1.4641, 2.8522);   // (мінімум, розмір) уздовж v_axis
uniform vec3 base_color : source_color = vec3(0.03, 0.03, 0.035); // верх/низ/торці (там проєкція б розтягнулась)
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.55;

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec2 uv = vec2((dot(obj_pos, u_axis) - u_range.x) / u_range.y,
			(dot(obj_pos, v_axis) - v_range.x) / v_range.y);
	vec3 tex = texture(skin_texture, uv).rgb;
	float side = smoothstep(0.35, 0.8, abs(dot(normalize(obj_normal), side_axis)));
	ALBEDO = mix(base_color, tex, side) * brightness;
	ROUGHNESS = roughness_value;
}
