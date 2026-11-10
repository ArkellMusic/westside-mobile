shader_type sky;
// Cielo de WESTSIDE LEGACY: degradado por hora del día, sol y luna visibles (el astro es la
// luz direccional de la escena: sol de día, luna de noche), estrellas y nubes volumétricas
// (ray marching de una capa de nubes con ruido 3D, iluminadas hacia el astro).
// Las nubes se calculan a un cuarto de resolución y se componen encima del cielo.
render_mode use_quarter_res_pass;

uniform vec3 top_color : source_color = vec3(0.2, 0.43, 0.82);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.81, 0.95);
uniform vec3 ground_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float night = 0.0;            // 0 = día, 1 = noche cerrada
uniform float cloud_cover = 0.45;     // 0 = despejado, 1 = cubierto
uniform float cloud_time = 0.0;       // segundos (deriva del viento)
uniform float cloud_steps = 12.0;     // 0 = sin nubes volumétricas
uniform float energy = 1.0;
uniform sampler3D noise_tex : repeat_enable, filter_linear;

const float CLOUD_BOTTOM = 1100.0;
const float CLOUD_TOP = 2300.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float cloud_density(vec3 p) {
	vec3 wind = vec3(cloud_time * 6.0, 0.0, cloud_time * 2.5);
	vec3 q = (p + wind) * 0.00022;
	float n = texture(noise_tex, q).r * 0.56 + texture(noise_tex, q * 2.9 + vec3(0.37)).r * 0.28 + texture(noise_tex, q * 7.3).r * 0.16;
	float h = clamp((p.y - CLOUD_BOTTOM) / (CLOUD_TOP - CLOUD_BOTTOM), 0.0, 1.0);
	// Base plana y cima redondeada.
	float shape = smoothstep(0.0, 0.18, h) * smoothstep(1.0, 0.45, h);
	// Umbral según la cobertura: con 0.45 quedan cúmulos sueltos y mucho cielo a la vista.
	return clamp((n - mix(0.68, 0.44, cloud_cover)) * 6.0, 0.0, 1.0) * shape;
}

vec4 clouds(vec3 dir, vec3 light_dir, vec3 light_col, float day) {
	if (dir.y < 0.03 || cloud_steps < 1.0) {
		return vec4(0.0);
	}
	float t0 = CLOUD_BOTTOM / dir.y;
	float t1 = CLOUD_TOP / dir.y;
	float steps = cloud_steps;
	float dt = (t1 - t0) / steps;
	float jitter = hash13(dir * 913.0);
	float transmit = 1.0;
	vec3 col = vec3(0.0);
	vec3 ambient = mix(horizon_color, top_color, 0.5) * mix(0.75, 1.0, day) + vec3(0.02);
	vec3 lit = light_col * mix(0.35, 1.25, day);
	for (float i = 0.0; i < steps; i += 1.0) {
		vec3 p = dir * (t0 + dt * (i + jitter));
		float d = cloud_density(p);
		if (d > 0.01) {
			// Una muestra hacia el astro: cuánta nube tapa la luz.
			float shadow = exp(-cloud_density(p + light_dir * 260.0) * 2.6);
			float h = clamp((p.y - CLOUD_BOTTOM) / (CLOUD_TOP - CLOUD_BOTTOM), 0.0, 1.0);
			vec3 c = ambient * mix(0.55, 1.0, h) + lit * shadow;
			float a = 1.0 - exp(-d * dt * 0.0045);
			col += c * a * transmit;
			transmit *= 1.0 - a;
			if (transmit < 0.03) {
				break;
			}
		}
	}
	float alpha = 1.0 - transmit;
	// Se disuelven hacia el horizonte.
	float fade = smoothstep(0.03, 0.16, dir.y);
	return vec4(col / max(alpha, 0.001), alpha * fade);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 light_dir = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : vec3(0.0, 1.0, 0.0);
	vec3 light_col = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0);
	float day = 1.0 - clamp(night, 0.0, 1.0);

	if (AT_QUARTER_RES_PASS) {
		vec4 c = clouds(dir, light_dir, light_col, day);
		COLOR = c.rgb * energy;
		ALPHA = c.a;
	} else {
		// Degradado base.
		float up = max(dir.y, 0.0);
		vec3 col = mix(horizon_color, top_color, pow(up, 0.42));
		if (dir.y < 0.0) {
			col = mix(horizon_color, ground_color, clamp(-dir.y * 6.0, 0.0, 1.0));
		}
		float cosang = dot(dir, light_dir);
		float above = smoothstep(-0.06, 0.02, light_dir.y);
		// Sol: disco, corona y resplandor amplio (se apaga al llegar la noche).
		float sun_vis = above * smoothstep(0.75, 0.45, night);
		float sun_disk = smoothstep(0.99955, 0.99972, cosang);
		float corona = pow(max(cosang, 0.0), 900.0) * 1.6 + pow(max(cosang, 0.0), 40.0) * 0.22;
		col += light_col * (sun_disk * 18.0 + corona) * sun_vis;
		// Luna: disco con sombreado de esfera, mares y halo suave.
		float moon_vis = above * smoothstep(0.5, 0.8, night);
		float moon_r = 0.04;
		float ang = acos(clamp(cosang, -1.0, 1.0));
		if (ang < moon_r * 1.02 && moon_vis > 0.0) {
			vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), light_dir));
			vec3 upv = cross(light_dir, right);
			vec2 uv = vec2(dot(dir, right), dot(dir, upv)) / moon_r;
			float r2 = dot(uv, uv);
			float z = sqrt(max(1.0 - r2, 0.0));
			vec3 nrm = vec3(uv, z);
			float lambert = clamp(dot(nrm, normalize(vec3(-0.55, 0.3, 0.75))), 0.0, 1.0);
			float seas = texture(noise_tex, vec3(uv * 0.21 + 0.4, 0.31)).r;
			float surface = mix(0.55, 1.0, smoothstep(0.38, 0.62, seas));
			float edge = smoothstep(1.02, 0.94, sqrt(r2));
			vec3 moon = vec3(0.92, 0.94, 1.0) * surface * (0.12 + lambert * 1.5);
			col = mix(col, moon, edge * moon_vis);
		}
		col += vec3(0.5, 0.6, 0.85) * pow(max(cosang, 0.0), 220.0) * 0.35 * moon_vis;
		// Estrellas (solo de noche y sobre el horizonte).
		if (night > 0.35 && dir.y > 0.0) {
			vec3 sp = dir * 380.0;
			vec3 g = floor(sp);
			float s = hash13(g);
			float tw = 0.75 + 0.25 * sin(TIME * (1.0 + s * 3.0) + s * 40.0);
			// Punto redondo y pequeño en el centro de la celda.
			float star = step(0.9986, s) * smoothstep(0.42, 0.05, length(fract(sp) - 0.5)) * tw;
			col += vec3(0.85, 0.9, 1.0) * star * smoothstep(0.35, 0.85, night) * smoothstep(0.0, 0.15, dir.y) * 1.6;
		}
		if (!AT_CUBEMAP_PASS) {
			vec4 c = QUARTER_RES_COLOR;
			col = mix(col, c.rgb / max(energy, 0.001), c.a);
		} else {
			// Reflejos y luz ambiente: nubes aproximadas por su cobertura (sin ray marching).
			col = mix(col, mix(horizon_color, vec3(1.0), 0.5 * day), cloud_cover * 0.18 * smoothstep(0.0, 0.3, dir.y));
		}
		COLOR = col * energy;
	}
}
