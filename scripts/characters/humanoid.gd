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
var _blend_speed: float = 0.0

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm := [null, null]
var _elbow := [null, null]
var _leg := [null, null]
var _knee := [null, null]
var _seated: bool = false

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


## speed en m/s, on_floor para la pose aérea.
func animate(delta: float, speed: float, on_floor: bool) -> void:
	if _hips == null:
		return
	if _seated:
		return
	_blend_speed = lerpf(_blend_speed, speed, clampf(delta * 8.0, 0.0, 1.0))
	var s := _blend_speed
	var run := clampf((s - 3.0) / 3.0, 0.0, 1.0)
	var walk := clampf(s / 2.0, 0.0, 1.0)
	var freq := lerpf(1.6, 2.6, run) * TAU * (0.4 + clampf(s / 6.0, 0.0, 1.0) * 0.6)
	_phase = fposmod(_phase + delta * freq, TAU)
	var sw := sin(_phase)
	var amp := lerpf(0.45, 0.85, run) * walk

	if not on_floor:
		for i in 2:
			_leg[i].rotation.x = -0.5 if i == 0 else 0.3
			_knee[i].rotation.x = 0.9 if i == 0 else 0.3
			_arm[i].rotation.x = -0.9
			_arm[i].rotation.z = (-1.0 if i == 0 else 1.0) * 0.5
			_elbow[i].rotation.x = -0.4
		_torso.rotation.x = -0.1
		return

	for i in 2:
		var side := sw if i == 0 else -sw
		_leg[i].rotation.x = side * amp
		_knee[i].rotation.x = maxf(0.0, -side) * amp * 1.4 + 0.05
		_arm[i].rotation.x = -side * amp * 0.9
		_arm[i].rotation.z = (-1.0 if i == 0 else 1.0) * (0.08 + 0.05 * run)
		_elbow[i].rotation.x = -(0.25 + 0.9 * run) * walk - 0.1
	var breathe := sin(Time.get_ticks_msec() * 0.002) * 0.015 * (1.0 - walk)
	_hips.position.y = 0.95 - absf(cos(_phase)) * 0.04 * walk + breathe
	_torso.rotation.x = -0.18 * run - 0.03 * walk
	_torso.rotation.y = sw * 0.08 * walk
	_head.rotation.x = 0.12 * run


## Pose de brazos cruzados / manos juntas para personajes que esperan.
func pose_idle_stance(kind: String) -> void:
	if _hips == null:
		return
	match kind:
		"arms_crossed":
			for i in 2:
				_arm[i].rotation = Vector3(-0.5, 0, (-1.0 if i == 0 else 1.0) * -0.35)
				_elbow[i].rotation = Vector3(-1.9, 0, 0)
		"hands_together":
			for i in 2:
				_arm[i].rotation = Vector3(-0.35, 0, (-1.0 if i == 0 else 1.0) * -0.25)
				_elbow[i].rotation = Vector3(-1.2, 0, 0)
		"phone":
			_arm[1].rotation = Vector3(-0.3, 0, 0.6)
			_elbow[1].rotation = Vector3(-2.4, 0, 0)


## Pose sentada (pasajero/conductor o asiento del autobús).
func set_seated(on: bool) -> void:
	_seated = on
	if _hips == null:
		return
	for i in 2:
		_leg[i].rotation.x = -1.45 if on else 0.0
		_knee[i].rotation.x = 1.45 if on else 0.0
		_arm[i].rotation.x = -0.9 if on else 0.0
		_elbow[i].rotation.x = -0.5 if on else 0.0
	_hips.position.y = 0.95
	_torso.rotation = Vector3.ZERO


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
