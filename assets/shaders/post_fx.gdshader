shader_type canvas_item;
// Postproceso barato de pantalla completa: desenfoque de movimiento radial al ir
// rápido en coche, viñeta y grano.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float motion = 0.0;        // 0..1 (velocidad del coche)
uniform vec2 motion_center = vec2(0.5, 0.48);
uniform float vignette = 0.28;
uniform float grain = 0.025;
uniform float aberration = 0.0;  // desactivada: en móvil se veía como franjas de color

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - motion_center;
	float r = length(d * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0));
	vec3 col;
	if (motion > 0.01) {
		// 6 muestras hacia el centro, solo en los bordes (el centro queda nítido).
		float k = motion * 0.035 * smoothstep(0.12, 0.6, r);
		vec3 acc = vec3(0.0);
		for (int i = 0; i < 6; i++) {
			float t = float(i) / 5.0;
			acc += textureLod(screen_tex, uv - d * k * t, 0.0).rgb;
		}
		col = acc / 6.0;
	} else {
		col = textureLod(screen_tex, uv, 0.0).rgb;
	}
	// Aberración cromática sutil en las esquinas.
	float ab = aberration * smoothstep(0.45, 0.9, r);
	if (ab > 0.00001) {
		col.r = mix(col.r, textureLod(screen_tex, uv + d * ab, 0.0).r, 0.5);
		col.b = mix(col.b, textureLod(screen_tex, uv - d * ab, 0.0).b, 0.5);
	}
	// Viñeta suave.
	float v = smoothstep(0.95, 0.25, r);
	col *= mix(1.0 - vignette, 1.0, v);
	// Grano de película (más visible en sombras, nada en blancos).
	float n = hash12(FRAGCOORD.xy + fract(TIME * 7.13) * 917.0) - 0.5;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col += n * grain * (1.0 - smoothstep(0.2, 0.9, luma));
	COLOR = vec4(col, 1.0);
}
