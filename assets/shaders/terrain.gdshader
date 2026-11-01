shader_type spatial;
// Terreno del estado: mezcla por altura, pendiente y bioma (COLOR del vértice:
// r desierto, g bosque, b arena de costa, a ciudad) de 15 texturas en un Texture2DArray.
// Tiling a escala de mundo con dos escalas rotadas + variación macro para que no se
// note la repetición; triplanar en los acantilados.
// Capas: 0 grass 1 grass_mix 2 hill_grass 3 forest 4 desert_red 5 desert_rocks
// 6 desert_cracked 7 sand 8 beach_aerial 9 cliff 10 coast_rocks 11 snow 12 dirt_road
// 13 seabed 14 coral_gravel.

render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float sea_level = -0.45;
uniform float snow_line = 250.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 bio;

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

// Muestra una capa con dos escalas (la segunda rotada) mezcladas por ruido. A mucha
// distancia se usa el color medio de la capa (último mip): sin patrón repetido.
uniform float far_avg_begin = 900.0;
vec3 layer(float idx, vec2 p, float tile, float mixn, float fa) {
	vec2 uv1 = p / tile;
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / (tile * 3.7) + 0.37;
	vec3 avg = textureLod(albedo_arr, vec3(uv1, idx), 12.0).rgb;
	if (fa > 0.99) {
		return avg;
	}
	vec3 a = texture(albedo_arr, vec3(uv1, idx)).rgb;
	vec3 b = texture(albedo_arr, vec3(uv2, idx)).rgb;
	return mix(mix(a, b, mixn), avg, fa);
}

vec3 tri_layer(float idx, vec3 p, vec3 n, float tile) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 x = texture(albedo_arr, vec3(p.zy / tile, idx)).rgb;
	vec3 y = texture(albedo_arr, vec3(p.xz / tile, idx)).rgb;
	vec3 z = texture(albedo_arr, vec3(p.xy / tile, idx)).rgb;
	return x * w.x + y * w.y + z * w.z;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	bio = COLOR;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 n = normalize(wnrm);
	float slope = 1.0 - n.y;
	float h = wpos.y;
	float macro = vnoise(p * 0.0045);
	float macro2 = vnoise(p * 0.0011 + 17.0);
	float mixn = smoothstep(0.25, 0.75, vnoise(p * 0.021 + 3.0));
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float fa = smoothstep(far_avg_begin, far_avg_begin * 2.2, dist);
	// A lo lejos solo la escala grande (menos muestras, sin moiré).
	float far_k = smoothstep(350.0, 900.0, dist);
	mixn = mix(mixn, 1.0, far_k);

	float w_des = bio.r;
	float w_for = bio.g;
	float w_sand = bio.b;
	float w_urb = bio.a;
	float w_under = smoothstep(sea_level + 0.15, sea_level - 0.9, h);
	float w_cliff = smoothstep(0.30, 0.48, slope + (macro - 0.5) * 0.08);
	float w_snow = smoothstep(snow_line + 50.0 * macro, snow_line + 40.0 + 50.0 * macro, h) * (1.0 - smoothstep(0.55, 0.75, slope));

	// Hierba: pradera, mezcla y hierba de colina por altura y ruido macro.
	vec3 col = vec3(0.0);
	vec3 nrm_t = vec3(0.5, 0.5, 1.0);
	float green_w = (1.0 - w_des) * (1.0 - w_sand);
	if (green_w > 0.01) {
		// Base: pradera (grass_mix) con manchas de hojarasca verde y, en las colinas, hierba con roca.
		// (La capa 0 "grass" es un atlas de briznas para la hierba 3D: no se usa como suelo.)
		vec3 g = layer(1.0, p, 10.0, mixn, fa) * vec3(0.92, 1.08, 0.78);
		g = mix(g, layer(3.0, p, 7.0, mixn, fa) * vec3(1.2, 1.15, 1.0), smoothstep(0.45, 0.8, macro) * 0.5);
		float hill = smoothstep(25.0, 90.0, h + (macro2 - 0.5) * 40.0);
		if (hill > 0.01) {
			g = mix(g, layer(2.0, p, 12.0, mixn, fa), hill * 0.6);
		}
		if (w_for > 0.05) {
			g = mix(g, layer(3.0, p, 8.0, mixn, fa) * vec3(0.85, 0.95, 0.85), smoothstep(0.1, 0.6, w_for * (0.7 + 0.6 * macro)));
		}
		// Variación de color a gran escala: zonas secas y zonas más verdes.
		g *= mix(vec3(1.08, 1.02, 0.80), vec3(0.80, 1.02, 0.80), macro2);
		col += g * green_w;
		nrm_t = texture(normal_arr, vec3(p / 10.0, 1.0)).rgb;
	}
	if (w_des > 0.01) {
		vec3 d0 = layer(4.0, p, 14.0, mixn, fa);
		vec3 d1 = layer(6.0, p, 11.0, mixn, fa);
		vec3 d = mix(d0, d1, smoothstep(0.6, 0.85, macro) * 0.6 * (1.0 - smoothstep(10.0, 30.0, h)));
		d = mix(d, layer(5.0, p, 9.0, mixn, fa), smoothstep(0.12, 0.3, slope) * 0.8);
		d *= mix(vec3(1.12, 0.82, 0.66), vec3(1.0, 0.86, 0.74), macro2);
		col += d * w_des * (1.0 - w_sand);
		nrm_t = mix(nrm_t, texture(normal_arr, vec3(p / 14.0, 4.0)).rgb, w_des);
	}
	if (w_sand > 0.01) {
		vec3 s = mix(layer(7.0, p, 9.0, mixn, fa), layer(8.0, p, 26.0, mixn, fa), smoothstep(0.4, 0.7, macro) * 0.6);
		// Arena mojada junto al agua.
		s = mix(s, s * vec3(0.62, 0.6, 0.55), smoothstep(sea_level + 0.6, sea_level, h));
		col += s * w_sand;
	}
	// Ciudades: tierra compactada y polvo.
	if (w_urb > 0.01) {
		vec3 u = layer(12.0, p, 12.0, mixn, fa);
		col = mix(col, u * vec3(0.95, 0.93, 0.9), w_urb * smoothstep(0.3, 0.7, vnoise(p * 0.03)) * 0.55);
	}
	// Acantilados y laderas fuertes (triplanar): roca de desierto, de costa o de montaña.
	if (w_cliff > 0.01) {
		vec3 rock = tri_layer(9.0, wpos, n, 22.0);
		if (w_des > 0.05) {
			rock = mix(rock, tri_layer(5.0, wpos, n, 16.0) * vec3(1.15, 0.9, 0.8), w_des);
		}
		float coast = smoothstep(12.0, 2.0, h) * (1.0 - w_des);
		if (coast > 0.01) {
			rock = mix(rock, tri_layer(10.0, wpos, n, 12.0), coast);
		}
		col = mix(col, rock, w_cliff);
		nrm_t = mix(nrm_t, vec3(0.5, 0.5, 1.0), w_cliff);
	}
	if (w_snow > 0.01) {
		col = mix(col, layer(11.0, p, 12.0, mixn, fa) * 1.05, w_snow);
	}
	if (w_under > 0.01) {
		vec3 sb = mix(layer(14.0, p, 8.0, mixn, fa), layer(13.0, p, 10.0, mixn, fa), smoothstep(-2.5, -8.0, h));
		col = mix(col, sb, w_under);
	}
	// Variación de brillo de baja frecuencia (rompe la repetición a lo lejos).
	col *= 0.86 + 0.28 * vnoise(p * 0.0025 + 9.0);
	ALBEDO = col;
	NORMAL_MAP = mix(nrm_t, vec3(0.5, 0.5, 1.0), far_k * 0.8);
	ROUGHNESS = mix(0.92, 0.55, w_snow * 0.5 + w_under * 0.4);
	SPECULAR = 0.2;
}
