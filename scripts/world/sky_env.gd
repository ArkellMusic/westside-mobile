class_name SkyEnv
extends Node3D
## Cielo, sol, niebla e iluminación ambiental con ambientes predefinidos que
## se pueden fundir entre sí (noche en el desierto, amanecer, mañana, atardecer).
##
## En Forward+ añade lo que da el aspecto de juego "real": tonemap AgX con
## exposición automática suave, bloom para farolas y neón, SSAO + SSIL, reflejos
## SSR (asfalto mojado, cristales, coches), SDFGI, niebla de altura y volumétrica
## (rayos de sol y calima), sombras PCSS en 4 cortes, gradación de color por hora
## del día (cálida al atardecer, azul y naranja de noche) y una ReflectionProbe que
## sigue a la cámara y se actualiza de vez en cuando. Lo que se activa depende
## del nivel de Settings (alta, media, baja).

## Valores por defecto de los campos de gradación y atmósfera de cada ambiente.
## shadow_tint / high_tint: tinte de sombras y de luces (curvas por canal tras el tonemap).
## vol: densidad de la niebla volumétrica; height_fog: niebla baja; wet: asfalto mojado.
const GRADE_DEFAULTS := {
	"sat": 1.06, "contrast": 1.05, "shadow_tint": Color(1, 1, 1), "high_tint": Color(1, 1, 1),
	"vol": 0.004, "vol_albedo": Color(0.85, 0.85, 0.85), "vol_emit": 0.0, "height_fog": 0.0,
	"wet": 0.0, "sun_size": 0.5, "scatter": 0.15, "aerial": 0.5, "clouds": 0.45,
}

## Ajustes cinematográficos por ambiente (se mezclan con PRESETS).
const GRADES := {
	"night_desert": {
		"sat": 1.0, "contrast": 1.08, "shadow_tint": Color(0.86, 0.95, 1.16), "high_tint": Color(1.1, 0.98, 0.86),
		"vol": 0.006, "vol_albedo": Color(0.55, 0.62, 0.8), "vol_emit": 0.0, "height_fog": 0.02, "wet": 0.0, "sun_size": 0.3, "scatter": 0.0, "aerial": 0.3,
	},
	"night_city": {
		"sat": 1.08, "contrast": 1.1, "shadow_tint": Color(0.84, 0.95, 1.18), "high_tint": Color(1.14, 0.98, 0.82),
		"vol": 0.004, "vol_albedo": Color(0.6, 0.66, 0.85), "vol_emit": 0.012, "height_fog": 0.008, "wet": 0.75, "sun_size": 0.3, "scatter": 0.0, "aerial": 0.3,
	},
	"dusk": {
		"sat": 1.1, "contrast": 1.08, "shadow_tint": Color(0.88, 0.9, 1.14), "high_tint": Color(1.14, 0.96, 0.9),
		"vol": 0.003, "vol_albedo": Color(0.85, 0.66, 0.74), "vol_emit": 0.004, "height_fog": 0.006, "wet": 0.35, "sun_size": 0.6, "scatter": 0.3, "aerial": 0.6,
	},
	"dawn": {
		"sat": 1.08, "contrast": 1.05, "shadow_tint": Color(0.9, 0.95, 1.12), "high_tint": Color(1.12, 0.98, 0.86),
		"vol": 0.005, "vol_albedo": Color(1.0, 0.82, 0.7), "vol_emit": 0.0, "height_fog": 0.012, "wet": 0.3, "sun_size": 0.6, "scatter": 0.45, "aerial": 0.7,
	},
	"morning": {
		"sat": 1.24, "contrast": 1.12, "shadow_tint": Color(0.97, 1.0, 1.05), "high_tint": Color(1.03, 1.0, 0.96),
		"vol": 0.0006, "vol_albedo": Color(0.92, 0.94, 0.98), "vol_emit": 0.0, "height_fog": 0.0, "wet": 0.0, "sun_size": 0.5, "scatter": 0.05, "aerial": 0.35,
	},
	"golden": {
		"sat": 1.14, "contrast": 1.08, "shadow_tint": Color(0.9, 0.94, 1.12), "high_tint": Color(1.12, 0.98, 0.84),
		"vol": 0.002, "vol_albedo": Color(1.0, 0.8, 0.62), "vol_emit": 0.0, "height_fog": 0.004, "wet": 0.1, "sun_size": 0.6, "scatter": 0.4, "aerial": 0.65,
	},
}

const PRESETS := {
	"night_desert": {
		"sun_yaw": -40.0, "sun_pitch": -35.0, "light": Color(0.62, 0.68, 0.85), "energy": 0.32,
		"top": Color(0.02, 0.03, 0.08), "horizon": Color(0.10, 0.12, 0.22), "ground": Color(0.03, 0.03, 0.05),
		"fog": Color(0.06, 0.07, 0.13), "fog_density": 0.0005, "ambient": 0.3, "night": 1.0, "exposure": 1.35, "sky_energy": 1.0,
	},
	"night_city": {
		"sun_yaw": -40.0, "sun_pitch": -35.0, "light": Color(0.62, 0.7, 0.9), "energy": 0.45,
		"top": Color(0.025, 0.045, 0.12), "horizon": Color(0.09, 0.13, 0.26), "ground": Color(0.03, 0.035, 0.07),
		"fog": Color(0.07, 0.1, 0.19), "fog_density": 0.0004, "ambient": 0.55, "night": 1.0, "exposure": 1.45, "sky_energy": 1.0,
	},
	"dusk": {
		"sun_yaw": -78.0, "sun_pitch": 3.0, "light": Color(0.9, 0.45, 0.4), "energy": 0.2,
		"top": Color(0.09, 0.11, 0.3), "horizon": Color(0.8, 0.4, 0.46), "ground": Color(0.1, 0.08, 0.11),
		"fog": Color(0.5, 0.33, 0.44), "fog_density": 0.0004, "ambient": 0.38, "night": 0.7, "exposure": 1.0, "sky_energy": 1.0,
	},
	"dawn": {
		"sun_yaw": 95.0, "sun_pitch": -6.0, "light": Color(1.0, 0.55, 0.35), "energy": 0.9,
		"top": Color(0.16, 0.22, 0.42), "horizon": Color(0.98, 0.58, 0.38), "ground": Color(0.16, 0.12, 0.1),
		"fog": Color(0.85, 0.58, 0.46), "fog_density": 0.0005, "ambient": 0.45, "night": 0.55, "exposure": 1.05, "sky_energy": 1.0,
	},
	"morning": {
		"sun_yaw": 110.0, "sun_pitch": -32.0, "light": Color(1.0, 0.95, 0.86), "energy": 1.6,
		"top": Color(0.2, 0.43, 0.82), "horizon": Color(0.66, 0.81, 0.95), "ground": Color(0.3, 0.3, 0.3),
		"fog": Color(0.7, 0.8, 0.93), "fog_density": 0.00012, "ambient": 1.15, "night": 0.05, "exposure": 1.0, "sky_energy": 1.0,
	},
	"golden": {
		"sun_yaw": -80.0, "sun_pitch": -11.0, "light": Color(1.0, 0.66, 0.4), "energy": 1.25,
		"top": Color(0.22, 0.32, 0.58), "horizon": Color(1.0, 0.66, 0.44), "ground": Color(0.2, 0.15, 0.12),
		"fog": Color(0.95, 0.68, 0.5), "fog_density": 0.0003, "ambient": 0.4, "night": 0.35, "exposure": 1.0, "sky_energy": 1.0, "hdri": "res://assets/sky/sunset.hdr",
	},
}

var sun: DirectionalLight3D
var env: Environment
## Atributos de la cámara de juego (exposición automática suave).
var cam_attrs: CameraAttributesPractical
var probe: ReflectionProbe
var grass: GrassField
var _grade_tex: GradientTexture1D
var _grade_key: PackedFloat32Array = PackedFloat32Array()
var _probe_pos := Vector3(INF, INF, INF)
var _probe_night := -1.0
var _probe_timer := 0.0
var _last_wet := -1.0
var _grade_time := 0
var sky_mat: ProceduralSkyMaterial
var pano_mat: PanoramaSkyMaterial
var cloud_mat: ShaderMaterial
var sky: Sky
var _hdri_cache: Dictionary = {}
var city: CityBuilder:
	set(v):
		city = v
		_spawn_grass()
var current: Dictionary = {}
var _from: Dictionary = {}
var _to: Dictionary = {}
var _t: float = 1.0
var _duration: float = 1.0

## Ciclo día/noche automático (lo apagan los ambientes de las cinemáticas).
var auto_cycle: bool = false
var _keys: Array = []
var _cycle_seg: int = -1
var _seg_hdri: String = ""
var _lamp_lights: Array = []
var _lamp_timer: float = 0.0


func _ready() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.12
	sky_mat.energy_multiplier = 1.0
	sky = Sky.new()
	sky.sky_material = sky_mat
	_make_cloud_sky()
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if _is_rd() else Sky.PROCESS_MODE_AUTOMATIC
	pano_mat = PanoramaSkyMaterial.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Luz ambiente: mezcla del cielo con un color neutro del ambiente, para que las sombras
	# no queden negras ni teñidas del azul del cielo despejado.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	env.ambient_light_sky_contribution = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true
	env.fog_sky_affect = 0.1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	_grade_tex = GradientTexture1D.new()
	_grade_tex.width = 128
	_grade_tex.gradient = Gradient.new()
	cam_attrs = CameraAttributesPractical.new()
	cam_attrs.auto_exposure_speed = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	we.camera_attributes = cam_attrs
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.05
	sun.shadow_blur = 1.5
	add_child(sun)
	probe = ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(160, 70, 160)
	probe.max_distance = 140.0
	probe.box_projection = false
	probe.enable_shadows = false
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.blend_distance = 20.0
	probe.mesh_lod_threshold = 8.0
	probe.intensity = 1.0
	probe.top_level = true
	add_child(probe)
	_build_keys()
	for i in 8:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.52)
		l.omni_range = 14.0
		l.omni_attenuation = 1.4
		l.light_energy = 1.4
		l.light_size = 0.25
		l.light_volumetric_fog_energy = 2.5
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lamp_lights.append(l)
	EventBus.settings_changed.connect(_apply_quality)
	_apply_quality()
	apply_preset("morning", 0.0)


static func _is_rd() -> bool:
	var m := RenderingServer.get_current_rendering_method()
	return m == "forward_plus" or m == "mobile"


## Activa o desactiva los efectos según el nivel gráfico.
func _apply_quality() -> void:
	if env == null:
		return
	var fx := Settings.use_screen_effects()
	if sun:
		sun.shadow_enabled = Settings.shadows_enabled()
		sun.directional_shadow_max_distance = Settings.shadow_distance()
		if Settings.shadow_splits() >= 4:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			# Cortes pensados para la cámara de tercera persona: 0-8 m, 8-26 m, 26-64 m y el resto.
			sun.directional_shadow_split_1 = 0.05
			sun.directional_shadow_split_2 = 0.16
			sun.directional_shadow_split_3 = 0.4
			sun.directional_shadow_blend_splits = true
			sun.directional_shadow_fade_start = 0.85
		else:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_blend_splits = false
		sun.directional_shadow_pancake_size = 30.0
		sun.shadow_bias = 0.03 if fx else 0.05
		sun.shadow_normal_bias = 1.4 if fx else 1.0
		sun.shadow_blur = 1.0 if fx else 1.5
	if fx:
		# Tonemap filmico AgX y exposición automática suave.
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_agx_white = 12.0
		env.tonemap_agx_contrast = 1.3
		cam_attrs.auto_exposure_enabled = true
		cam_attrs.auto_exposure_scale = 0.4
		cam_attrs.auto_exposure_min_sensitivity = 140.0
		cam_attrs.auto_exposure_max_sensitivity = 420.0
		# Bloom para farolas, faros, neón y ventanas iluminadas.
		env.glow_enabled = true
		env.glow_normalized = false
		env.glow_intensity = 0.4
		env.glow_strength = 1.0
		env.glow_bloom = 0.02
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		env.glow_hdr_threshold = 1.1
		env.glow_hdr_scale = 2.0
		env.glow_hdr_luminance_cap = 16.0
		for i in 7:
			env.set_glow_level(i, [0.0, 0.35, 0.75, 1.0, 0.7, 0.35, 0.0][i])
		# Oclusión ambiental + iluminación indirecta en pantalla.
		env.ssao_enabled = true
		env.ssao_radius = 1.6
		env.ssao_intensity = 2.2
		env.ssao_power = 1.6
		env.ssao_detail = 0.6
		env.ssao_horizon = 0.06
		env.ssao_sharpness = 0.98
		env.ssao_light_affect = 0.15
		env.ssao_ao_channel_affect = 0.0
		env.ssil_enabled = true
		env.ssil_radius = 6.0
		env.ssil_intensity = 0.9
		env.ssil_sharpness = 0.98
		env.ssil_normal_rejection = 1.0
		# Reflejos en pantalla: asfalto mojado, charcos, cristales y coches.
		env.ssr_enabled = true
		env.ssr_max_steps = 48 if Settings.quality == "high" else 32
		env.ssr_fade_in = 0.12
		env.ssr_fade_out = 2.5
		env.ssr_depth_tolerance = 0.35
		# Iluminación global por campo de distancia (solo alta).
		env.sdfgi_enabled = Settings.use_sdfgi()
		env.sdfgi_cascades = 3
		env.sdfgi_min_cell_size = 0.4
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
		env.sdfgi_use_occlusion = true
		env.sdfgi_bounce_feedback = 0.35
		env.sdfgi_read_sky_light = true
		env.sdfgi_energy = 0.9
		env.sdfgi_normal_bias = 1.1
		env.sdfgi_probe_bias = 1.1
		# Niebla: exponencial con perspectiva aérea (calima) y niebla baja.
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_height = 4.0
		env.volumetric_fog_enabled = Settings.use_volumetric_fog()
		env.volumetric_fog_anisotropy = 0.62
		env.volumetric_fog_length = 110.0
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_gi_inject = 0.6
		env.volumetric_fog_ambient_inject = 0.25
		env.volumetric_fog_sky_affect = 0.1
		env.volumetric_fog_temporal_reprojection_enabled = true
		env.volumetric_fog_temporal_reprojection_amount = 0.9
		env.adjustment_color_correction = _grade_tex
	else:
		# Igual que antes del salto gráfico (renderizador "mobile").
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_white = 6.0
		cam_attrs.auto_exposure_enabled = false
		env.glow_enabled = true
		env.glow_intensity = 0.6
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.ssr_enabled = false
		env.sdfgi_enabled = false
		env.volumetric_fog_enabled = false
		env.fog_height_density = 0.0
		env.fog_aerial_perspective = 0.0
		env.fog_sun_scatter = 0.0
		env.adjustment_color_correction = null
	if probe:
		probe.visible = Settings.quality == "high" and _is_rd()
		_probe_pos = Vector3(INF, INF, INF)
	if grass:
		grass.set_cells(Settings.grass_cells())
	if not current.is_empty():
		_apply_values(current)


## Cielo con nubes volumétricas, sol, luna y estrellas (assets/shaders/sky_clouds.gdshader).
## El ruido 3D de las nubes se genera una vez al arrancar.
func _make_cloud_sky() -> void:
	var shader := load("res://assets/shaders/sky_clouds.gdshader") as Shader
	if shader == null:
		return
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.045
	noise.seed = 1971
	var tex := NoiseTexture3D.new()
	tex.width = 64
	tex.height = 64
	tex.depth = 64
	tex.seamless = true
	tex.seamless_blend_skirt = 0.25
	tex.noise = noise
	cloud_mat = ShaderMaterial.new()
	cloud_mat.shader = shader
	cloud_mat.set_shader_parameter("noise_tex", tex)
	sky.sky_material = cloud_mat


## Pasa al cielo los colores, la noche, la cobertura de nubes y la calidad.
func _update_cloud_sky(p: Dictionary) -> void:
	if cloud_mat == null:
		return
	sky.sky_material = cloud_mat
	cloud_mat.set_shader_parameter("top_color", p["top"])
	cloud_mat.set_shader_parameter("horizon_color", p["horizon"])
	cloud_mat.set_shader_parameter("ground_color", p["ground"])
	cloud_mat.set_shader_parameter("night", float(p.get("night", 0.0)))
	cloud_mat.set_shader_parameter("cloud_cover", float(p.get("clouds", 0.45)))
	cloud_mat.set_shader_parameter("cloud_steps", float(Settings.cloud_steps()))
	cloud_mat.set_shader_parameter("cloud_time", Time.get_ticks_msec() * 0.001)


func _spawn_grass() -> void:
	if grass != null or city == null or not is_inside_tree():
		return
	grass = GrassField.new()
	grass.name = "GrassField"
	add_child(grass)
	grass.setup(city)
	grass.set_cells(Settings.grass_cells())


func apply_preset(preset: String, duration: float) -> void:
	auto_cycle = false
	pano_mat.energy_multiplier = 1.0
	_from = current.duplicate() if not current.is_empty() else preset_values(preset)
	_to = preset_values(preset)
	var hdri := String(_to.get("hdri", ""))
	_to.erase("hdri")
	_from.erase("hdri")
	if hdri != "" and ResourceLoader.exists(hdri):
		if not _hdri_cache.has(hdri):
			_hdri_cache[hdri] = load(hdri)
		pano_mat.panorama = _hdri_cache[hdri]
		sky.sky_material = cloud_mat if cloud_mat else pano_mat
	else:
		sky.sky_material = cloud_mat if cloud_mat else sky_mat
	_duration = maxf(duration, 0.001)
	_t = 0.0 if duration > 0.0 else 1.0
	if duration <= 0.0:
		_apply_values(_to)


## Ambiente completo: valores base + gradación cinematográfica.
static func preset_values(preset: String) -> Dictionary:
	var v: Dictionary = (PRESETS[preset] as Dictionary).duplicate()
	for k in GRADE_DEFAULTS:
		v[k] = GRADE_DEFAULTS[k]
	var g: Dictionary = GRADES.get(preset, {})
	for k in g:
		v[k] = g[k]
	return v


func _process(delta: float) -> void:
	_update_probe(delta)
	if cloud_mat:
		cloud_mat.set_shader_parameter("cloud_time", Time.get_ticks_msec() * 0.001)
	_lamp_timer -= delta
	if _lamp_timer <= 0.0:
		_lamp_timer = 0.5
		_update_lamp_lights()
	if _t < 1.0:
		_t = minf(_t + delta / _duration, 1.0)
		var t := _t * _t * (3.0 - 2.0 * _t)
		var mix := {}
		for k in _to:
			var a: Variant = _from.get(k, _to[k])
			var b: Variant = _to[k]
			if typeof(b) == TYPE_COLOR:
				mix[k] = (a as Color).lerp(b, t)
			else:
				mix[k] = lerpf(float(a), float(b), t)
		_apply_values(mix)


func _apply_values(p: Dictionary) -> void:
	current = p
	sun.rotation_degrees = Vector3(float(p["sun_pitch"]), float(p["sun_yaw"]), 0)
	sun.light_color = p["light"]
	sun.light_energy = p["energy"]
	sky_mat.sky_top_color = p["top"]
	sky_mat.sky_horizon_color = p["horizon"]
	sky_mat.ground_horizon_color = (p["horizon"] as Color).darkened(0.3)
	sky_mat.ground_bottom_color = p["ground"]
	env.fog_light_color = p["fog"]
	env.fog_density = p["fog_density"]
	env.ambient_light_energy = p["ambient"]
	env.ambient_light_color = (p["fog"] as Color).lerp(Color(1, 1, 1), 0.45)
	env.tonemap_exposure = p["exposure"]
	_update_cloud_sky(p)
	_apply_grade(p)
	if city:
		city.set_night(float(p["night"]))


## Gradación de color, niebla y materiales que dependen de la hora.
func _apply_grade(p: Dictionary) -> void:
	if not Settings.use_screen_effects():
		env.adjustment_contrast = 1.1
		env.adjustment_saturation = 1.2
		return
	var night := float(p.get("night", 0.0))
	env.adjustment_contrast = float(p.get("contrast", 1.05))
	env.adjustment_saturation = float(p.get("sat", 1.06))
	env.fog_aerial_perspective = float(p.get("aerial", 0.5))
	env.fog_sun_scatter = float(p.get("scatter", 0.15))
	env.fog_height_density = float(p.get("height_fog", 0.0))
	env.volumetric_fog_density = float(p.get("vol", 0.004))
	var fog_col: Color = p["fog"]
	env.volumetric_fog_albedo = p.get("vol_albedo", Color(0.85, 0.85, 0.85))
	env.volumetric_fog_emission = fog_col.lerp(Color(1.0, 0.62, 0.35), 0.35)
	env.volumetric_fog_emission_energy = float(p.get("vol_emit", 0.0))
	sun.light_angular_distance = float(p.get("sun_size", 0.5))
	sun.light_volumetric_fog_energy = lerpf(1.0, 0.35, night)
	sun.light_specular = 1.0
	# Curvas por canal: sombras y luces teñidas (teal & orange de noche, cálido al atardecer).
	var sh: Color = p.get("shadow_tint", Color.WHITE)
	var hi: Color = p.get("high_tint", Color.WHITE)
	var key := PackedFloat32Array([sh.r, sh.g, sh.b, hi.r, hi.g, hi.b])
	var changed := _grade_key.size() != key.size()
	if not changed:
		for i in key.size():
			if absf(key[i] - _grade_key[i]) > 0.02:
				changed = true
				break
	var now := Time.get_ticks_msec()
	if changed and (now - _grade_time > 2000 or _grade_key.is_empty()):
		_grade_time = now
		_grade_key = key
		var g := Gradient.new()
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
		g.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 0.8, 1.0])
		var mid := sh.lerp(hi, 0.5)
		g.colors = PackedColorArray([
			Color(0, 0, 0),
			Color(0.2 * sh.r, 0.2 * sh.g, 0.2 * sh.b),
			Color(minf(0.5 * mid.r, 1.0), minf(0.5 * mid.g, 1.0), minf(0.5 * mid.b, 1.0)),
			Color(minf(0.8 * hi.r, 1.0), minf(0.8 * hi.g, 1.0), minf(0.8 * hi.b, 1.0)),
			Color(1, 1, 1),
		])
		_grade_tex.gradient = g
	# Asfalto mojado de noche (charcos con reflejos SSR).
	var wet := float(p.get("wet", 0.0))
	if city and city.mat_road and absf(wet - _last_wet) > 0.01:
		_last_wet = wet
		city.mat_road.set_shader_parameter("wetness", wet)


## La sonda de reflejos sigue a la cámara y solo se vuelve a renderizar al
## alejarse 18 m o al cambiar la luz (una cara del cubo por fotograma).
func _update_probe(delta: float) -> void:
	if probe == null or not probe.visible:
		return
	_probe_timer -= delta
	if _probe_timer > 0.0:
		return
	_probe_timer = 0.5
	var cam := _find_camera()
	if cam == null:
		return
	var p := cam.global_position
	var night := night_amount()
	var moved := Vector2(p.x - _probe_pos.x, p.z - _probe_pos.z).length() > 18.0 or absf(p.y - _probe_pos.y) > 12.0
	if moved or absf(night - _probe_night) > 0.08:
		_probe_pos = p
		_probe_night = night
		probe.global_position = Vector3(snappedf(p.x, 2.0), maxf(p.y, 1.0) + 3.0, snappedf(p.z, 2.0))
		# Forzar un nuevo render aunque la posición coincida.
		probe.intensity = 1.0 if probe.intensity < 1.0 else 0.999


# ---------------------------------------------------------------- ciclo día/noche

## Claves del ciclo: [hora, ambiente, cambios]. El yaw del sol avanza de forma continua
## (este por la mañana, sur al mediodía, oeste al atardecer).
func _build_keys() -> void:
	var defs := [
		[0.0, "night_city", {"sun_yaw": 320.0}],
		[5.5, "night_city", {"sun_yaw": 40.0}],
		[6.5, "dawn", {}],
		[8.0, "morning", {"sun_yaw": 105.0, "sun_pitch": -26.0}],
		[12.5, "morning", {"sun_yaw": 190.0, "sun_pitch": -55.0}],
		[17.0, "morning", {"sun_yaw": 250.0, "sun_pitch": -30.0}],
		[18.75, "golden", {"sun_yaw": 280.0}],
		[19.75, "dusk", {"sun_yaw": 282.0}],
		[21.0, "night_city", {"sun_yaw": 320.0}],
		[24.0, "night_city", {"sun_yaw": 320.0}],
	]
	_keys.clear()
	for d in defs:
		var v: Dictionary = preset_values(String(d[1]))
		for k in (d[2] as Dictionary):
			v[k] = d[2][k]
		var hdri := String(v.get("hdri", ""))
		v.erase("hdri")
		_keys.append({"h": float(d[0]), "v": v, "hdri": hdri})


func resume_cycle() -> void:
	auto_cycle = true
	_t = 1.0
	_cycle_seg = -1


## 0 = pleno día, 1 = noche cerrada (según el ambiente actual).
func night_amount() -> float:
	return float(current.get("night", 0.0))


func set_time_of_day(minutes: float) -> void:
	if not auto_cycle or _keys.is_empty():
		return
	var h := fposmod(minutes / 60.0, 24.0)
	var i := 0
	while i < _keys.size() - 2 and h >= float(_keys[i + 1]["h"]):
		i += 1
	var k0: Dictionary = _keys[i]
	var k1: Dictionary = _keys[i + 1]
	var t := clampf((h - float(k0["h"])) / (float(k1["h"]) - float(k0["h"])), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	if i != _cycle_seg:
		# El panorama solo cambia al cruzar una clave, nunca cada fotograma.
		_cycle_seg = i
		_seg_hdri = String(k0["hdri"])
		if _seg_hdri != "" and ResourceLoader.exists(_seg_hdri):
			if not _hdri_cache.has(_seg_hdri):
				_hdri_cache[_seg_hdri] = load(_seg_hdri)
			pano_mat.panorama = _hdri_cache[_seg_hdri]
			sky.sky_material = cloud_mat if cloud_mat else pano_mat
		else:
			_seg_hdri = ""
			sky.sky_material = cloud_mat if cloud_mat else sky_mat
	if _seg_hdri != "":
		# Si el siguiente tramo no tiene panorama, se apaga poco a poco.
		pano_mat.energy_multiplier = lerpf(1.0, 0.3, t) if String(k1["hdri"]) == "" else 1.0
	var va: Dictionary = k0["v"]
	var vb: Dictionary = k1["v"]
	var mix := {}
	for k in vb:
		var a: Variant = va.get(k, vb[k])
		var b: Variant = vb[k]
		if typeof(b) == TYPE_COLOR:
			mix[k] = (a as Color).lerp(b, t)
		elif k == "sun_yaw":
			mix[k] = rad_to_deg(lerp_angle(deg_to_rad(float(a)), deg_to_rad(float(b)), t))
		else:
			mix[k] = lerpf(float(a), float(b), t)
	_apply_values(mix)


## Recoloca el grupo de luces de farola junto a la cámara (cada 0.5 s, solo de noche).
func _update_lamp_lights() -> void:
	var night := night_amount()
	var cam: Camera3D = _find_camera()
	if night <= 0.4 or city == null or cam == null or city.lamp_positions.is_empty():
		for l in _lamp_lights:
			(l as OmniLight3D).visible = false
		return
	var cp: Vector3 = cam.global_position
	var lamps: PackedVector3Array = city.lamp_positions
	var dists := PackedFloat32Array()
	dists.resize(lamps.size())
	for i in lamps.size():
		var d: Vector3 = lamps[i] - cp
		dists[i] = d.x * d.x + d.z * d.z
	var energy := 1.4 * smoothstep(0.4, 0.65, night)
	for l in _lamp_lights:
		var best := -1
		var bd := INF
		for i in dists.size():
			if dists[i] < bd:
				bd = dists[i]
				best = i
		var light := l as OmniLight3D
		if best < 0:
			light.visible = false
			continue
		dists[best] = INF
		light.global_position = lamps[best] + Vector3(0, -0.4, 0)
		light.light_energy = energy
		light.visible = true


var _cam: Camera3D

func _find_camera() -> Camera3D:
	if is_inside_tree():
		var vc := get_viewport().get_camera_3d()
		if vc:
			return vc
	if _cam != null and is_instance_valid(_cam) and _cam.is_inside_tree():
		return _cam
	_cam = null
	if is_inside_tree():
		var stack: Array = [get_tree().root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is Camera3D:
				_cam = n
				return _cam
			stack.append_array(n.get_children())
	return _cam
