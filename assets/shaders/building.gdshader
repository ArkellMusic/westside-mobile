shader_type spatial;
// Fachadas con texturas PBR reales (estuco, ladrillo, hormigón) + ventanas,
// escaparates y azoteas generadas por coordenadas de mundo.
// INSTANCE_CUSTOM.rgb = tono del edificio; .a = tipo (<0.34 casa, <0.67 comercio, resto torre).
// Funciona en el renderizador Mobile (iPhone) y en Compatibility.

render_mode diffuse_burley, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 0.25;
uniform vec3 glass_color : source_color = vec3(0.10, 0.13, 0.17);
uniform vec3 sky_tint : source_color = vec3(0.85, 0.75, 0.62);
uniform vec3 window_light : source_color = vec3(1.0, 0.78, 0.48);

uniform sampler2D house_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D house_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shop_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shop_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tower_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tower_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wall_tile = 3.0;

varying vec3 wpos;
varying vec3 wnorm;
varying vec4 bdata;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	bdata = INSTANCE_CUSTOM;
	// Base tangente alineada con las caras de la caja (para los mapas normales).
	if (abs(NORMAL.y) > 0.5) {
		TANGENT = vec3(1.0, 0.0, 0.0);
		BINORMAL = vec3(0.0, 0.0, 1.0);
	} else if (abs(NORMAL.x) > 0.5) {
		TANGENT = vec3(0.0, 0.0, -sign(NORMAL.x));
		BINORMAL = vec3(0.0, -1.0, 0.0);
	} else {
		TANGENT = vec3(sign(NORMAL.z), 0.0, 0.0);
		BINORMAL = vec3(0.0, -1.0, 0.0);
	}
}

void fragment() {
	vec3 tint = bdata.rgb;
	float kind = bdata.a;
	float seed = dot(tint, vec3(91.7, 37.3, 13.1));
	bool house = kind < 0.34;
	bool tower = kind > 0.66;

	if (wnorm.y > 0.5) {
		vec2 ruv = wpos.xz / 4.0;
		ALBEDO = texture(roof_albedo, ruv).rgb * 0.85;
		NORMAL_MAP = texture(roof_normal, ruv).rgb;
		ROUGHNESS = 0.95;
	} else if (wnorm.y < -0.5) {
		ALBEDO = tint * 0.3;
		ROUGHNESS = 1.0;
	} else {
		float u = abs(wnorm.x) > 0.5 ? wpos.z : wpos.x;
		float v = wpos.y;
		vec2 tuv = vec2(u, -v) / wall_tile;
		vec3 wall_tex;
		vec3 wall_nrm;
		if (house) {
			wall_tex = texture(house_albedo, tuv).rgb;
			wall_nrm = texture(house_normal, tuv).rgb;
		} else if (tower) {
			wall_tex = texture(tower_albedo, tuv * 0.7).rgb;
			wall_nrm = texture(tower_normal, tuv * 0.7).rgb;
		} else {
			wall_tex = texture(shop_albedo, tuv).rgb;
			wall_nrm = texture(shop_normal, tuv).rgb;
		}
		float floor_h = house ? 3.0 : (tower ? 3.6 : 3.4);
		float col_w = house ? 3.4 : (tower ? 1.8 : 2.7);
		vec2 cell = vec2(floor(u / col_w), floor(v / floor_h));
		vec2 f = vec2(fract(u / col_w), fract(v / floor_h));

		float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.32, f.y) * step(f.y, 0.86);
		if (tower) {
			win = step(0.06, f.x) * step(f.x, 0.94) * step(0.12, f.y) * step(f.y, 0.92);
		}
		if (house) {
			win *= step(0.42, hash21(cell + seed));
		}
		bool storefront = !house && v < floor_h;
		if (storefront) {
			float fu = fract(u / 6.0);
			win = step(0.05, fu) * step(fu, 0.95) * step(0.08, v / floor_h) * step(v / floor_h, 0.78);
		}
		if (house && v < 0.6) {
			win = 0.0;
		}
		// Marco de ventana (alféizar y dintel en relieve oscuro).
		float frame = 0.0;
		if (!tower && !storefront) {
			frame = (step(0.14, f.x) * step(f.x, 0.86) * step(0.28, f.y) * step(f.y, 0.9)) * (1.0 - win);
		}
		float ground_ao = mix(0.55, 1.0, clamp(v / 2.5, 0.0, 1.0));
		float grime = mix(0.85, 1.0, hash21(floor(vec2(u, v) * 0.5) + seed));
		vec3 wall = wall_tex * mix(vec3(1.0), tint * 1.25, 0.65) * ground_ao * grime;
		wall = mix(wall, wall * 0.55, frame);

		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		vec3 glass = mix(glass_color, sky_tint * 0.6, 0.22 + 0.6 * fres);
		// Reflejo de cielo variable por ventana y cortinas interiores.
		glass *= 0.8 + 0.4 * hash21(cell * 3.7 + seed);
		if (storefront) {
			glass = mix(glass, vec3(0.34, 0.28, 0.2), 0.35);
		}
		ALBEDO = mix(wall, glass, win);
		NORMAL_MAP = mix(wall_nrm, vec3(0.5, 0.5, 1.0), win);
		ROUGHNESS = mix(0.9, 0.06, win);
		SPECULAR = mix(0.35, 0.9, win);
		float lit_chance = storefront ? 0.8 : night * 0.75;
		float lit = step(1.0 - lit_chance, hash21(cell * 1.37 + seed + 3.1));
		EMISSION = win * lit * window_light * (storefront ? 1.1 : 1.8) * (0.3 + night);
	}
}
