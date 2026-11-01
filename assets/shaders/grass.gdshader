shader_type spatial;
// Matas de hierba 3D instanciadas (MultiMesh) alrededor de la cámara.
// La máscara de césped (R = 1 en jardines) decide dónde crecen; se encogen y
// desaparecen con la distancia, y se mecen con el viento.
// UV.y = 0 en la base, 1 en la punta.

render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D lawn_mask : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(0.0, 0.0, 1.0, 1.0); // x0, z0, ancho, fondo (m)
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float ground_tile = 7.0;
uniform vec3 ground_tint : source_color = vec3(1.0);
uniform float fade_start = 12.0;
uniform float fade_end = 20.0;
uniform float wind_strength = 0.12;
uniform vec2 wind_dir = vec2(0.8, 0.6);

varying float v_tip;
varying vec3 v_ground;
varying float v_var;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 muv = (origin.xz - mask_rect.xy) / mask_rect.zw;
	float m = texture(lawn_mask, muv).r;
	if (muv.x < 0.0 || muv.y < 0.0 || muv.x > 1.0 || muv.y > 1.0) {
		m = 0.0;
	}
	float d = distance(origin.xz, CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	float h = hash21(origin.xz);
	float s = smoothstep(0.35, 0.65, m) * fade * (0.65 + 0.7 * h);
	v_tip = UV.y;
	v_var = h;
	if (s < 0.02) {
		VERTEX = vec3(0.0);
	} else {
		VERTEX.y *= s;
		VERTEX.xz *= mix(0.6, 1.0, s);
		// Viento: ondas que recorren el césped, más fuertes en la punta.
		float t = TIME * 1.6 + dot(origin.xz, wind_dir) * 0.35;
		float sway = (sin(t) * 0.6 + sin(t * 2.3 + h * 6.28) * 0.4) * wind_strength;
		vec3 wl = (inverse(mat3(MODEL_MATRIX)) * vec3(wind_dir.x, 0.0, wind_dir.y));
		VERTEX += wl * sway * UV.y * UV.y * s;
	}
	// Normal casi vertical: las matas se iluminan como el suelo (sin caras negras).
	NORMAL = normalize(mix(NORMAL, (inverse(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0)), 0.65));
	// Color medio del césped en esa zona (mip alto: sin manchas de hojas sueltas).
	v_ground = textureLod(ground_albedo, origin.xz / ground_tile, 6.0).rgb * ground_tint;
}

void fragment() {
	// Mismo color que el suelo en la base (se funde con él) y algo más claro en la punta.
	vec3 base = v_ground;
	vec3 tip = v_ground * vec3(1.12, 1.18, 0.92);
	tip = mix(tip, tip * vec3(1.15, 1.08, 0.8), smoothstep(0.75, 1.0, v_var) * 0.5);
	ALBEDO = mix(base, tip, smoothstep(0.0, 1.0, v_tip));
	AO = mix(0.85, 1.0, v_tip);
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.18, 0.22, 0.08) * v_tip;
}
