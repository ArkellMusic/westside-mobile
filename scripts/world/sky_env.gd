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
	"night_city": {
		"sun_yaw": -40.0, "sun_pitch": -35.0, "light": Color(0.62, 0.7, 0.9), "energy": 0.3,
		"top": Color(0.025, 0.045, 0.12), "horizon": Color(0.09, 0.13, 0.26), "ground": Color(0.03, 0.035, 0.07),
		"fog": Color(0.07, 0.1, 0.19), "fog_density": 0.0008, "ambient": 0.35, "night": 1.0, "exposure": 1.3, "sky_energy": 1.0,
	},
	"dusk": {
		"sun_yaw": -78.0, "sun_pitch": 3.0, "light": Color(0.9, 0.45, 0.4), "energy": 0.2,
		"top": Color(0.09, 0.11, 0.3), "horizon": Color(0.8, 0.4, 0.46), "ground": Color(0.1, 0.08, 0.11),
		"fog": Color(0.5, 0.33, 0.44), "fog_density": 0.0009, "ambient": 0.38, "night": 0.7, "exposure": 1.0, "sky_energy": 1.0,
	},
	"dawn": {
		"sun_yaw": 95.0, "sun_pitch": -6.0, "light": Color(1.0, 0.55, 0.35), "energy": 0.9,
		"top": Color(0.16, 0.22, 0.42), "horizon": Color(0.98, 0.58, 0.38), "ground": Color(0.16, 0.12, 0.1),
		"fog": Color(0.85, 0.58, 0.46), "fog_density": 0.0011, "ambient": 0.45, "night": 0.55, "exposure": 1.05, "sky_energy": 1.0,
	},
	"morning": {
		"sun_yaw": 110.0, "sun_pitch": -32.0, "light": Color(1.0, 0.9, 0.76), "energy": 1.15,
		"top": Color(0.28, 0.48, 0.78), "horizon": Color(0.88, 0.80, 0.70), "ground": Color(0.25, 0.22, 0.18),
		"fog": Color(0.86, 0.80, 0.72), "fog_density": 0.0006, "ambient": 0.35, "night": 0.05, "exposure": 0.78, "sky_energy": 1.0, "hdri": "res://assets/sky/day.hdr",
	},
	"golden": {
		"sun_yaw": -80.0, "sun_pitch": -11.0, "light": Color(1.0, 0.66, 0.4), "energy": 1.25,
		"top": Color(0.22, 0.32, 0.58), "horizon": Color(1.0, 0.66, 0.44), "ground": Color(0.2, 0.15, 0.12),
		"fog": Color(0.95, 0.68, 0.5), "fog_density": 0.0008, "ambient": 0.35, "night": 0.35, "exposure": 0.8, "sky_energy": 1.0, "hdri": "res://assets/sky/sunset.hdr",
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
	sky = Sky.new()
	sky.sky_material = sky_mat
	pano_mat = PanoramaSkyMaterial.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
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
	_build_keys()
	for i in 8:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.52)
		l.omni_range = 14.0
		l.light_energy = 1.4
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lamp_lights.append(l)
	EventBus.settings_changed.connect(_apply_quality)
	_apply_quality()
	apply_preset("morning", 0.0)


func _apply_quality() -> void:
	if sun:
		sun.shadow_enabled = Settings.shadows_enabled()
		sun.directional_shadow_max_distance = Settings.shadow_distance()


func apply_preset(preset: String, duration: float) -> void:
	auto_cycle = false
	pano_mat.energy_multiplier = 1.0
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
	env.tonemap_exposure = p["exposure"]
	if city:
		city.set_night(float(p["night"]))


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
		var v: Dictionary = (PRESETS[d[1]] as Dictionary).duplicate()
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
			sky.sky_material = pano_mat
		else:
			_seg_hdri = ""
			sky.sky_material = sky_mat
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
