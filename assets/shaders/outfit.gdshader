shader_type spatial;
// Ropa de Mack: recolorea la tela oscura del modelo (sudadera y pantalón negros) sin tocar
// piel, zapatillas, estampados ni cabeza. La tela se detecta por ser oscura y sin color,
// y la prenda por la altura del vértice (pantalón abajo, sudadera arriba).
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 rough_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform float roughness_scale = 1.0;
uniform float use_normal = 1.0;
uniform vec3 top_color : source_color = vec3(0.6, 0.6, 0.62);
uniform vec3 pants_color : source_color = vec3(0.16, 0.22, 0.36);
uniform float top_amount = 1.0;
uniform float pants_amount = 1.0;
uniform vec3 head_color : source_color = vec3(0.38, 0.24, 0.13);
uniform float head_amount = 0.0;
uniform float waist_y = 0.97;
uniform float neck_y = 1.5;
uniform float ankle_y = 0.09;

varying float height;

void vertex() {
	height = VERTEX.y;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 c = tex.rgb;
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float cloth = smoothstep(0.2, 0.09, mx) * smoothstep(0.07, 0.03, mx - mn);
	float is_top = smoothstep(waist_y - 0.03, waist_y + 0.03, height) * smoothstep(neck_y + 0.02, neck_y - 0.04, height);
	float is_pants = smoothstep(ankle_y - 0.02, ankle_y + 0.02, height) * smoothstep(waist_y + 0.03, waist_y - 0.03, height);
	// El detalle de pliegues se conserva usando el brillo original como sombreado.
	float shade = 0.45 + mx * 5.5;
	vec3 dyed = c;
	dyed = mix(dyed, top_color * shade, cloth * is_top * top_amount);
	dyed = mix(dyed, pants_color * shade, cloth * is_pants * pants_amount);
	// Barba, cejas y gorra (todo lo oscuro por encima del cuello).
	float is_head = smoothstep(neck_y + 0.02, neck_y + 0.07, height);
	dyed = mix(dyed, head_color * shade, cloth * is_head * head_amount);
	ALBEDO = dyed;
	ROUGHNESS = dot(texture(rough_tex, UV), rough_channel) * roughness_scale;
	METALLIC = 0.0;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
