class_name SkyEnv
extends Node3D
## Cielo, sol, niebla e iluminación ambiental con ambientes predefinidos que
## se pueden fundir entre sí (noche en el desierto, amanecer, mañana, atardecer).

const PRESETS := {
	"night_desert": {
		"sun_yaw": -40.0, "sun_pitch": -35.0, "light": Color(0.62, 0.68, 0.85), "energy": 0.32,
		"top": Color(0.02, 0.03, 0.08), "horizon": Color(0.10, 0.12, 0.22), "ground": Color(0.03, 0.03, 0.05),
		"fog": Color(0.06, 0.07, 0.13), "fog_density": 0.0009, "ambient": 0.3, "night": 1.0, "exposure": 1.35, "sky_energy": 1.0,
	},
	"dawn": {
		"sun_yaw": 95.0, "sun_pitch": -6.0, "light": Color(1.0, 0.55, 0.35), "energy": 0.9,
		"top": Color(0.16, 0.22, 0.42), "horizon": Color(0.98, 0.58, 0.38), "ground": Color(0.16, 0.12, 0.1),
		"fog": Color(0.85, 0.58, 0.46), "fog_density": 0.0011, "ambient": 0.45, "night": 0.55, "exposure": 1.05, "sky_energy": 1.0,
	},
	"morning": {
		"sun_yaw": 110.0, "sun_pitch": -24.0, "light": Color(1.0, 0.86, 0.68), "energy": 1.35,
		"top": Color(0.28, 0.48, 0.78), "horizon": Color(0.88, 0.80, 0.70), "ground": Color(0.25, 0.22, 0.18),
		"fog": Color(0.86, 0.80, 0.72), "fog_density": 0.0006, "ambient": 0.6, "night": 0.05, "exposure": 1.0, "sky_energy": 1.0, "hdri": "res://assets/sky/day.hdr",
	},
	"golden": {
		"sun_yaw": -80.0, "sun_pitch": -11.0, "light": Color(1.0, 0.66, 0.4), "energy": 1.25,
		"top": Color(0.22, 0.32, 0.58), "horizon": Color(1.0, 0.66, 0.44), "ground": Color(0.2, 0.15, 0.12),
		"fog": Color(0.95, 0.68, 0.5), "fog_density": 0.0008, "ambient": 0.5, "night": 0.35, "exposure": 1.0, "sky_energy": 1.0, "hdri": "res://assets/sky/sunset.hdr",
	},
}

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var pano_mat: PanoramaSkyMaterial
var sky: Sky
var _hdri_cache: Dictionary = {}
var city: CityBuilder
var current: Dictionary = {}
var _from: Dictionary = {}
var _to: Dictionary = {}
var _t: float = 1.0
var _duration: float = 1.0


func _ready() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.12
	sky = Sky.new()
	sky.sky_material = sky_mat
	pano_mat = PanoramaSkyMaterial.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.05
	sun.shadow_blur = 1.5
	add_child(sun)
	EventBus.settings_changed.connect(_apply_quality)
	_apply_quality()
	apply_preset("morning", 0.0)


func _apply_quality() -> void:
	if sun:
		sun.shadow_enabled = Settings.shadows_enabled()
		sun.directional_shadow_max_distance = Settings.shadow_distance()


func apply_preset(preset: String, duration: float) -> void:
	_from = current.duplicate() if not current.is_empty() else PRESETS[preset].duplicate()
	_to = PRESETS[preset].duplicate()
	var hdri := String(_to.get("hdri", ""))
	_to.erase("hdri")
	_from.erase("hdri")
	if hdri != "" and ResourceLoader.exists(hdri):
		if not _hdri_cache.has(hdri):
			_hdri_cache[hdri] = load(hdri)
		pano_mat.panorama = _hdri_cache[hdri]
		sky.sky_material = pano_mat
	else:
		sky.sky_material = sky_mat
	_duration = maxf(duration, 0.001)
	_t = 0.0 if duration > 0.0 else 1.0
	if duration <= 0.0:
		_apply_values(_to)


func _process(delta: float) -> void:
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
	env.tonemap_exposure = p["exposure"]
	if city:
		city.set_night(float(p["night"]))
