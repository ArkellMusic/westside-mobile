shader_type spatial;
// Fachadas procedurales: ventanas, plantas bajas comerciales y azoteas.
// Color del edificio en INSTANCE_CUSTOM.rgb; tipo en INSTANCE_CUSTOM.a:
//   < 0.34 casa, < 0.67 comercial, resto torre.
// Funciona igual en el renderizador Mobile (iPhone) y en Compatibility.

render_mode diffuse_burley, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 0.25;
uniform vec3 glass_color : source_color = vec3(0.13, 0.17, 0.22);
uniform vec3 sky_tint : source_color = vec3(0.95, 0.62, 0.42);
uniform vec3 window_light : source_color = vec3(1.0, 0.78, 0.48);

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
}

void fragment() {
	vec3 base = bdata.rgb;
	float kind = bdata.a;
	float seed = dot(base, vec3(91.7, 37.3, 13.1));

	if (wnorm.y > 0.5) {
		// Azotea: grava oscura con algo de ruido.
		float n = hash21(floor(wpos.xz * 1.5));
		ALBEDO = mix(vec3(0.20, 0.20, 0.21), base * 0.45, 0.35) * (0.9 + 0.1 * n);
		ROUGHNESS = 0.95;
	} else if (wnorm.y < -0.5) {
		ALBEDO = base * 0.3;
		ROUGHNESS = 1.0;
	} else {
		float u = abs(wnorm.x) > 0.5 ? wpos.z : wpos.x;
		float v = wpos.y;
		bool house = kind < 0.34;
		bool tower = kind > 0.66;
		float floor_h = house ? 3.0 : (tower ? 3.6 : 3.4);
		float col_w = house ? 3.4 : (tower ? 1.8 : 2.7);

		vec2 cell = vec2(floor(u / col_w), floor(v / floor_h));
		vec2 f = vec2(fract(u / col_w), fract(v / floor_h));

		float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.30, f.y) * step(f.y, 0.86);
		if (tower) {
			win = step(0.06, f.x) * step(f.x, 0.94) * step(0.12, f.y) * step(f.y, 0.92);
		}
		if (house) {
			win *= step(0.42, hash21(cell + seed));
		}
		// Planta baja comercial: escaparates anchos.
		bool storefront = !house && v < floor_h;
		if (storefront) {
			float fu = fract(u / 6.0);
			win = step(0.05, fu) * step(fu, 0.95) * step(0.08, v / floor_h) * step(v / floor_h, 0.78);
		}
		// Zócalo y franja inferior sin ventanas en casas.
		if (house && v < 0.6) {
			win = 0.0;
		}

		float floor_line = 1.0 - 0.12 * step(0.95, f.y) * (house ? 0.0 : 1.0);
		float ground_ao = mix(0.62, 1.0, clamp(v / 2.5, 0.0, 1.0));
		vec3 wall = base * floor_line * ground_ao;

		// Cristal: refleja algo del cielo del atardecer según el ángulo.
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		vec3 glass = mix(glass_color, sky_tint * 0.55, 0.25 + 0.55 * fres);
		if (storefront) {
			glass = mix(glass, vec3(0.32, 0.27, 0.20), 0.35);
		}

		ALBEDO = mix(wall, glass, win);
		ROUGHNESS = mix(0.88, 0.12, win);
		SPECULAR = mix(0.3, 0.7, win);

		float lit_chance = storefront ? 0.75 : night * 0.75;
		float lit = step(1.0 - lit_chance, hash21(cell * 1.37 + seed + 3.1));
		EMISSION = win * lit * window_light * (storefront ? 0.9 : 1.6) * (0.35 + night);
	}
}
