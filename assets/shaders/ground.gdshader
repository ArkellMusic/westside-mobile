shader_type spatial;
// Suelo procedural por coordenadas de mundo: césped, hormigón, acera, arena o tierra.

render_mode diffuse_burley, specular_schlick_ggx;

uniform int surface = 0; // 0 césped, 1 hormigón, 2 acera, 3 arena, 4 tierra seca
uniform vec3 tint : source_color = vec3(1.0);

varying vec3 wpos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = vnoise(p * 0.15);
	float n2 = vnoise(p * 1.7);
	vec3 col;
	float rough = 0.9;
	if (surface == 0) {
		col = mix(vec3(0.20, 0.31, 0.12), vec3(0.33, 0.40, 0.17), n1);
		col = mix(col, vec3(0.42, 0.40, 0.24), smoothstep(0.65, 0.95, n1) * 0.6);
		col *= 0.88 + 0.2 * n2;
	} else if (surface == 1) {
		col = vec3(0.47, 0.46, 0.44) * (0.85 + 0.2 * n1) * (0.95 + 0.08 * n2);
		vec2 g = fract(p / 5.0);
		col *= 1.0 - 0.18 * (step(g.x, 0.02) + step(g.y, 0.02));
		rough = 0.85;
	} else if (surface == 2) {
		col = vec3(0.62, 0.60, 0.57) * (0.9 + 0.12 * n2);
		vec2 g = fract(p / 1.6);
		col *= 1.0 - 0.22 * clamp(step(g.x, 0.03) + step(g.y, 0.03), 0.0, 1.0);
		rough = 0.8;
	} else if (surface == 3) {
		col = mix(vec3(0.86, 0.76, 0.58), vec3(0.93, 0.85, 0.68), n1) * (0.94 + 0.08 * n2);
		// Arena mojada cerca de la orilla.
		float wet = smoothstep(-0.05, -0.6, wpos.y);
		col = mix(col, vec3(0.55, 0.47, 0.35), wet);
		rough = mix(0.95, 0.4, wet);
	} else {
		col = mix(vec3(0.45, 0.38, 0.26), vec3(0.35, 0.36, 0.20), n1) * (0.9 + 0.15 * n2);
	}
	ALBEDO = col * tint;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
