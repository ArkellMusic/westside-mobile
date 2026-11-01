shader_type spatial;
// Océano, bahías, lago y canales del estado: un plano al nivel del mar. La profundidad
// sale de un mapa del fondo (StateLayout, R = profundidad / 25 m): turquesa transparente
// en los bajíos (se ve el fondo de arena y coral), azul profundo mar adentro y espuma en la orilla.

render_mode blend_mix, depth_draw_opaque, diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform vec4 map_rect = vec4(-1408.0, -3328.0, 8192.0, 4864.0);
uniform vec3 shallow : source_color = vec3(0.12, 0.60, 0.60);
uniform vec3 mid : source_color = vec3(0.05, 0.42, 0.52);
uniform vec3 deep : source_color = vec3(0.02, 0.15, 0.27);
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 0.96);

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
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz - map_rect.xy) / map_rect.zw;
	float depth = 25.0;
	if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
		depth = texture(depth_map, uv).r * 25.0;
	}
	float t = TIME;
	vec2 p = wpos.xz;
	// Olas por normal: tres trenes de ondas + ruido.
	float e = 0.6;
	vec2 g = vec2(0.0);
	g += vec2(0.08, 0.0) * cos(p.x * 0.08 + t * 1.1) * 0.12;
	g += vec2(0.0, 0.11) * cos(p.y * 0.11 - t * 0.9) * 0.10;
	g += vec2(0.23, 0.23) * cos((p.x + p.y) * 0.23 + t * 1.7) * 0.05;
	g += (vec2(vnoise(p * 0.35 + t * 0.4), vnoise(p * 0.35 - t * 0.37 + 4.0)) - 0.5) * 0.18;
	vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;

	float d01 = clamp(depth / 25.0, 0.0, 1.0);
	vec3 col = mix(shallow, mid, smoothstep(0.0, 0.22, d01));
	col = mix(col, deep, smoothstep(0.2, 0.9, d01));
	// Espuma en la orilla (bajíos de menos de ~0,7 m).
	float foam = smoothstep(0.45, 0.02, depth) * (0.55 + 0.45 * sin(p.x * 0.3 + p.y * 0.21 + t * 1.4)) * step(0.01, depth + 0.02);
	foam *= smoothstep(0.35, 0.65, vnoise(p * 0.25 + t * 0.2));
	col = mix(col, foam_color, foam * 0.75);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = col;
	ALPHA = clamp(mix(0.55, 0.97, smoothstep(0.3, 6.0, depth)) + foam * 0.5, 0.0, 1.0);
	ROUGHNESS = 0.05;
	SPECULAR = 0.75;
	EMISSION = vec3(0.9, 0.6, 0.4) * fres * 0.15;
}
