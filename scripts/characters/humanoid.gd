class_name Humanoid
extends Node3D
## Personaje articulado procedural, construido según las fichas de personaje
## (docs/personajes). Es el marcador de posición hasta que existan los modelos
## GLB con esqueleto. Mira hacia -Z. Animación de andar/correr/saltar por código.
##
## Claves de aspecto (todas opcionales):
##   skin, top_type (tee|tank|hoodie|open_shirt|crop), top, under, print
##   pants_type (long|shorts), pants, socks, shoes, sole
##   hair_type (short|fade|dreads|bun), hair, beard
##   head (none|cap|beanie), head_color, glasses, chain (none|silver|gold), watch
##   build, height, female

var look: Dictionary = {}
var _phase: float = 0.0
var _pose: Dictionary = {}
var _talking: bool = false
## 0 de pie .. 1 agachado (lo fija Player).
var crouch: float = 0.0
var _talk_t: float = 0.0
var _idle_t: float = randf() * 20.0
var _idle_seed: float = randf() * TAU
var _flinch: float = 0.0
var _flinch_side: float = 1.0
var _accel_lean: float = 0.0
var _turn_lean: float = 0.0
var _last_yaw: float = 0.0
var _blend_speed: float = 0.0

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm := [null, null]
var _elbow := [null, null]
var _leg := [null, null]
var _knee := [null, null]
var _seated: bool = false
var _built: bool = false
var _skel: Skeleton3D = null
var _static_model: bool = false   # modelo sin esqueleto humanoide (se queda en su pose)
var _bones: Dictionary = {}
var _phone: Node3D = null   # móvil de la pose "phone"
var _gun: Node3D = null     # pistola en la mano derecha (combate)
## Pose superpuesta a la de andar (combate: apuntar, puñetazo). Mismas claves que _new_pose().
var overlay: Dictionary = {}

static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}

const SILVER := Color(0.78, 0.79, 0.82)
const GOLD := Color(0.86, 0.68, 0.2)


static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var skins := [Color(0.36, 0.22, 0.14), Color(0.55, 0.38, 0.26), Color(0.80, 0.62, 0.50), Color(0.25, 0.16, 0.10), Color(0.68, 0.50, 0.36), Color(0.47, 0.31, 0.20)]
	var tops := [Color(0.85, 0.2, 0.2), Color(0.2, 0.35, 0.65), Color(0.95, 0.95, 0.93), Color(0.1, 0.1, 0.11), Color(0.85, 0.65, 0.2), Color(0.25, 0.45, 0.32), Color(0.5, 0.5, 0.52), Color(0.45, 0.3, 0.55)]
	var bottoms := [Color(0.12, 0.15, 0.28), Color(0.13, 0.13, 0.14), Color(0.62, 0.56, 0.44), Color(0.32, 0.33, 0.35), Color(0.2, 0.25, 0.4)]
	var female := rng.randf() < 0.4
	var top_types := ["tee", "tee", "hoodie", "tank", "open_shirt"] if not female else ["tee", "crop", "tank", "hoodie"]
	return {
		"skin": skins[rng.randi() % skins.size()],
		"top_type": top_types[rng.randi() % top_types.size()],
		"top": tops[rng.randi() % tops.size()],
		"under": Color(0.95, 0.95, 0.93),
		"pants_type": "shorts" if rng.randf() < 0.25 else "long",
		"pants": bottoms[rng.randi() % bottoms.size()],
		"shoes": [Color(0.94, 0.94, 0.94), Color(0.08, 0.08, 0.09), Color(0.5, 0.32, 0.2)][rng.randi() % 3],
		"hair_type": ["short", "fade", "bun", "dreads"][rng.randi() % 4] if female else ["short", "fade", "fade", "dreads"][rng.randi() % 4],
		"hair": [Color(0.05, 0.04, 0.03), Color(0.3, 0.2, 0.12), Color(0.55, 0.45, 0.3)][rng.randi() % 3],
		"head": "cap" if rng.randf() < 0.25 else "none",
		"head_color": tops[rng.randi() % tops.size()],
		"beard": not female and rng.randf() < 0.4,
		"build": rng.randf_range(0.92, 1.18),
		"height": rng.randf_range(0.92, 1.04) * (0.94 if female else 1.0),
		"female": female,
	}


static func _mat(c: Color, metal: bool = false) -> StandardMaterial3D:
	var key := c.to_html() + ("m" if metal else "")
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.3 if metal else 0.78
		m.metallic = 0.9 if metal else 0.0
		_mat_cache[key] = m
	return _mat_cache[key]


func setup(appearance: Dictionary) -> void:
	look = appearance
	for c in get_children():
		remove_child(c)
		c.free()
	_skel = null
	_static_model = false
	_built = true
	var model_path := String(look.get("model", ""))
	if model_path != "" and ResourceLoader.exists(model_path):
		var model: Node3D = (load(model_path) as PackedScene).instantiate()
		add_child(model)
		_skel = model.get_node_or_null("Skeleton3D")
		if _skel == null:
			_static_model = true   # p. ej. el médico y el guardia de la comisaría
			return
		for i in _skel.get_bone_count():
			_bones[_skel.get_bone_name(i)] = i
		_apply(_new_pose())
		return
	var b: float = look.get("build", 1.0)
	var h: float = look.get("height", 1.0)
	var female: bool = look.get("female", false)
	var skin: Color = look.get("skin", Color(0.4, 0.25, 0.16))
	var top_type: String = look.get("top_type", "tee")
	var top: Color = look.get("top", Color.WHITE)
	var under: Color = look.get("under", Color(0.95, 0.95, 0.93))
	var pants: Color = look.get("pants", Color(0.12, 0.14, 0.2))
	var shorts: bool = look.get("pants_type", "long") == "shorts"
	scale = Vector3(h, h, h)
	var sw := 0.86 if female else 1.0  # anchura de hombros
	var baggy := 1.25 if top_type == "hoodie" else 1.0

	_hips = _pivot(self, Vector3(0, 0.95, 0))
	var pelvis := _part(_hips, _box(Vector3(0.36, 0.22, 0.22)), Vector3.ZERO, pants)
	pelvis.scale = Vector3(b * (1.06 if female else 1.0), 1, 1)

	_torso = _pivot(_hips, Vector3(0, 0.08, 0))
	var chest_color := top
	if top_type == "open_shirt":
		chest_color = under
	var chest := _part(_torso, _cap(0.17, 0.62), Vector3(0, 0.28, 0), chest_color)
	chest.scale = Vector3(1.25 * b * sw * baggy, 1.0, 0.8 * b * baggy)
	if top_type == "crop":
		chest.scale.y = 0.62
		chest.position.y = 0.38
		var belly := _part(_torso, _cap(0.13, 0.3), Vector3(0, 0.08, 0), skin)
		belly.scale = Vector3(1.1, 1, 0.8)
	if top_type == "hoodie":
		# Capucha caída a la espalda, bolsillo y gráfico delantero.
		var hood := _part(_torso, _sph(0.16), Vector3(0, 0.56, 0.11), top.darkened(0.08))
		hood.scale = Vector3(1.3, 0.7, 0.9)
		_part(_torso, _box(Vector3(0.28, 0.12, 0.03)), Vector3(0, 0.08, -0.2), top.darkened(0.1))
		_part(_torso, _box(Vector3(0.4 * b, 0.05, 0.3)), Vector3(0, -0.04, 0), under)
	if look.has("print"):
		_part(_torso, _box(Vector3(0.26, 0.16, 0.02)), Vector3(0, 0.32, -0.2 * b * baggy - 0.005), look["print"])
	if top_type == "open_shirt":
		for sx in [-1.0, 1.0]:
			var panel := _part(_torso, _box(Vector3(0.14 * b, 0.6, 0.06)), Vector3(sx * 0.15 * b, 0.27, -0.13 * b), top)
			panel.rotation.y = sx * 0.15
		var back := _part(_torso, _box(Vector3(0.42 * b, 0.62, 0.06)), Vector3(0, 0.27, 0.13 * b), top)
		back.scale.x = 1.0
	if top_type == "tank" or top_type == "crop":
		for sx in [-1.0, 1.0]:
			_part(_torso, _box(Vector3(0.05, 0.1, 0.26 * b)), Vector3(sx * 0.13 * b, 0.56, 0), top)

	_head = _pivot(_torso, Vector3(0, 0.6, 0))
	_part(_head, _cyl(0.058, 0.12), Vector3(0, 0.02, 0), skin)
	var head_mi := _part(_head, _sph(0.115), Vector3(0, 0.15, 0), skin)
	head_mi.scale = Vector3(0.92 if female else 0.96, 1.12, 1.0)
	for sx in [-1.0, 1.0]:
		_part(_head, _sph(0.014), Vector3(sx * 0.04, 0.165, -0.105), Color(0.05, 0.04, 0.04))
		_part(_head, _box(Vector3(0.04, 0.01, 0.02)), Vector3(sx * 0.042, 0.19, -0.104), look.get("hair", Color.BLACK))
	if look.get("beard", false):
		_part(_head, _box(Vector3(0.05, 0.05, 0.03)), Vector3(0, 0.06, -0.1), look.get("hair", Color.BLACK))
		_part(_head, _box(Vector3(0.07, 0.012, 0.02)), Vector3(0, 0.11, -0.112), look.get("hair", Color.BLACK))
	_build_hair()
	_build_headwear()
	if look.get("glasses", false):
		_part(_head, _box(Vector3(0.19, 0.045, 0.02)), Vector3(0, 0.165, -0.118), Color(0.02, 0.02, 0.02))
	var chain: String = look.get("chain", "none")
	if chain != "none":
		var cc := GOLD if chain == "gold" else SILVER
		var c1 := _part(_torso, _box(Vector3(0.2, 0.02, 0.02)), Vector3(0, 0.46, -0.16 * b * baggy), cc, true)
		c1.rotation.x = 0.35
		_part(_torso, _box(Vector3(0.05, 0.06, 0.015)), Vector3(0, 0.38, -0.175 * b * baggy), cc, true)
	if female and look.get("hoops", false):
		for sx in [-1.0, 1.0]:
			_part(_head, _sph(0.022), Vector3(sx * 0.11, 0.1, 0), GOLD, true)

	var long_sleeve := top_type == "hoodie"
	var sleeveless := top_type == "tank" or top_type == "crop"
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		_arm[i] = _pivot(_torso, Vector3(sx * 0.23 * b * sw * (1.08 if top_type == "hoodie" else 1.0), 0.5, 0))
		var upper := _part(_arm[i], _cap(0.058, 0.34), Vector3(0, -0.15, 0), skin if sleeveless else top)
		upper.scale = Vector3(b * (1.3 if long_sleeve else 1.0), 1, b * (1.3 if long_sleeve else 1.0))
		_elbow[i] = _pivot(_arm[i], Vector3(0, -0.3, 0))
		var fore := _part(_elbow[i], _cap(0.048, 0.3), Vector3(0, -0.13, 0), top if long_sleeve else skin)
		fore.scale = Vector3(b * (1.25 if long_sleeve else 1.0), 1, b * (1.25 if long_sleeve else 1.0))
		_part(_elbow[i], _sph(0.05), Vector3(0, -0.3, 0), skin)
		if look.get("watch", false) and i == 1:
			_part(_elbow[i], _cyl(0.054, 0.04), Vector3(0, -0.24, 0), GOLD, true)

		_leg[i] = _pivot(_hips, Vector3(sx * 0.1 * b * (1.06 if female else 1.0), -0.06, 0))
		var thigh := _part(_leg[i], _cap(0.085, 0.5), Vector3(0, -0.21, 0), pants)
		thigh.scale = Vector3(b * 1.12, 1, b * 1.12)
		if not shorts:
			_part(_leg[i], _box(Vector3(0.05, 0.16, 0.12)), Vector3(sx * 0.1 * b, -0.3, 0), pants.darkened(0.12))
		_knee[i] = _pivot(_leg[i], Vector3(0, -0.43, 0))
		if shorts:
			_part(_knee[i], _cap(0.055, 0.44), Vector3(0, -0.2, 0), skin)
			_part(_knee[i], _cap(0.058, 0.22), Vector3(0, -0.32, 0), look.get("socks", Color(0.95, 0.95, 0.95)))
		else:
			var shin := _part(_knee[i], _cap(0.075, 0.47), Vector3(0, -0.2, 0), pants)
			shin.scale = Vector3(b * 1.12, 1, b * 1.12)
		var shoe: Color = look.get("shoes", Color(0.95, 0.95, 0.95))
		_part(_knee[i], _box(Vector3(0.12, 0.09, 0.28)), Vector3(0, -0.43, -0.05), shoe)
		_part(_knee[i], _box(Vector3(0.125, 0.03, 0.29)), Vector3(0, -0.47, -0.05), look.get("sole", Color(0.96, 0.96, 0.96)))


func _build_hair() -> void:
	var hair: Color = look.get("hair", Color(0.05, 0.04, 0.03))
	match String(look.get("hair_type", "short")):
		"fade":
			var f := _part(_head, _sph(0.117), Vector3(0, 0.19, 0.01), hair)
			f.scale = Vector3(0.97, 0.72, 1.0)
		"dreads":
			var top := _part(_head, _sph(0.125), Vector3(0, 0.19, 0.0), hair)
			top.scale = Vector3(1.02, 0.9, 1.05)
			for k in 14:
				var a := PI * 0.15 + (PI * 1.7) * float(k) / 13.0
				var d := Vector3(sin(a), 0, cos(a))
				var lock := _part(_head, _cap(0.018, 0.2), Vector3(d.x * 0.11, 0.13, d.z * 0.11 + 0.01), hair)
				lock.rotation = Vector3(d.z * 0.25, 0, -d.x * 0.25)
		"bun":
			var top := _part(_head, _sph(0.12), Vector3(0, 0.2, 0.01), hair)
			top.scale = Vector3(1.0, 0.8, 1.02)
			_part(_head, _sph(0.075), Vector3(0, 0.31, 0.04), hair)
			for sx in [-1.0, 1.0]:
				_part(_head, _cap(0.015, 0.13), Vector3(sx * 0.1, 0.12, -0.06), hair)
		_:
			var s := _part(_head, _sph(0.118), Vector3(0, 0.185, 0.012), hair)
			s.scale = Vector3(0.98, 0.82, 1.0)


func _build_headwear() -> void:
	var col: Color = look.get("head_color", Color(0.06, 0.06, 0.07))
	match String(look.get("head", "none")):
		"cap":
			var crown := _part(_head, _sph(0.127), Vector3(0, 0.205, 0.0), col)
			crown.scale = Vector3(1.0, 0.62, 1.05)
			_part(_head, _box(Vector3(0.2, 0.018, 0.13)), Vector3(0, 0.205, -0.16), col)
		"beanie":
			var bean := _part(_head, _sph(0.126), Vector3(0, 0.215, 0.005), col)
			bean.scale = Vector3(1.0, 0.95, 1.04)
			_part(_head, _cyl(0.124, 0.05), Vector3(0, 0.2, 0.005), col.lightened(0.05))


## Pose en radianes. Convenio común para el modelo procedural y el modelo con esqueleto:
##   leg > 0 adelanta el muslo · knee > 0 dobla la rodilla · arm > 0 adelanta el brazo
##   elbow > 0 dobla el codo · arm_out > 0 separa el brazo · torso_x < 0 inclina adelante
static func _new_pose() -> Dictionary:
	return {"leg": [0.0, 0.0], "knee": [0.05, 0.05], "arm": [0.0, 0.0], "elbow": [0.15, 0.15], "arm_out": [0.08, 0.08], "torso_x": 0.0, "torso_y": 0.0, "head_x": 0.0, "hip_y": 0.0}


## Animación por código con modelo de marcha (no son clips grabados):
## - cadencia y longitud de zancada calculadas a partir de la velocidad real, para que los pies
##   no patinen; rodilla que flexiona en el balanceo y amortigua en el apoyo; tobillo que
##   levanta la punta al pisar y empuja al despegar;
## - pelvis que sube y baja dos veces por ciclo, rota y bascula; hombros en contrarrotación;
##   cabeza estabilizada; brazos en oposición con el codo más cerrado al correr;
## - inclinación al acelerar, frenar y girar; reposo con respiración y cambio de peso;
## - gestos de manos al hablar (set_talking) y sacudida al recibir un golpe (flinch);
## - toda la pose se suaviza en el tiempo, así que apuntar, golpear o parar no dan saltos.
## speed en m/s, on_floor para la pose aérea.
func animate(delta: float, speed: float, on_floor: bool) -> void:
	if not _built or _seated:
		return
	if _phone != null and _phone.visible:
		_phone.visible = false
	var prev_speed := _blend_speed
	_blend_speed = lerpf(_blend_speed, speed, clampf(delta * 8.0, 0.0, 1.0))
	var s := _blend_speed
	var accel := (s - prev_speed) / maxf(delta, 0.001)
	_accel_lean = lerpf(_accel_lean, clampf(accel * 0.02, -0.12, 0.16), clampf(delta * 5.0, 0.0, 1.0))
	# Velocidad de giro (para inclinarse hacia dentro de la curva).
	var yaw_now := global_rotation.y
	var yaw_rate := wrapf(yaw_now - _last_yaw, -PI, PI) / maxf(delta, 0.001)
	_last_yaw = yaw_now
	_turn_lean = lerpf(_turn_lean, clampf(yaw_rate * 0.05 * clampf(s / 4.0, 0.0, 1.0), -0.22, 0.22), clampf(delta * 6.0, 0.0, 1.0))
	_idle_t += delta
	_talk_t += delta
	_flinch = maxf(0.0, _flinch - delta * 3.5)
	var run := clampf((s - 3.2) / 3.0, 0.0, 1.0)
	var move := clampf(s / 1.0, 0.0, 1.0)
	# Cadencia (ciclos por segundo) y amplitud de la zancada según la velocidad.
	var cadence := lerpf(0.82, 1.62, clampf(s / 6.8, 0.0, 1.0))
	_phase = fposmod(_phase + delta * cadence * TAU * (0.35 + 0.65 * move), TAU)
	var step_len := s / (2.0 * cadence)
	var amp := asin(clampf(step_len / 1.76, 0.0, 0.82)) * lerpf(1.0, 0.95, run)
	var p := _new_pose()
	p["foot"] = [0.0, 0.0]
	p["torso_z"] = 0.0
	p["hip_z"] = 0.0
	p["hip_yaw"] = 0.0
	p["head_y"] = 0.0
	if not on_floor:
		p["leg"] = [0.6, -0.35]
		p["knee"] = [1.0, 0.45]
		p["foot"] = [-0.3, -0.5]
		p["arm"] = [-0.5, 0.6]
		p["arm_out"] = [0.45, 0.45]
		p["elbow"] = [0.9, 0.7]
		p["torso_x"] = -0.12
	else:
		for i in 2:
			var ph := _phase if i == 0 else _phase + PI
			var sw := sin(ph)
			var cw := cos(ph)   # > 0: la pierna va hacia delante (fase de balanceo)
			p["leg"][i] = sw * amp + 0.2 * run
			# Rodilla: flexión grande a mitad del balanceo y pequeña al cargar el peso.
			var swing := maxf(0.0, cos(ph - 0.35))
			var load := maxf(0.0, -cos(ph - 2.6))
			p["knee"][i] = 0.06 + pow(swing, 1.3) * lerpf(0.95, 1.4, run) * move + load * lerpf(0.18, 0.4, run) * move
			# Tobillo: punta arriba al apoyar el talón (pierna delante), empuje al despegar (pierna atrás).
			p["foot"][i] = (0.28 * maxf(0.0, sw) - 0.42 * maxf(0.0, -sw) * maxf(0.0, cw + 0.4)) * move - 0.25 * pow(swing, 2.0) * run
			# Brazos en oposición a las piernas; al correr, codo a unos 90 grados.
			var asw := -sw
			p["arm"][i] = asw * amp * lerpf(0.75, 1.05, run) + 0.05 * run
			p["arm_out"][i] = 0.07 + 0.06 * run
			p["elbow"][i] = 0.16 + move * (0.22 + 0.25 * maxf(0.0, asw)) + run * (1.05 + 0.25 * asw)
		var sw0 := sin(_phase)
		# Pelvis: baja en el doble apoyo, sube a mitad de paso; rota con la pierna que avanza
		# y bascula hacia la pierna que está en el aire.
		p["hip_y"] = -absf(sw0) * lerpf(0.035, 0.075, run) * move
		p["hip_yaw"] = sw0 * lerpf(0.10, 0.16, run) * move
		p["hip_z"] = cos(_phase) * 0.045 * move
		# Hombros en contrarrotación y cabeza que mira al frente.
		p["torso_y"] = -sw0 * lerpf(0.16, 0.26, run) * move
		p["head_y"] = sw0 * lerpf(0.05, 0.08, run) * move
		p["torso_x"] = -0.035 * move - 0.2 * run - _accel_lean
		p["head_x"] = 0.02 * move + 0.14 * run + _accel_lean * 0.6
		p["torso_z"] = _turn_lean
		# Reposo: respiración, cambio lento de peso de una pierna a otra y mirada que se mueve.
		var idle := 1.0 - move
		if idle > 0.0:
			var breath := sin(_idle_t * 1.7)
			var shift := sin(_idle_t * 0.37 + _idle_seed)
			p["torso_x"] += (0.012 * breath - 0.02) * idle
			p["hip_z"] += shift * 0.05 * idle
			p["torso_z"] += -shift * 0.035 * idle
			p["hip_y"] += (-0.012 * absf(shift) + 0.004 * breath) * idle
			p["knee"][0] += maxf(0.0, shift) * 0.14 * idle
			p["knee"][1] += maxf(0.0, -shift) * 0.14 * idle
			p["head_y"] += sin(_idle_t * 0.23 + _idle_seed * 2.0) * 0.16 * idle
			p["head_x"] += sin(_idle_t * 0.31) * 0.03 * idle
			for i in 2:
				p["arm"][i] += (0.03 * breath + 0.04) * idle
				p["elbow"][i] += (0.14 + 0.03 * breath) * idle
				p["arm_out"][i] += 0.03 * idle
	if crouch > 0.01 and on_floor:
		# Agachado: caderas abajo, rodillas muy flexionadas y tronco hacia delante.
		for i in 2:
			p["leg"][i] = lerpf(float(p["leg"][i]), 0.95 + float(p["leg"][i]) * 0.4, crouch)
			p["knee"][i] = lerpf(float(p["knee"][i]), 1.75 + float(p["knee"][i]) * 0.3, crouch)
			p["foot"][i] = lerpf(float(p["foot"][i]), 0.6, crouch)
		p["hip_y"] += -0.42 * crouch
		p["torso_x"] += -0.3 * crouch
		p["head_x"] += 0.25 * crouch
	if _talking and on_floor:
		# Hablar con las manos: antebrazos levantados, golpes de énfasis alternos y cabeceo.
		var t := _talk_t
		var beat := sin(t * 5.3) * 0.5 + 0.5
		var beat2 := sin(t * 3.9 + 1.3) * 0.5 + 0.5
		var lead := 0.5 + 0.5 * sin(t * 0.9 + _idle_seed)
		p["arm"] = [0.32 + 0.22 * beat * lead, 0.34 + 0.24 * beat2 * (1.0 - lead * 0.6)]
		p["elbow"] = [1.25 + 0.4 * beat * lead, 1.3 + 0.42 * beat2]
		p["arm_out"] = [0.16 + 0.12 * beat2, 0.18 + 0.14 * beat]
		p["arm_twist"] = [0.25 * beat, -0.25 * beat2]
		p["head_x"] += 0.05 * sin(t * 5.3) + 0.02
		p["head_y"] += 0.1 * sin(t * 1.7)
		p["torso_y"] += 0.06 * sin(t * 1.1)
		p["torso_x"] += -0.03
	if _flinch > 0.0:
		p["torso_x"] += 0.3 * _flinch
		p["head_x"] += -0.25 * _flinch
		p["torso_y"] += 0.2 * _flinch * _flinch_side
		p["hip_y"] += -0.05 * _flinch
	for k in overlay:
		var v = overlay[k]
		if v is Array and p.has(k):
			for i in 2:
				if v[i] != null:
					p[k][i] = v[i]
		else:
			p[k] = v
	_apply(_smooth(p, delta))


## Mezcla la pose objetivo con la anterior para que no haya saltos entre gestos.
func _smooth(target: Dictionary, delta: float) -> Dictionary:
	if _pose.is_empty():
		_pose = target.duplicate(true)
		return _pose
	var k := 1.0 - exp(-delta * 20.0)
	for key in target:
		var tv = target[key]
		if tv is Array:
			if not _pose.has(key):
				_pose[key] = (tv as Array).duplicate()
			for i in 2:
				_pose[key][i] = lerpf(float(_pose[key][i]), float(tv[i]), k)
		else:
			_pose[key] = lerpf(float(_pose.get(key, tv)), float(tv), k)
	if not target.has("arm_twist") and _pose.has("arm_twist"):
		for i in 2:
			_pose["arm_twist"][i] = lerpf(float(_pose["arm_twist"][i]), 0.0, k)
	return _pose


## El personaje gesticula con las manos mientras habla.
func set_talking(on: bool) -> void:
	if on and not _talking:
		_talk_t = 0.0
	_talking = on


## Sacudida al recibir un golpe o una bala (side: -1 izquierda, 1 derecha).
func flinch(side: float = 1.0) -> void:
	_flinch = 1.0
	_flinch_side = side


## Posturas de espera para personajes quietos.
func pose_idle_stance(kind: String) -> void:
	if not _built:
		return
	var p := _new_pose()
	match kind:
		"arms_crossed":
			p["arm"] = [0.25, 0.25]
			p["elbow"] = [1.4, 1.4]
			p["arm_out"] = [-0.32, -0.32]
		"hands_together":
			p["arm"] = [0.3, 0.3]
			p["elbow"] = [1.05, 1.05]
			p["arm_out"] = [-0.18, -0.18]
		"phone":
			# Antebrazo derecho doblado hasta la oreja (valores resueltos numéricamente sobre el
			# esqueleto auto_rig: muñeca junto a la oreja, codo bajo y hacia delante).
			# arm_twist gira el brazo sobre su eje para llevar la mano hacia la cabeza.
			if _seated:
				p = _seated_pose()
			p["arm"][1] = 1.0
			p["elbow"][1] = 2.65
			p["arm_out"][1] = -0.30
			p["arm_twist"] = [0.0, -0.55]
	_set_phone(kind == "phone")
	_apply(p)


## Sentado (asiento del coche o del autobús).
func set_seated(on: bool) -> void:
	_seated = on
	if not _built:
		return
	_set_phone(false)
	_apply(_seated_pose() if on else _new_pose())


static func _seated_pose() -> Dictionary:
	var p := _new_pose()
	p["leg"] = [1.45, 1.45]
	p["knee"] = [1.45, 1.45]
	p["arm"] = [0.85, 0.85]
	p["elbow"] = [0.5, 0.5]
	return p


## Móvil (caja negra) pegado a la mano derecha; solo se ve con la pose "phone".
func _set_phone(on: bool) -> void:
	if on and _phone == null:
		_phone = _make_phone()
	if _phone != null:
		_phone.visible = on


## Conjuntos de ropa del protagonista. El 0 es el del modelo (todo negro); el resto tiñe la
## sudadera (top) y el pantalón (pants) con assets/shaders/outfit.gdshader. null = sin teñir.
const OUTFITS := [
	{"name": "Sudadera negra y pantalón negro", "top": null, "pants": null},
	{"name": "Sudadera gris y vaqueros azules", "top": Color(0.62, 0.62, 0.65), "pants": Color(0.15, 0.22, 0.38)},
	{"name": "Sudadera roja y pantalón negro", "top": Color(0.6, 0.07, 0.08), "pants": null},
	{"name": "Sudadera blanca y pantalón caqui", "top": Color(0.9, 0.9, 0.87), "pants": Color(0.56, 0.48, 0.33)},
	{"name": "Sudadera azul y pantalón gris", "top": Color(0.1, 0.24, 0.55), "pants": Color(0.4, 0.4, 0.43)},
]
const OUTFIT_SHADER := "res://assets/shaders/outfit.gdshader"

## Tintes de la barbería: recolorean la barba, las cejas y la gorra a juego. 0 = original.
const HEAD_STYLES := [
	{"name": "Negro", "color": null},
	{"name": "Castaño", "color": Color(0.4, 0.25, 0.13)},
	{"name": "Gris ceniza", "color": Color(0.6, 0.6, 0.63)},
	{"name": "Platino", "color": Color(0.86, 0.8, 0.6)},
]

static var _outfit_mats: Dictionary = {}
var outfit: int = 0
var head_style: int = 0


static func outfit_name(i: int) -> String:
	return String(OUTFITS[clampi(i, 0, OUTFITS.size() - 1)]["name"])


static func head_name(i: int) -> String:
	return String(HEAD_STYLES[clampi(i, 0, HEAD_STYLES.size() - 1)]["name"])


## Cambia la ropa de un personaje con modelo (solo tiene efecto en modelos con esqueleto).
func set_outfit(i: int) -> void:
	set_look(i, head_style)


## Ropa (OUTFITS) y tinte de barba y gorra (HEAD_STYLES) del personaje.
func set_look(outfit_i: int, head_i: int) -> void:
	outfit = clampi(outfit_i, 0, OUTFITS.size() - 1)
	head_style = clampi(head_i, 0, HEAD_STYLES.size() - 1)
	if _skel == null:
		return
	var o: Dictionary = OUTFITS[outfit]
	var hc = HEAD_STYLES[head_style]["color"]
	for n in _skel.get_parent().find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.skin == null:
			continue
		for s in mi.mesh.get_surface_count():
			if o["top"] == null and o["pants"] == null and hc == null:
				mi.set_surface_override_material(s, null)
				continue
			var base := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if base == null or base.albedo_texture == null:
				continue
			var key := "%s_%d_%d_%d" % [String(look.get("model", "")), s, outfit, head_style]
			if not _outfit_mats.has(key):
				var sm := ShaderMaterial.new()
				sm.shader = load(OUTFIT_SHADER)
				sm.set_shader_parameter("albedo_tex", base.albedo_texture)
				sm.set_shader_parameter("use_normal", 1.0 if base.normal_enabled and base.normal_texture != null else 0.0)
				if base.normal_texture != null:
					sm.set_shader_parameter("normal_tex", base.normal_texture)
				if base.roughness_texture != null:
					sm.set_shader_parameter("rough_tex", base.roughness_texture)
					var ch := [Color(1, 0, 0, 0), Color(0, 1, 0, 0), Color(0, 0, 1, 0), Color(0, 0, 0, 1), Color(0.333, 0.333, 0.333, 0)]
					sm.set_shader_parameter("rough_channel", ch[clampi(int(base.roughness_texture_channel), 0, 4)])
				sm.set_shader_parameter("roughness_scale", base.roughness)
				sm.set_shader_parameter("top_amount", 0.0 if o["top"] == null else 1.0)
				sm.set_shader_parameter("pants_amount", 0.0 if o["pants"] == null else 1.0)
				sm.set_shader_parameter("head_amount", 0.0 if hc == null else 1.0)
				if o["top"] != null:
					sm.set_shader_parameter("top_color", o["top"])
				if o["pants"] != null:
					sm.set_shader_parameter("pants_color", o["pants"])
				if hc != null:
					sm.set_shader_parameter("head_color", hc)
				_outfit_mats[key] = sm
			mi.set_surface_override_material(s, _outfit_mats[key])


## Pistola (dos cajas oscuras) en la mano derecha. Solo personajes con esqueleto o procedurales.
func set_gun(on: bool, kind: String = "pistol") -> void:
	if _static_model or not _built:
		return
	if on and _gun == null:
		_gun = _make_gun()
	if _gun != null:
		_gun.visible = on
		# Las armas largas alargan la corredera (subfusil y escopeta).
		var root: Node3D = _gun.get_node_or_null("Pistola") if _gun.name != "Pistola" else _gun
		if root:
			var k := 1.0 if kind == "pistol" else (1.7 if kind == "smg" else 2.6)
			root.scale = Vector3(k, 1.0, 1.0) if _skel else Vector3(1.0, 1.0, k)


func _make_gun() -> Node3D:
	var root := Node3D.new()
	root.name = "Pistola"
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.06)
	m.roughness = 0.35
	m.metallic = 0.7
	var slide := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.material = m
	slide.mesh = sm
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.material = m
	grip.mesh = gm
	root.add_child(slide)
	root.add_child(grip)
	if _skel:
		# Eje X local de la mano = dirección del antebrazo.
		sm.size = Vector3(0.19, 0.035, 0.028)
		slide.position = Vector3(0.14, -0.05, 0.0)
		gm.size = Vector3(0.04, 0.10, 0.026)
		grip.position = Vector3(0.07, -0.095, 0.0)
		var att := BoneAttachment3D.new()
		att.name = "PistolaAdjunta"
		_skel.add_child(att)
		att.bone_name = "r_hand"
		att.add_child(root)
		return att
	sm.size = Vector3(0.028, 0.035, 0.19)
	slide.position = Vector3(0.0, -0.36, -0.09)
	gm.size = Vector3(0.026, 0.10, 0.04)
	grip.position = Vector3(0.0, -0.33, -0.01)
	_elbow[1].add_child(root)
	return root


func _make_phone() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "Movil"
	var bm := BoxMesh.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.04)
	m.roughness = 0.6
	m.metallic = 0.0
	bm.material = m
	mi.mesh = bm
	if _skel:
		# Hueso de la mano derecha: eje X local = dirección del antebrazo (modelo en pose T)
		bm.size = Vector3(0.15, 0.015, 0.068)
		mi.position = Vector3(0.07, -0.024, 0.0)
		var att := BoneAttachment3D.new()
		att.name = "MovilAdjunto"
		_skel.add_child(att)
		att.bone_name = "r_hand"
		att.add_child(mi)
		return att
	# Procedural: en el extremo del antebrazo derecho
	bm.size = Vector3(0.07, 0.14, 0.012)
	mi.position = Vector3(-0.02, -0.34, 0.0)
	_elbow[1].add_child(mi)
	return mi


func _apply(p: Dictionary) -> void:
	if _static_model:
		return
	if _skel:
		_apply_rigged(p)
		return
	for i in 2:
		_leg[i].rotation.x = p["leg"][i]
		_knee[i].rotation.x = -float(p["knee"][i])
		_arm[i].rotation.x = p["arm"][i]
		_arm[i].rotation.z = (-1.0 if i == 0 else 1.0) * float(p["arm_out"][i])
		_arm[i].rotation.y = float((p["arm_twist"] as Array)[i]) if p.has("arm_twist") else 0.0
		_elbow[i].rotation.x = p["elbow"][i]
	_torso.rotation = Vector3(p["torso_x"], p["torso_y"], 0)
	_head.rotation.x = p["head_x"]
	_hips.position.y = 0.95 + float(p["hip_y"])


func _apply_rigged(p: Dictionary) -> void:
	var b := _bones
	var tz := float(p.get("torso_z", 0.0))
	var hz := float(p.get("hip_z", 0.0))
	var hyaw := float(p.get("hip_yaw", 0.0))
	var heady := float(p.get("head_y", 0.0))
	_skel.set_bone_pose_position(b["hips"], _skel.get_bone_rest(b["hips"]).origin + Vector3(0, p["hip_y"], 0))
	_skel.set_bone_pose_rotation(b["hips"], Quaternion(Vector3.UP, hyaw) * Quaternion(Vector3.BACK, hz))
	# La columna deshace el giro de la pelvis y reparte la contrarrotación de los hombros.
	var ty := float(p["torso_y"]) - hyaw
	var tq := Quaternion(Vector3.RIGHT, float(p["torso_x"]) * 0.5) * Quaternion(Vector3.UP, ty * 0.5) * Quaternion(Vector3.BACK, (tz - hz) * 0.5)
	_skel.set_bone_pose_rotation(b["spine"], tq)
	_skel.set_bone_pose_rotation(b["chest"], tq)
	var hq := Quaternion(Vector3.RIGHT, float(p["head_x"]) * 0.5) * Quaternion(Vector3.UP, (heady - float(p["torso_y"]) * 0.6) * 0.5) * Quaternion(Vector3.BACK, -tz * 0.4)
	if b.has("neck"):
		_skel.set_bone_pose_rotation(b["neck"], hq)
		_skel.set_bone_pose_rotation(b["head"], hq)
	else:
		_skel.set_bone_pose_rotation(b["head"], hq * hq)
	for i in 2:
		var pre := "l_" if i == 0 else "r_"
		var sgn := 1.0 if i == 0 else -1.0
		_skel.set_bone_pose_rotation(b[pre + "thigh"], Quaternion(Vector3.RIGHT, p["leg"][i]))
		_skel.set_bone_pose_rotation(b[pre + "shin"], Quaternion(Vector3.RIGHT, -float(p["knee"][i])))
		if b.has(pre + "foot") and p.has("foot"):
			_skel.set_bone_pose_rotation(b[pre + "foot"], Quaternion(Vector3.RIGHT, float(p["foot"][i])))
		var hang := sgn * (PI * 0.5 - float(p["arm_out"][i]))
		var tw: float = float((p["arm_twist"] as Array)[i]) if p.has("arm_twist") else 0.0
		_skel.set_bone_pose_rotation(b[pre + "upperarm"], Quaternion(Vector3.RIGHT, p["arm"][i]) * Quaternion(Vector3.BACK, hang) * Quaternion(Vector3.RIGHT, tw))
		_skel.set_bone_pose_rotation(b[pre + "forearm"], Quaternion(Vector3.UP, -sgn * float(p["elbow"][i])))


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, metal: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color, metal)
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> Mesh:
	var key := "b%s" % size
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _sph(r: float) -> Mesh:
	var key := "s%.3f" % r
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 12
		m.rings = 6
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _cap(r: float, hgt: float) -> Mesh:
	var key := "c%.3f_%.3f" % [r, hgt]
	if not _mesh_cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(hgt, r * 2.0 + 0.001)
		m.radial_segments = 8
		m.rings = 2
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _cyl(r: float, hgt: float) -> Mesh:
	var key := "y%.3f_%.3f" % [r, hgt]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = hgt
		m.radial_segments = 10
		_mesh_cache[key] = m
	return _mesh_cache[key]
