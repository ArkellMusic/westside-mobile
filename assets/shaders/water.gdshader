shader_type spatial;
// Océano: olas suaves en vértices, turquesa en la orilla y azul profundo mar adentro.

render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec3 shallow : source_color = vec3(0.12, 0.62, 0.66);
uniform vec3 deep : source_color = vec3(0.02, 0.16, 0.28);
uniform float shore_x = -330.0;
uniform vec3 foam_color : source_color = vec3(0.95, 0.96, 0.95);

varying vec3 wpos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float h = sin(w.x * 0.08 + t * 1.1) * 0.12 + sin(w.z * 0.11 - t * 0.9) * 0.10 + sin((w.x + w.z) * 0.23 + t * 1.7) * 0.05;
	VERTEX.y += h;
	wpos = w;
	wpos.y += h;
}

void fragment() {
	float d = clamp((shore_x - wpos.x) / 140.0, 0.0, 1.0);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 1.0, d));
	float t = TIME;
	float ripple = sin(wpos.x * 0.9 + t * 2.0) * sin(wpos.z * 0.7 - t * 1.6);
	col *= 0.93 + 0.07 * ripple;
	// Espuma junto a la orilla.
	float foam = smoothstep(14.0, 0.0, abs(wpos.x - shore_x)) * (0.5 + 0.5 * sin(wpos.z * 0.35 + t * 1.3));
	col = mix(col, foam_color, foam * 0.35);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = col;
	ROUGHNESS = 0.06;
	SPECULAR = 0.8;
	METALLIC = 0.0;
	EMISSION = vec3(0.9, 0.55, 0.35) * fres * 0.25;
}
