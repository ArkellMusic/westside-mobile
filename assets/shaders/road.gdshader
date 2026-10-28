shader_type spatial;
// Asfalto con marcas viales. UV.x = 0..1 a lo ancho, UV.y = metros a lo largo.
// UV2.x = longitud del tramo (m), UV2.y = ancho (m). Pasos de cebra en los extremos.
// UV2.y = 0 indica un cruce (sin marcas).

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 asphalt : source_color = vec3(0.16, 0.16, 0.17);
uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 5.0;

varying vec2 info;
varying vec3 wpos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	info = UV2;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 wp = UV;
	float len = info.x;
	float width = info.y;
	float grain = hash21(floor(vec2(wp.x * max(width, 1.0), wp.y) * 6.0));
	vec2 tuv = wpos.xz / tile;
	vec3 col = texture(asphalt_albedo, tuv).rgb * (asphalt / vec3(0.16)) * 0.9 * (0.94 + 0.12 * grain);
	float tex_rough = texture(asphalt_rough, tuv).g;
	// Manchas de desgaste en el centro de cada carril.
	col *= 1.0 - 0.06 * smoothstep(0.0, 0.5, sin(wp.x * 6.2831 * 2.0) * 0.5 + 0.5);
	float paint = 0.0;
	vec3 paint_col = vec3(0.92);

	if (width > 0.5) {
		float across = wp.x * width;
		// Doble línea amarilla central.
		float c = abs(across - width * 0.5);
		float yellow = step(0.10, c) * step(c, 0.25);
		// Líneas de borde blancas.
		float edge = step(0.35, across) * step(across, 0.5) + step(width - 0.5, across) * step(across, width - 0.35);
		// Separador de carriles discontinuo en vías anchas (2 carriles por sentido).
		float dash = 0.0;
		if (width >= 13.0) {
			float q = abs(abs(across - width * 0.5) - width * 0.25);
			dash = step(q, 0.08) * step(0.5, fract(wp.y / 6.0));
		}
		// Pasos de cebra cerca de los cruces.
		float zebra = 0.0;
		if (wp.y < 3.5 || wp.y > len - 3.5) {
			zebra = step(0.5, fract(across / 1.1)) * step(0.6, across) * step(across, width - 0.6);
			yellow = 0.0;
			dash = 0.0;
		}
		// Línea de detención.
		float stopl = (step(3.6, wp.y) * step(wp.y, 4.1) + step(len - 4.1, wp.y) * step(wp.y, len - 3.6));
		paint = clamp(edge + dash + zebra + stopl, 0.0, 1.0);
		if (yellow > 0.5) {
			paint = 1.0;
			paint_col = vec3(0.95, 0.72, 0.18);
		}
	}
	ALBEDO = mix(col, paint_col * (0.85 + 0.15 * grain), paint * 0.92);
	NORMAL_MAP = mix(texture(asphalt_normal, tuv).rgb, vec3(0.5, 0.5, 1.0), paint * 0.7);
	ROUGHNESS = mix(tex_rough, 0.55, paint);
	SPECULAR = 0.35;
}
