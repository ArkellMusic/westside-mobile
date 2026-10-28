class_name TrafficControl
extends Node3D
## Semáforos y señales de STOP de Westbrook.
## - Semáforos en las calles z = 0, -100, -200 (avenidas x = -150, -50, 50, 150).
## - STOP a 4 vías en z = 100 y 200 para esas mismas avenidas.
## - Cruces con el bulevar de la playa (x = -235) y Eastline (x = 250): STOP solo
##   para el tráfico de la calle que se incorpora a la avenida.
## Todo el dibujo va en MultiMesh; cambiar de fase solo toca 12 materiales compartidos.

const GREEN_T := 14.0
const AMBER_T := 3.0
const RED_T := 1.5
const CYCLE := (GREEN_T + AMBER_T + RED_T) * 2.0
const LAMP_ON := 4.0
const STOP_LINE_GAP := 4.5   # m entre la línea de stop y el borde de la calzada que se cruza
const POLE_H := 6.2

const LIGHT_ZS := [0.0, -100.0, -200.0]
const STOP_ZS := [100.0, 200.0]
const INNER_XS := [-150.0, -50.0, 50.0, 150.0]

var time: float = 0.0
var enabled: bool = true

var _kind := {}              # Vector2i -> "light" | "stop4" | "stopT"
var _parity := {}            # Vector2i -> 0/1 (desfase)
var _mats: Array = []        # [grupo] -> [rojo, ámbar, verde] StandardMaterial3D
var _last_state: Array = ["", "", "", ""]
var _static: StaticBody3D
var _built := false


func _ready() -> void:
	set_process(false)


func build() -> void:
	if _built:
		return
	_built = true
	_static = StaticBody3D.new()
	_static.name = "TrafficControlCollision"
	add_child(_static)
	var light_xf: Array = [[], [], [], []]   # por grupo (paridad * 2 + eje)
	var stop_xf: Array = []
	var ai := 0
	for a in CityLayout.AVENUES:
		var x: float = a[0]
		var aw: float = a[1]
		var inner := INNER_XS.has(x)
		for s in CityLayout.STREETS:
			var z: float = s[0]
			var sw: float = s[1]
			var key := Vector2i(roundi(x), roundi(z))
			var center := Vector2(x, z)
			var dirs: Array = []
			if inner and LIGHT_ZS.has(z):
				_kind[key] = "light"
				_parity[key] = ai % 2
				dirs = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
			elif inner and STOP_ZS.has(z):
				_kind[key] = "stop4"
				dirs = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
			elif not inner:
				_kind[key] = "stopT"
				dirs = [Vector2(-1, 0)] if x < 0.0 else [Vector2(1, 0)]
			for d in dirs:
				var horizontal := absf(d.x) > absf(d.y)
				var own_half := (sw if horizontal else aw) * 0.5
				var cross_half := (aw if horizontal else sw) * 0.5
				var r := Vector2(-d.y, d.x)
				var pos: Vector2 = center - d * (cross_half + 1.2) + r * (own_half + 1.2)
				var xf := Transform3D(Basis.looking_at(Vector3(d.x, 0, d.y), Vector3.UP), Vector3(pos.x, 0, pos.y))
				if _kind[key] == "light":
					var g: int = int(_parity[key]) * 2 + (1 if horizontal else 0)
					light_xf[g].append(xf)
					_collider(Vector3(pos.x, POLE_H * 0.5, pos.y), Vector3(0.28, POLE_H, 0.28))
				else:
					stop_xf.append(xf)
					_collider(Vector3(pos.x, 1.3, pos.y), Vector3(0.22, 2.6, 0.22))
		if inner:
			ai += 1
	_build_lights(light_xf)
	_build_stop_signs(stop_xf)
	for g in 4:
		_set_group_state(g, "red")
	set_process(true)
	_update_states()


# ---------------------------------------------------------------- consulta

## Señal que ve un coche que se acerca al cruce `node_pos` (XZ) con dirección `dir`.
## Devuelve "green", "amber", "red", "stop" o "none".
func signal_for(node_pos: Vector2, dir: Vector2) -> String:
	var key := Vector2i(roundi(node_pos.x), roundi(node_pos.y))
	if not _kind.has(key):
		return "none"
	var horizontal := absf(dir.x) > absf(dir.y)
	match String(_kind[key]):
		"light":
			return _state(int(_parity[key]), 1 if horizontal else 0)
		"stop4":
			return "stop"
		"stopT":
			return "stop" if horizontal else "none"
	return "none"


## Distancia desde el centro del cruce hasta la línea de stop para un coche con rumbo `dir`.
func stop_offset(node_pos: Vector2, dir: Vector2) -> float:
	return cross_half_width(node_pos, dir) + STOP_LINE_GAP


## Semiancho de la calzada que cruza el coche que avanza en `dir` hacia `node_pos`.
func cross_half_width(node_pos: Vector2, dir: Vector2) -> float:
	if absf(dir.x) > absf(dir.y):
		for a in CityLayout.AVENUES:
			if absf(float(a[0]) - node_pos.x) < 1.0:
				return float(a[1]) * 0.5
		return CityLayout.AVENUE_WIDTH * 0.5
	for s in CityLayout.STREETS:
		if absf(float(s[0]) - node_pos.y) < 1.0:
			return float(s[1]) * 0.5
	return CityLayout.STREET_WIDTH * 0.5


## Estado de un eje (0 = norte-sur, 1 = este-oeste) según el reloj y la paridad.
func _state(parity: int, axis: int) -> String:
	var t := fposmod(time + float(parity) * CYCLE * 0.5, CYCLE)
	var half := GREEN_T + AMBER_T + RED_T
	var local := t
	var phase_axis := 0
	if t >= half:
		local = t - half
		phase_axis = 1
	if phase_axis != axis:
		return "red"
	if local < GREEN_T:
		return "green"
	if local < GREEN_T + AMBER_T:
		return "amber"
	return "red"


# ---------------------------------------------------------------- actualización

func _process(delta: float) -> void:
	if not enabled:
		return
	time += delta
	_update_states()


func _update_states() -> void:
	for g in 4:
		var st := _state(g >> 1, g & 1)
		if st != _last_state[g]:
			_set_group_state(g, st)


func _set_group_state(g: int, st: String) -> void:
	_last_state[g] = st
	var mats: Array = _mats[g]
	var active := 0 if st == "red" else (1 if st == "amber" else 2)
	for i in 3:
		(mats[i] as StandardMaterial3D).emission_energy_multiplier = LAMP_ON if i == active else 0.0


# ---------------------------------------------------------------- geometría

func _collider(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	_static.add_child(cs)


func _lamp_material(c: Color) -> StandardMaterial3D:
	var m := MeshBuilder.material(c.darkened(0.7), 0.35)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.0
	return m


func _build_lights(light_xf: Array) -> void:
	var metal := MeshBuilder.material(Color(0.2, 0.21, 0.23), 0.55, 0.5)
	var casing := MeshBuilder.material(Color(0.07, 0.07, 0.08), 0.6, 0.2)
	var cols := [Color(1.0, 0.1, 0.08), Color(1.0, 0.62, 0.05), Color(0.1, 1.0, 0.35)]
	for g in 4:
		var mats: Array = []
		for c in cols:
			mats.append(_lamp_material(c))
		_mats.append(mats)
		var xfs: Array = light_xf[g]
		if xfs.is_empty():
			continue
		var horizontal := g % 2 == 1
		var lane := Traffic.LANE_OFFSET_STREET if horizontal else Traffic.LANE_OFFSET_AVENUE
		var own_half := (CityLayout.STREET_WIDTH if horizontal else CityLayout.AVENUE_WIDTH) * 0.5
		var arm_len := own_half + 1.2 - lane
		var b := MeshBuilder.new()
		b.surface("metal", metal)
		b.surface("casing", casing)
		b.surface("r", mats[0])
		b.surface("a", mats[1])
		b.surface("g", mats[2])
		b.cylinder("metal", Vector3.ZERO, 0.12, 0.08, POLE_H, 8)
		b.box("metal", Vector3(-arm_len * 0.5, POLE_H - 0.15, 0), Vector3(arm_len, 0.14, 0.14))
		var hy := 5.1
		b.box("casing", Vector3(-arm_len, hy, 0), Vector3(0.46, 1.25, 0.34))
		b.box("casing", Vector3(-arm_len, hy + 0.1, -0.2), Vector3(0.9, 1.7, 0.05))
		b.box("metal", Vector3(-arm_len, POLE_H - 0.5, 0), Vector3(0.08, 0.5, 0.08))
		var rot := Basis(Vector3.RIGHT, PI * 0.5)
		var ys := [hy + 0.4, hy, hy - 0.4]
		var keys := ["r", "a", "g"]
		for i in 3:
			b.cylinder(keys[i], Vector3.ZERO, 0.15, 0.15, 0.07, 10, Transform3D(rot, Vector3(-arm_len, ys[i], 0.165)))
			# visera sobre cada lámpara
			b.box("casing", Vector3(-arm_len, ys[i] + 0.17, 0.25), Vector3(0.34, 0.04, 0.22))
		_multimesh(b.commit(), xfs, "Lights%d" % g)


func _build_stop_signs(stop_xf: Array) -> void:
	var metal := MeshBuilder.material(Color(0.55, 0.57, 0.6), 0.5, 0.6)
	var red := MeshBuilder.material(Color(0.702, 0.078, 0.106), 0.5)
	var white := MeshBuilder.material(Color(0.95, 0.95, 0.95), 0.5)
	var b := MeshBuilder.new()
	b.surface("metal", metal)
	b.surface("red", red)
	b.surface("white", white)
	b.cylinder("metal", Vector3.ZERO, 0.045, 0.045, 2.6, 6)
	var oct := Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, deg_to_rad(22.5))
	var cy := 2.1
	b.cylinder("metal", Vector3.ZERO, 0.42, 0.42, 0.02, 8, Transform3D(oct, Vector3(0, cy, 0.04)))
	b.cylinder("white", Vector3.ZERO, 0.43, 0.43, 0.025, 8, Transform3D(oct, Vector3(0, cy, 0.06)))
	b.cylinder("red", Vector3.ZERO, 0.375, 0.375, 0.02, 8, Transform3D(oct, Vector3(0, cy, 0.085)))
	_multimesh(b.commit(), stop_xf, "StopSigns")
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.9
	for xf in stop_xf:
		var l := Label3D.new()
		l.text = "STOP"
		l.font = font
		l.font_size = 52
		l.pixel_size = 0.0034
		l.outline_size = 3
		l.modulate = Color(1, 1, 1)
		l.outline_modulate = Color(1, 1, 1)
		l.double_sided = false
		l.shaded = false
		l.visibility_range_end = 70.0
		l.transform = Transform3D((xf as Transform3D).basis, (xf as Transform3D).origin + (xf as Transform3D).basis * Vector3(0, cy, 0.105))
		add_child(l)


func _multimesh(mesh: Mesh, xfs: Array, node_name: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.visibility_range_end = 260.0
	add_child(mi)
