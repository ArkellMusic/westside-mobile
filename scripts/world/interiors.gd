class_name Interiors
extends Node3D
## Lugares enterables de Westbrook, montados lejos de la ciudad (x = 3000, z = -3000,
## uno cada 60 m) y construidos al entrar por primera vez:
##   - Casa de Mack (cama = guardar partida)
##   - Vargas Auto Works (taller de Loco)
##   - Comisaría South Veyra PD (lobby con celda)
##   - Hospital Westbrook General
## Además crea los edificios exteriores nuevos del distrito comercial junto al taller:
## "Pinta y Listo" (taller de pintura: reparar + pintar + quitar búsqueda por $100),
## la comisaría y el hospital, y la puerta lateral del taller Vargas.
##
## API pública: enter(id), leave(), interaction(pos, can_enter), police_respawn_point(),
## hospital_respawn_point(), wasted_respawn(), radar_markers(from), reset().
## Los datos de la ciudad (suelo, aceras) están a y = 0,10-0,12.

const PROPS := "res://assets/props/"
const KIT := "res://assets/kit/city/"
const TEX := "res://assets/textures/"
const BASE := Vector3(3000.0, 0.0, -3000.0)
const SPACING := 60.0
const VIS_END := 120.0
const RESPRAY_PRICE := 100
const HOSPITAL_BILL := 100

## Referencia al nodo principal (main.gd). Se asigna antes de build().
var main
var busy: bool = false
var inside: int = -1
var respray_rect := Rect2(65.6, -122.6, 9.8, 9.6)

var _city: CityBuilder
var _places: Array = []
var _roots: Dictionary = {}
var _scenes: Dictionary = {}
var _bounds: Dictionary = {}
var _mats: Dictionary = {}
var _statics: StaticBody3D
var _respray_cd: float = 0.0
var _env_saved: Dictionary = {}
var _env_on: bool = false
var _wasted_running: bool = false
var _model_npcs: Array = []
var _follow_light: OmniLight3D


# ---------------------------------------------------------------- definición

func _define_places() -> void:
	var door := CityLayout.landmark("mack_door")
	_places = [
		{"id": "house", "name": "Casa de Mack", "size": Vector2(12, 10), "height": 2.9, "door_x": 0.0,
			"enter": door + Vector3(0, 0, 1.0), "radius": 2.4, "out": door + Vector3(0, 0.55, 0.4), "out_yaw": 0.0,
			"ambient": Color(0.95, 0.86, 0.75), "energy": 0.4},
		{"id": "garage", "name": "Vargas Auto Works", "size": Vector2(20, 14), "height": 6.0, "door_x": -7.0,
			"enter": Vector3(85.7, 0, -121.0), "radius": 2.2, "out": Vector3(85.1, 0.25, -121.0), "out_yaw": PI * 0.5,
			"ambient": Color(0.82, 0.84, 0.9), "energy": 0.7},
		{"id": "police", "name": "South Veyra PD", "size": Vector2(16, 10), "height": 3.2, "door_x": -5.0,
			"enter": Vector3(122.25, 0, -108.6), "radius": 2.2, "out": Vector3(122.25, 0.25, -107.2), "out_yaw": PI,
			"ambient": Color(0.78, 0.84, 1.0), "energy": 0.3},
		{"id": "hospital", "name": "Westbrook General", "size": Vector2(16, 12), "height": 3.4, "door_x": -4.0,
			"enter": Vector3(193.9, 0, -128.2), "radius": 2.2, "out": Vector3(193.9, 0.25, -126.8), "out_yaw": PI,
			"ambient": Color(0.86, 0.95, 0.95), "energy": 0.3},
		{"id": "subway", "name": "Estación Westbrook", "size": Vector2(16, 10), "height": 3.4, "door_x": 0.0,
			"enter": Vector3(-59.0, 0, -20.0), "radius": 2.4, "out": Vector3(-59.0, 0.25, -18.2), "out_yaw": PI,
			"ambient": Color(0.75, 0.82, 0.95), "energy": 0.8,
			"model": "res://assets/buildings/subway/subway.scn", "origin": Vector3(3600, 100, -3400),
			"anchor": Vector2(40.0, -36.0), "floor_ymax": 12.2, "spawn": Vector3(0, 0.1, 2.5), "spawn_yaw": PI},
	]


func _origin(i: int) -> Vector3:
	if _places[i].has("origin"):
		return _places[i]["origin"]
	return BASE + Vector3(i * SPACING, 0.0, 0.0)


func place_index(id: String) -> int:
	for i in _places.size():
		if _places[i]["id"] == id:
			return i
	return -1


# ---------------------------------------------------------------- construcción exterior

func build(city: CityBuilder) -> void:
	_city = city
	_define_places()
	_statics = StaticBody3D.new()
	_statics.name = "InteriorsCollision"
	add_child(_statics)
	_build_garage_side_door()
	var kb := KitBuildings.new()
	kb.name = "StationFacades"
	add_child(kb)
	kb._rng.seed = 4242
	kb._build_modular(Vector2(122.25, -117.0), Vector3(16, 9.6, 14), 0)
	kb._flush()
	if not city.night_changed.is_connected(kb.set_night):
		city.night_changed.connect(kb.set_night)
	_build_respray()
	_build_police_exterior()
	# Edificios, vehículos y personajes reales (hospital, cárcel, aparcamiento, flota policial).
	var rs := RealSites.new()
	rs.name = "RealSites"
	add_child(rs)
	rs.build(city, self, main)


func _build_garage_side_door() -> void:
	var metal := _mat(Color(0.2, 0.22, 0.25), 0.5, 0.6)
	var frame := _mat(Color(0.9, 0.75, 0.15), 0.6)
	var x := 86.93
	var z := -121.0
	_mesh_box(self, Vector3(x, 1.1, z), Vector3(0.12, 2.2, 1.1), metal)
	for dz in [-0.62, 0.62]:
		_mesh_box(self, Vector3(x - 0.02, 1.15, z + dz), Vector3(0.14, 2.3, 0.14), frame)
	_mesh_box(self, Vector3(x - 0.02, 2.3, z), Vector3(0.14, 0.14, 1.38), frame)
	_mesh_box(self, Vector3(x - 0.3, 2.75, z), Vector3(0.5, 0.35, 0.9), _mat(Color(0.12, 0.12, 0.13), 0.7))
	_label(self, "TALLER", Vector3(x - 0.58, 2.75, z), -90.0, 40, Color(1, 0.9, 0.5), 0.006)
	var lamp := _mesh_box(self, Vector3(x - 0.15, 2.55, z - 0.75), Vector3(0.18, 0.18, 0.18), _mat(Color(1, 0.9, 0.6), 0.4, 0.0, Color(1, 0.8, 0.4), 2.0))
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _solid_box(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	_statics.add_child(cs)


## Taller de pintura "Pinta y Listo": nave abierta por delante donde se mete el coche.
func _build_respray() -> void:
	var c := Vector3(70.5, 0.1, -117.5)
	var w := 12.0
	var d := 15.0
	var h := 5.6
	var wall := _pbr("concrete_wall", Color(0.95, 0.95, 1.0), 3.0)
	var floor_m := _pbr("concrete", Color(0.75, 0.75, 0.78), 3.0)
	var trim := _mat(Color(0.05, 0.45, 0.55), 0.5)
	var dark := _mat(Color(0.05, 0.06, 0.08), 0.6)
	var t := 0.4
	var open_w := 6.4
	var open_h := 4.2
	var front := c.z + d * 0.5
	_mesh_box(self, Vector3(c.x, c.y + 0.01, c.z), Vector3(w - 0.2, 0.02, d - 0.2), floor_m)
	# Paredes: fondo, laterales y frente con una gran abertura central.
	_wall_box(Vector3(c.x, c.y + h * 0.5, c.z - d * 0.5 + t * 0.5), Vector3(w, h, t), wall)
	_wall_box(Vector3(c.x - w * 0.5 + t * 0.5, c.y + h * 0.5, c.z), Vector3(t, h, d), wall)
	_wall_box(Vector3(c.x + w * 0.5 - t * 0.5, c.y + h * 0.5, c.z), Vector3(t, h, d), wall)
	var side_w := (w - open_w) * 0.5
	for sx in [-1.0, 1.0]:
		_wall_box(Vector3(c.x + sx * (open_w * 0.5 + side_w * 0.5), c.y + h * 0.5, front - t * 0.5), Vector3(side_w, h, t), wall)
	_wall_box(Vector3(c.x, c.y + open_h + (h - open_h) * 0.5, front - t * 0.5), Vector3(open_w, h - open_h, t), trim)
	_wall_box(Vector3(c.x, c.y + h + 0.15, c.z), Vector3(w + 0.4, 0.3, d + 0.4), dark)
	# Marco de la abertura y franjas de color en la fachada.
	for sx in [-1.0, 1.0]:
		_mesh_box(self, Vector3(c.x + sx * (open_w * 0.5 + 0.12), c.y + open_h * 0.5, front + 0.05), Vector3(0.24, open_h, 0.12), _mat(Color(0.95, 0.7, 0.1), 0.5))
	_mesh_box(self, Vector3(c.x, c.y + open_h + 0.1, front + 0.05), Vector3(open_w + 0.48, 0.2, 0.12), _mat(Color(0.95, 0.7, 0.1), 0.5))
	var stripe_cols := [Color(0.9, 0.15, 0.15), Color(0.95, 0.7, 0.1), Color(0.2, 0.7, 0.3), Color(0.15, 0.4, 0.9), Color(0.6, 0.2, 0.8)]
	for k in stripe_cols.size():
		_mesh_box(self, Vector3(c.x - 4.8 + k * 2.4, c.y + 0.5, front + 0.03), Vector3(2.2, 0.7, 0.06), _mat(stripe_cols[k], 0.5))
	# Cartel: placa oscura con letras luminosas, y cartel vertical en la azotea.
	_mesh_box(self, Vector3(c.x, c.y + 4.95, front + 0.1), Vector3(6.2, 0.95, 0.12), _mat(Color(0.03, 0.05, 0.1), 0.5))
	# Sin rótulo exterior: el nombre se ve en el mapa.
	#_label(self, "PINTA Y LISTO", Vector3(c.x, c.y + 4.95, front + 0.19), 0.0, 120, Color(1.0, 0.85, 0.2), 0.0075)
	var pylon := _mesh_box(self, Vector3(c.x + 4.9, c.y + h + 1.6, front - 0.4), Vector3(0.3, 3.2, 0.3), dark)
	pylon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_box(self, Vector3(c.x + 4.9, c.y + h + 3.6, front - 0.4), Vector3(1.6, 1.0, 0.2), _mat(Color(0.95, 0.7, 0.1), 0.4, 0.0, Color(1.0, 0.7, 0.1), 1.2))
	_label(self, "$100", Vector3(c.x + 4.9, c.y + h + 3.6, front - 0.28), 0.0, 90, Color(0.05, 0.05, 0.05), 0.008)
	# Interior: suelo marcado, estantes con botes, paneles de color y luces.
	_label(self, "METE EL COCHE · $100", Vector3(c.x, c.y + 0.04, c.z + 3.6), 0.0, 80, Color(1, 0.9, 0.3), 0.008, true)
	_mesh_box(self, Vector3(c.x, c.y + 0.03, c.z - 1.6), Vector3(5.0, 0.01, 7.4), _mat(Color(0.95, 0.75, 0.1), 0.6, 0.0, Color(0.9, 0.6, 0.05), 0.35))
	_mesh_box(self, Vector3(c.x, c.y + 0.035, c.z - 1.6), Vector3(4.7, 0.01, 7.1), _pbr("concrete", Color(0.7, 0.7, 0.74), 3.0))
	# Techo interior claro (la caja exterior es oscura).
	_mesh_box(self, Vector3(c.x, c.y + h - 0.02, c.z), Vector3(w - t * 2.0, 0.04, d - t), _mat(Color(0.82, 0.84, 0.88), 0.9))
	var bx := c.x - w * 0.5 + t
	for k in 4:
		var col: Color = stripe_cols[k]
		_mesh_box(self, Vector3(c.x - 3.9 + k * 0.5, c.y + 1.6, c.z - d * 0.5 + t + 0.03), Vector3(0.44, 1.0, 0.04), _mat(col, 0.3, 0.2))
	_prop(self, "steel_frame_shelves_02/steel_frame_shelves_02_1k.gltf", Vector3(bx + 0.4, c.y, c.z - d * 0.5 + 1.0), 90.0, 1.0, true, true)
	for k in 3:
		_prop(self, "spray_paint_bottles/spray_paint_bottles_1k.gltf", Vector3(bx + 0.4, c.y + 0.55 + k * 0.5, c.z - d * 0.5 + 1.0), 90.0, 1.5, false, true)
	for k in 3:
		_mesh_box(self, Vector3(c.x - 2.0 + k * 2.0, c.y + h - 0.15, c.z - 1.5), Vector3(0.4, 0.08, 5.0), _mat(Color(1, 1, 0.95), 0.3, 0.0, Color(1, 0.97, 0.88), 2.5))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.95, 0.85)
	lamp.light_energy = 3.2
	lamp.omni_range = 14.0
	lamp.shadow_enabled = false
	lamp.position = Vector3(c.x, c.y + h - 1.4, c.z - 1.0)
	add_child(lamp)
	var lamp2 := OmniLight3D.new()
	lamp2.light_color = Color(1.0, 0.95, 0.85)
	lamp2.light_energy = 2.0
	lamp2.omni_range = 9.0
	lamp2.position = Vector3(c.x, c.y + 2.6, c.z + 4.5)
	add_child(lamp2)
	_city.footprints.append(Rect2(c.x - w * 0.5, c.z - d * 0.5, w, d))


func _build_police_exterior() -> void:
	var cx := 122.25
	var front := -110.0
	var blue := _mat(Color(0.05, 0.12, 0.35), 0.5, 0.2)
	var glass := _mat(Color(0.04, 0.08, 0.12), 0.1, 0.3, Color(0.1, 0.25, 0.4), 0.4)
	_solid_box(Vector3(cx, 4.8, -117.0), Vector3(16, 9.6, 14))
	_city.footprints.append(Rect2(cx - 8.0, -124.0, 16.0, 14.0))
	# Puerta: cristal, marco, marquesina y luz azul.
	_mesh_box(self, Vector3(cx, 1.3, front + 0.07), Vector3(2.1, 2.6, 0.1), glass)
	for sx in [-1.0, 1.0]:
		_mesh_box(self, Vector3(cx + sx * 1.15, 1.35, front + 0.1), Vector3(0.2, 2.7, 0.16), blue)
	_mesh_box(self, Vector3(cx, 2.75, front + 0.1), Vector3(2.5, 0.2, 0.16), blue)
	_mesh_box(self, Vector3(cx, 3.05, front + 0.9), Vector3(4.4, 0.14, 1.8), blue)
	_mesh_box(self, Vector3(cx, 3.2, front + 1.72), Vector3(4.4, 0.3, 0.1), _mat(Color(0.9, 0.9, 0.95), 0.4))
	_mesh_box(self, Vector3(cx - 2.0, 3.58, front + 0.12), Vector3(0.5, 0.6, 0.4), _mat(Color(0.1, 0.3, 1.0), 0.3, 0.0, Color(0.1, 0.35, 1.0), 3.0))
	_mesh_box(self, Vector3(cx + 2.0, 3.58, front + 0.12), Vector3(0.5, 0.6, 0.4), _mat(Color(0.1, 0.3, 1.0), 0.3, 0.0, Color(0.1, 0.35, 1.0), 3.0))
	_mesh_box(self, Vector3(cx, 3.9, front + 0.1), Vector3(9.0, 1.0, 0.14), _mat(Color(0.03, 0.05, 0.12), 0.5))
	# Sin rótulo exterior: el nombre se ve en el mapa.
	#_label(self, "SOUTH VEYRA PD", Vector3(cx, 3.9, front + 0.2), 0.0, 120, Color(0.85, 0.92, 1.0), 0.0085)
	_label(self, "POLICÍA", Vector3(cx, 3.35, front + 1.79), 0.0, 52, Color(0.1, 0.2, 0.5), 0.006)
	var l := OmniLight3D.new()
	l.light_color = Color(0.5, 0.65, 1.0)
	l.light_energy = 1.4
	l.omni_range = 7.0
	l.shadow_enabled = false
	l.position = Vector3(cx, 2.6, front + 1.2)
	add_child(l)


# ---------------------------------------------------------------- puntos de reaparición

func police_respawn_point() -> Transform3D:
	var p: Dictionary = _places[place_index("police")]
	return Transform3D(Basis(Vector3.UP, float(p["out_yaw"])), p["out"])


func hospital_respawn_point() -> Transform3D:
	var p: Dictionary = _places[place_index("hospital")]
	return Transform3D(Basis(Vector3.UP, float(p["out_yaw"])), p["out"])


func current_name() -> String:
	return String(_places[inside]["name"]) if inside >= 0 else ""


## Posición y orientación (yaw) en la calle de la puerta del interior actual.
func outside_transform() -> Transform3D:
	if inside < 0:
		return Transform3D.IDENTITY
	var p: Dictionary = _places[inside]
	return Transform3D(Basis(Vector3.UP, float(p["out_yaw"])), p["out"])


func radar_markers(from: Vector3) -> Array:
	var out: Array = []
	var defs := [
		[Vector3(193.9, 0, -129.9), Color(0.88, 0.15, 0.18), "H"],
		[Vector3(-59.0, 0, -20.0), Color(0.95, 0.65, 0.1), "M"],
		[Vector3(122.25, 0, -110.0), Color(0.2, 0.35, 0.95), "P"],
		[Vector3(70.5, 0, -110.0), Color(0.2, 0.7, 0.3), "$"],
	]
	for d in defs:
		var p: Vector3 = d[0]
		if Vector2(p.x - from.x, p.z - from.z).length() < 150.0:
			out.append({"pos": p, "color": d[1], "label": d[2]})
	return out


# ---------------------------------------------------------------- interacción

## Devuelve {label, action} si hay algo que hacer cerca de `pos` (vacío si no).
func interaction(pos: Vector3, can_enter: bool) -> Dictionary:
	if busy:
		return {}
	if inside >= 0:
		var p: Dictionary = _places[inside]
		var o := _origin(inside)
		var size: Vector2 = p["size"]
		var ex := o + Vector3(float(p["door_x"]), 0, size.y * 0.5 - 0.9)
		if p.has("model"):
			ex = o
		if Vector2(pos.x - ex.x, pos.z - ex.z).length() < 1.9:
			return {"label": "Salir", "action": func() -> void: leave()}
		if p["id"] == "house" and Vector2(pos.x - (o.x + 4.4), pos.z - (o.z + 3.2)).length() < 2.0:
			return {"label": "Guardar partida", "action": func() -> void: _save_at_bed()}
		return {}
	if not can_enter:
		return {}
	for i in _places.size():
		var p: Dictionary = _places[i]
		var e: Vector3 = p["enter"]
		if Vector2(pos.x - e.x, pos.z - e.z).length() < float(p["radius"]):
			var idx := i
			return {"label": "Entrar", "action": func() -> void: enter_index(idx)}
	return {}


func enter(id: String) -> void:
	var i := place_index(id)
	if i >= 0:
		await enter_index(i)


func enter_index(i: int) -> void:
	if busy or inside >= 0:
		return
	busy = true
	main.hud.fade_to(1.0, 0.35)
	main.player.input_enabled = false
	await get_tree().create_timer(0.4).timeout
	_ensure_built(i)
	for k in _roots:
		(_roots[k] as Node3D).visible = (k == i)
	inside = i
	var p: Dictionary = _places[i]
	var size: Vector2 = p["size"]
	var spawn := _origin(i) + Vector3(float(p["door_x"]), 0.1, size.y * 0.5 - 1.7)
	var syaw := 0.0
	if p.has("model"):
		spawn = _origin(i) + (p["spawn"] as Vector3)
		syaw = float(p["spawn_yaw"])
		_set_follow_light(true)
	for n in _model_npcs:
		if is_instance_valid(n):
			n.player = main.player
	main.player.place(spawn, syaw)
	_snap_camera(syaw, 3.0)
	await get_tree().create_timer(0.2).timeout
	main.hud.fade_to(0.0, 0.35)
	main.player.input_enabled = true
	busy = false


func leave() -> void:
	if busy or inside < 0:
		return
	busy = true
	main.hud.fade_to(1.0, 0.35)
	main.player.input_enabled = false
	await get_tree().create_timer(0.4).timeout
	_exit_to_street()
	await get_tree().create_timer(0.2).timeout
	main.hud.fade_to(0.0, 0.35)
	main.player.input_enabled = true
	busy = false


func _exit_to_street() -> void:
	var t := outside_transform()
	var yaw := t.basis.get_euler().y
	inside = -1
	_set_follow_light(false)
	_restore_env()
	for k in _roots:
		(_roots[k] as Node3D).visible = false
	main.player.place(t.origin, yaw)
	_snap_camera(yaw, 4.2)


func _snap_camera(yaw: float, dist: float) -> void:
	main.rig.yaw = yaw
	main.rig.pitch = -0.25
	main.rig.distance = dist
	main.rig.global_position = main.player.global_position + Vector3.UP * main.rig.height


## Vuelve al estado normal del mundo (carga de partida, volver al menú).
func reset() -> void:
	inside = -1
	busy = false
	_wasted_running = false
	_restore_env()
	for k in _roots:
		(_roots[k] as Node3D).visible = false
	if main and main.rig and not main.current_vehicle:
		main.rig.distance = 4.2


func _save_at_bed() -> void:
	main.capture_state()
	if SaveSystem.save_slot(1):
		main.hud.toast("Partida guardada", "Casa de Mack · ranura 1", 2.5)
	else:
		main.hud.toast("No se pudo guardar", "", 2.5)


## Fin de partida por salud: factura del hospital y reaparición en Westbrook General.
func wasted_respawn() -> void:
	if _wasted_running or busy:
		return
	_wasted_running = true
	busy = true
	main.hud.fade_to(1.0, 0.8)
	main.hud.toast("HAS CAÍDO", "-$%d de factura del hospital" % HOSPITAL_BILL, 3.0)
	if main.current_vehicle:
		main.current_vehicle.linear_velocity = Vector3.ZERO
		await main.leave_vehicle()
	await get_tree().create_timer(1.6).timeout
	GameState.add_money(-HOSPITAL_BILL)
	main.wanted = 0
	main.hud.set_wanted(0)
	if inside >= 0:
		inside = -1
		_restore_env()
		for k in _roots:
			(_roots[k] as Node3D).visible = false
	var t := hospital_respawn_point()
	main.player.place(t.origin, t.basis.get_euler().y)
	_snap_camera(t.basis.get_euler().y, 4.2)
	GameState.set_health(GameState.MAX_HEALTH)
	await get_tree().create_timer(0.4).timeout
	main.hud.fade_to(0.0, 0.8)
	busy = false
	_wasted_running = false


# ---------------------------------------------------------------- bucle

func _process(delta: float) -> void:
	if main == null or main.sky == null:
		return
	if inside >= 0:
		_apply_env()
	_respray_cd = maxf(_respray_cd - delta, 0.0)
	var car = main.current_vehicle
	if car and main.current_seat == "driver" and not busy and _respray_cd <= 0.0 and inside < 0:
		var p: Vector3 = car.global_position
		if respray_rect.has_point(Vector2(p.x, p.z)) and p.y < 2.0 and car.linear_velocity.length() < 4.0:
			_respray(car)


func _apply_env() -> void:
	var env: Environment = main.sky.env
	if not _env_on:
		_env_on = true
		_env_saved = {
			"src": env.ambient_light_source, "col": env.ambient_light_color, "fog": env.fog_enabled,
			"refl": env.reflected_light_source, "sun": main.sky.sun.visible,
		}
	var p: Dictionary = _places[inside]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = p["ambient"]
	env.ambient_light_energy = float(p["energy"])
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = false
	env.tonemap_exposure = 1.0
	main.sky.sun.visible = false


func _restore_env() -> void:
	if not _env_on:
		return
	_env_on = false
	var env: Environment = main.sky.env
	env.ambient_light_source = _env_saved["src"]
	env.ambient_light_color = _env_saved["col"]
	env.fog_enabled = _env_saved["fog"]
	env.reflected_light_source = _env_saved["refl"]
	main.sky.sun.visible = _env_saved["sun"]
	if main.sky.current.has("ambient"):
		env.ambient_light_energy = float(main.sky.current["ambient"])
		env.tonemap_exposure = float(main.sky.current["exposure"])


## Pinta y Listo: repara, cambia el color, quita la búsqueda y cobra.
func _respray(car) -> void:
	busy = true
	_respray_cd = 10.0
	if GameState.money < RESPRAY_PRICE:
		main.hud.toast("Necesitas $%d" % RESPRAY_PRICE, "Pinta y Listo", 2.5)
		busy = false
		return
	GameState.add_money(-RESPRAY_PRICE)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	main.set_gameplay(false)
	main.hud.fade_to(1.0, 0.5)
	await get_tree().create_timer(0.6).timeout
	var colors: Array = CityBuilder.CAR_COLORS
	var color: Color = colors[randi() % colors.size()]
	var guard := 0
	while color.is_equal_approx(car.body_color) and guard < 8:
		color = colors[randi() % colors.size()]
		guard += 1
	car.repair()
	car.repaint(color)
	main.wanted = 0
	main.hud.set_wanted(0)
	await get_tree().create_timer(1.0).timeout
	main.hud.toast("PINTA Y LISTO", "Coche reparado y pintado", 3.0)
	main.hud.fade_to(0.0, 0.6)
	main.set_gameplay(true)
	await get_tree().create_timer(0.6).timeout
	busy = false


# ---------------------------------------------------------------- utilidades de construcción

func _mat(color: Color, rough: float = 0.8, metal: float = 0.0, emission: Color = Color.BLACK, energy: float = 1.0) -> StandardMaterial3D:
	var key := "m%s_%s_%s_%s_%s" % [color.to_html(), rough, metal, emission.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := MeshBuilder.material(color, rough, metal, emission, energy)
	m.vertex_color_use_as_albedo = false
	_mats[key] = m
	return m


## Material PBR con proyección triplanar en coordenadas de mundo (sin UV).
func _pbr(id: String, tint: Color, tile: float) -> StandardMaterial3D:
	var key := "p%s_%s_%s" % [id, tint.to_html(), tile]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	if ResourceLoader.exists(TEX + id + "/albedo.jpg"):
		m.albedo_texture = load(TEX + id + "/albedo.jpg")
		m.normal_enabled = true
		m.normal_texture = load(TEX + id + "/normal.jpg")
		m.roughness_texture = load(TEX + id + "/roughness.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / tile
	_mats[key] = m
	return m


func _mesh_box(parent: Node, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = center
	parent.add_child(mi)
	return mi


## Caja visible con colisión en el cuerpo estático de la ciudad nueva.
func _wall_box(center: Vector3, size: Vector3, mat: Material) -> void:
	_mesh_box(self, center, size, mat)
	_solid_box(center, size)


func _label(parent: Node, text: String, pos: Vector3, rot_y_deg: float, font_size: int, color: Color, pixel: float, flat: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.position = pos
	l.rotation_degrees = Vector3(-90.0 if flat else 0.0, rot_y_deg, 0.0)
	parent.add_child(l)
	return l


func _omni(parent: Node, pos: Vector3, color: Color, energy: float, rng: float, shadow: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	l.position = pos
	parent.add_child(l)
	return l


## Carga un modelo (relativo a assets/props, o ruta res://) y lo normaliza: base en
## y = 0 y centrado en XZ. `pos` es la base. Añade colisión de caja si es grande.
func _prop(parent: Node, file: String, pos: Vector3, yaw_deg: float = 0.0, scale: float = 1.0, collide: bool = true, outer: bool = false, tilt_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var path := file if file.begins_with("res://") else PROPS + file
	if not ResourceLoader.exists(path):
		push_warning("Interiors: falta %s" % path)
		return null
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var inst := (_scenes[path] as PackedScene).instantiate() as Node3D
	if not _bounds.has(path):
		_bounds[path] = _aabb_of(inst)
	var bb: AABB = _bounds[path]
	inst.scale = Vector3.ONE * scale
	inst.position = Vector3(-bb.get_center().x, -bb.position.y, -bb.get_center().z) * scale
	var holder: Node3D = StaticBody3D.new() if collide and bb.size.y * scale > 0.45 else Node3D.new()
	holder.position = pos
	holder.rotation_degrees = Vector3(tilt_deg.x, yaw_deg, tilt_deg.z)
	holder.add_child(inst)
	parent.add_child(holder)
	if holder is StaticBody3D:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(bb.size.x, bb.size.y, bb.size.z) * scale
		cs.shape = shape
		cs.position = Vector3(0, bb.size.y * scale * 0.5, 0)
		holder.add_child(cs)
	return holder


func _aabb_of(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


# ---------------------------------------------------------------- interiores

func _ensure_built(i: int) -> void:
	if _roots.has(i):
		return
	var root := Node3D.new()
	root.name = "Interior_%s" % _places[i]["id"]
	root.position = _origin(i)
	add_child(root)
	_roots[i] = root
	var p: Dictionary = _places[i]
	var size: Vector2 = p["size"]
	var h: float = p["height"]
	if p.has("model"):
		_fill_model_interior(root, p)
		root.visible = false
		return
	match String(p["id"]):
		"house":
			_shell(root, size, h, float(p["door_x"]), _pbr("stucco_beige", Color(1.0, 0.95, 0.88), 3.0), _mat(Color(0.93, 0.9, 0.85), 0.9), Color(0.62, 0.46, 0.34))
			_fill_house(root, size)
		"garage":
			_shell(root, size, h, float(p["door_x"]), _pbr("concrete_wall", Color(0.85, 0.88, 0.95), 3.0), _mat(Color(0.5, 0.52, 0.55), 0.9), Color(0.0, 0.0, 0.0, 0.0))
			_fill_garage(root, size)
		"police":
			_shell(root, size, h, float(p["door_x"]), _pbr("concrete_wall", Color(0.78, 0.82, 0.95), 3.0), _mat(Color(0.9, 0.92, 0.96), 0.9), Color(0.55, 0.58, 0.66))
			_fill_police(root, size)
		"hospital":
			_shell(root, size, h, float(p["door_x"]), _pbr("stucco", Color(0.92, 0.98, 0.98), 3.0), _mat(Color(0.95, 0.97, 0.97), 0.9), Color(0.88, 0.92, 0.98))
			_fill_hospital(root, size)
	if not p.has("model"):
		for n in root.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).visibility_range_end = VIS_END
	root.visible = false


func _rbox(root: Node3D, center: Vector3, size: Vector3, mat: Material, collide: bool = true, shadow: bool = false) -> MeshInstance3D:
	var mi := _mesh_box(root, center, size, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = center
		body.add_child(cs)
		root.add_child(body)
	return mi


## Caja de la sala: suelo (losas del kit o hormigón), cuatro paredes, techo y puerta.
## La puerta está en la pared +Z (sur); el jugador entra mirando hacia -Z.
func _shell(root: Node3D, size: Vector2, h: float, door_x: float, wall: Material, ceil_mat: Material, floor_tint: Color) -> void:
	var hw := size.x * 0.5
	var hd := size.y * 0.5
	var t := 0.3
	# Suelo: colisión + losas del kit (o hormigón PBR si no hay tinte).
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(size.x + 1.0, 0.5, size.y + 1.0)
	fcs.shape = fshape
	fcs.position = Vector3(0, -0.25, 0)
	floor_body.add_child(fcs)
	root.add_child(floor_body)
	if floor_tint.a < 0.5:
		var fm := _mesh_box(root, Vector3(0, -0.05, 0), Vector3(size.x, 0.1, size.y), _pbr("concrete", Color(0.95, 0.95, 1.0), 2.5))
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		_floor_tiles(root, size, floor_tint)
	# Paredes.
	_rbox(root, Vector3(0, h * 0.5, -hd - t * 0.5), Vector3(size.x + t * 2.0, h, t), wall)
	_rbox(root, Vector3(0, h * 0.5, hd + t * 0.5), Vector3(size.x + t * 2.0, h, t), wall)
	_rbox(root, Vector3(-hw - t * 0.5, h * 0.5, 0), Vector3(t, h, size.y), wall)
	_rbox(root, Vector3(hw + t * 0.5, h * 0.5, 0), Vector3(t, h, size.y), wall)
	_rbox(root, Vector3(0, h + t * 0.5, 0), Vector3(size.x + t * 2.0, t, size.y + t * 2.0), ceil_mat)
	# Rodapié oscuro.
	var base := _mat(Color(0.14, 0.12, 0.11), 0.7)
	_rbox(root, Vector3(0, 0.07, -hd + 0.02), Vector3(size.x, 0.14, 0.04), base, false)
	_rbox(root, Vector3(-hw + 0.02, 0.07, 0), Vector3(0.04, 0.14, size.y), base, false)
	_rbox(root, Vector3(hw - 0.02, 0.07, 0), Vector3(0.04, 0.14, size.y), base, false)
	# Puerta: hoja del kit con marco, y cartel luminoso "SALIR".
	var frame := _mat(Color(0.2, 0.13, 0.08), 0.6)
	for sx in [-1.0, 1.0]:
		_rbox(root, Vector3(door_x + sx * 0.62, 1.15, hd - 0.05), Vector3(0.14, 2.3, 0.1), frame, false)
	_rbox(root, Vector3(door_x, 2.33, hd - 0.05), Vector3(1.38, 0.14, 0.1), frame, false)
	var leaf := _prop(root, KIT + "Door_1.gltf", Vector3(door_x, 0.0, hd - 0.14), 180.0, 1.0, false)
	if leaf == null:
		_rbox(root, Vector3(door_x, 1.1, hd - 0.1), Vector3(1.0, 2.2, 0.1), frame, false)
	var sign_l := _label(root, "SALIR", Vector3(door_x, 2.62, hd - 0.08), 180.0, 56, Color(0.3, 1.0, 0.45), 0.005)
	sign_l.outline_size = 4


func _floor_tiles(root: Node3D, size: Vector2, tint: Color) -> void:
	if not _scenes.has(KIT + "Floor_4x4.gltf"):
		_scenes[KIT + "Floor_4x4.gltf"] = load(KIT + "Floor_4x4.gltf")
		_scenes[KIT + "Floor_2x2.gltf"] = load(KIT + "Floor_2x2.gltf")
	var nx := int(round(size.x / 2.0))
	var nz := int(round(size.y / 2.0))
	var x0 := -size.x * 0.5
	var z0 := -size.y * 0.5
	var used := {}
	for j in range(0, nz - 1, 2):
		for i in range(0, nx - 1, 2):
			used[Vector2i(i, j)] = 4
			used[Vector2i(i + 1, j)] = 0
			used[Vector2i(i, j + 1)] = 0
			used[Vector2i(i + 1, j + 1)] = 0
	for j in nz:
		for i in nx:
			var cell := Vector2i(i, j)
			var kind: int = int(used.get(cell, 2))
			if kind == 0:
				continue
			var path := KIT + ("Floor_4x4.gltf" if kind == 4 else "Floor_2x2.gltf")
			var tile := (_scenes[path] as PackedScene).instantiate() as Node3D
			var s := 4.0 if kind == 4 else 2.0
			tile.position = Vector3(x0 + i * 2.0 + s * 0.5, 0.0, z0 + j * 2.0 + s * 0.5)
			root.add_child(tile)
			for m in tile.find_children("*", "MeshInstance3D", true, false):
				var mi := m as MeshInstance3D
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.mesh = mi.mesh.duplicate()
				for sidx in mi.mesh.get_surface_count():
					var src := mi.mesh.surface_get_material(sidx)
					if src is BaseMaterial3D:
						var fm := src.duplicate() as BaseMaterial3D
						fm.vertex_color_use_as_albedo = false
						fm.albedo_color = tint
						mi.mesh.surface_set_material(sidx, fm)


func _ceiling_panel(root: Node3D, pos: Vector3, size: Vector3, color: Color = Color(1, 0.97, 0.9)) -> void:
	var mi := _mesh_box(root, pos, size, _mat(color, 0.3, 0.0, color, 1.3))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---- Casa de Mack ----

func _fill_house(root: Node3D, size: Vector2) -> void:
	var h := 2.9
	var hd := size.y * 0.5
	var wood := _mat(Color(0.36, 0.24, 0.15), 0.7)
	# Alfombra del salón y ventanas falsas de luz.
	_rbox(root, Vector3(-3.2, 0.012, -1.8), Vector3(3.6, 0.024, 2.6), _mat(Color(0.5, 0.18, 0.15), 0.95), false)
	_rbox(root, Vector3(-3.2, 0.026, -1.8), Vector3(3.2, 0.012, 2.2), _mat(Color(0.62, 0.3, 0.22), 0.95), false)
	for wx in [-3.6, 3.4]:
		_rbox(root, Vector3(wx, 1.6, -hd + 0.03), Vector3(1.6, 1.2, 0.05), _mat(Color(0.8, 0.9, 1.0), 0.3, 0.0, Color(0.75, 0.88, 1.0), 1.1), false)
		_rbox(root, Vector3(wx, 1.6, -hd + 0.06), Vector3(1.7, 0.06, 0.06), wood, false)
		_rbox(root, Vector3(wx, 1.6, -hd + 0.06), Vector3(0.06, 1.3, 0.06), wood, false)
	# Salón.
	_prop(root, "modern_wooden_cabinet/modern_wooden_cabinet_1k.gltf", Vector3(-3.2, 0, -hd + 0.3), 0.0)
	_prop(root, "television_01/Television_01_1k.gltf", Vector3(-3.2, 0.68, -hd + 0.3), 0.0, 1.35, false)
	_prop(root, "sofa_01/Sofa_01_1k.gltf", Vector3(-3.2, 0, 0.1), 180.0)
	_prop(root, "coffeetable_01/CoffeeTable_01_1k.gltf", Vector3(-3.2, 0, -1.7), 0.0, 0.9)
	_prop(root, "armchair_01/ArmChair_01_1k.gltf", Vector3(-5.1, 0, -1.6), 90.0)
	_prop(root, "shelf_01/Shelf_01_1k.gltf", Vector3(-5.82, 0, 1.4), 90.0)
	_prop(root, "side_table_01/side_table_01_1k.gltf", Vector3(-1.6, 0, 0.1), 0.0)
	_prop(root, "desk_lamp_arm_01/desk_lamp_arm_01_1k.gltf", Vector3(-1.6, 0.55, 0.1), 200.0, 0.9, false)
	# Cocina y comedor.
	_prop(root, "modern_wooden_cabinet/modern_wooden_cabinet_1k.gltf", Vector3(4.55, 0, -hd + 0.3), 0.0)
	_prop(root, "drawer_cabinet/drawer_cabinet_1k.gltf", Vector3(2.35, 0, -hd + 0.28), 0.0)
	_prop(root, "dining_table/dining_table_1k.gltf", Vector3(3.2, 0, -2.4), 0.0)
	_prop(root, "dining_chair_02/dining_chair_02_1k.gltf", Vector3(2.6, 0, -1.3), 180.0)
	_prop(root, "dining_chair_02/dining_chair_02_1k.gltf", Vector3(3.9, 0, -3.5), 0.0)
	# Dormitorio (esquina sureste) con tabique y puerta.
	var wall_m := _pbr("stucco_beige", Color(0.95, 0.92, 0.85), 3.0)
	_rbox(root, Vector3(3.9, h * 0.5, 0.9), Vector3(4.2, h, 0.15), wall_m)
	_rbox(root, Vector3(1.8, h * 0.5, 3.6), Vector3(0.15, h, 2.8), wall_m)
	_prop(root, "old_bed_frame/old_bed_frame_1k.gltf", Vector3(4.85, 0, 3.2), 90.0)
	_rbox(root, Vector3(4.85, 0.38, 3.2), Vector3(1.9, 0.18, 0.84), _mat(Color(0.82, 0.8, 0.74), 0.95), false)
	_rbox(root, Vector3(4.85, 0.5, 3.2), Vector3(1.9, 0.1, 0.8), _mat(Color(0.25, 0.32, 0.45), 0.9), false)
	_rbox(root, Vector3(5.5, 0.62, 3.2), Vector3(0.5, 0.14, 0.7), _mat(Color(0.92, 0.92, 0.9), 0.95), false)
	_prop(root, "classicnightstand_01/ClassicNightstand_01_1k.gltf", Vector3(5.65, 0, 2.2), 270.0)
	_prop(root, "drawer_cabinet/drawer_cabinet_1k.gltf", Vector3(3.0, 0, hd - 0.28), 180.0)
	# Luces cálidas (solo una con sombra).
	_omni(root, Vector3(-2.6, 2.5, 0.0), Color(1.0, 0.8, 0.55), 1.5, 9.0, true)
	_omni(root, Vector3(3.2, 2.5, -2.4), Color(1.0, 0.85, 0.62), 1.3, 7.0)
	_omni(root, Vector3(4.0, 2.4, 3.0), Color(1.0, 0.75, 0.5), 1.0, 5.5)
	_ceiling_panel(root, Vector3(-2.6, h - 0.04, 0.0), Vector3(1.4, 0.06, 1.0), Color(1.0, 0.85, 0.65))
	_ceiling_panel(root, Vector3(3.2, h - 0.04, -2.4), Vector3(1.2, 0.06, 0.8), Color(1.0, 0.88, 0.7))


# ---- Vargas Auto Works ----

func _fill_garage(root: Node3D, size: Vector2) -> void:
	var h := 6.0
	var hd := size.y * 0.5
	var dark := _mat(Color(0.08, 0.08, 0.1), 0.6, 0.4)
	var yellow := _mat(Color(0.95, 0.75, 0.1), 0.6)
	var steel := _mat(Color(0.35, 0.37, 0.4), 0.45, 0.7)
	# Vigas y tubos fluorescentes.
	for bx in [-6.0, 0.0, 6.0]:
		_rbox(root, Vector3(bx, h - 0.25, 0), Vector3(0.35, 0.5, size.y), dark, false)
	for lx in [-6.0, 0.0, 6.0]:
		for lz in [-3.5, 3.5]:
			_ceiling_panel(root, Vector3(lx + 1.5, h - 0.55, lz), Vector3(0.2, 0.08, 3.0), Color(1, 0.98, 0.92))
	# Portón enrollable en la pared norte.
	for k in 10:
		_rbox(root, Vector3(1.0, 0.45 + k * 0.42, -hd + 0.06), Vector3(5.6, 0.36, 0.1), _mat(Color(0.5, 0.52, 0.55), 0.5, 0.5), false)
	_rbox(root, Vector3(-1.9, 2.2, -hd + 0.07), Vector3(0.2, 4.4, 0.12), yellow, false)
	_rbox(root, Vector3(3.9, 2.2, -hd + 0.07), Vector3(0.2, 4.4, 0.12), yellow, false)
	# Elevador: marco amarillo en el suelo, dos columnas, raíles y un coche subido.
	for sx in [-1.0, 1.0]:
		_rbox(root, Vector3(3.0 + sx * 3.2, 0.012, -0.5), Vector3(0.14, 0.024, 4.6), yellow, false)
	for sz in [-1.0, 1.0]:
		_rbox(root, Vector3(3.0, 0.012, -0.5 + sz * 2.3), Vector3(6.5, 0.024, 0.14), yellow, false)
	for sx in [-1.0, 1.0]:
		_rbox(root, Vector3(3.0 + sx * 3.0, 1.9, -2.2), Vector3(0.3, 3.8, 0.3), steel)
		_rbox(root, Vector3(3.0 + sx * 3.0, 1.9, 1.2), Vector3(0.3, 3.8, 0.3), steel)
	for rz in [-1.4, 0.4]:
		_rbox(root, Vector3(3.0, 1.0, rz), Vector3(5.8, 0.14, 0.4), yellow, false)
	var car := MeshInstance3D.new()
	car.mesh = CarModel.build(1, Color(0.7, 0.08, 0.08), true)
	car.position = Vector3(3.0, 1.1, -0.5)
	car.rotation.y = PI * 0.5
	root.add_child(car)
	var cbody := StaticBody3D.new()
	var ccs := CollisionShape3D.new()
	var cshape := BoxShape3D.new()
	cshape.size = Vector3(4.8, 1.4, 2.0)
	ccs.shape = cshape
	ccs.position = Vector3(3.0, 1.0 + 0.7, -0.5)
	cbody.add_child(ccs)
	root.add_child(cbody)
	# Banco de trabajo con tornillo de banco y cajas de herramientas (pared norte, oeste).
	_rbox(root, Vector3(-6.0, 0.45, -hd + 0.5), Vector3(5.0, 0.9, 0.8), _mat(Color(0.3, 0.2, 0.12), 0.7))
	_rbox(root, Vector3(-6.0, 0.92, -hd + 0.5), Vector3(5.1, 0.06, 0.9), steel, false)
	_prop(root, "bench_vice_01/bench_vice_01_1k.gltf", Vector3(-4.3, 0.95, -hd + 0.55), 0.0, 1.8, false)
	_prop(root, "metal_tool_chest/metal_tool_chest_1k.gltf", Vector3(-8.1, 0, -hd + 0.5), 0.0, 1.3)
	_prop(root, "metal_tool_chest/metal_tool_chest_1k.gltf", Vector3(-9.1, 0, -hd + 0.5), 0.0, 1.3)
	_prop(root, "metal_tool_chest/metal_tool_chest_1k.gltf", Vector3(-6.4, 0.95, -hd + 0.5), 0.0, 1.1, false)
	_prop(root, "tool_cart/tool_cart_1k.gltf", Vector3(-1.4, 0, -4.4), 0.0)
	# Estantes en la pared oeste, con cajas.
	_prop(root, "steel_frame_shelves_03/steel_frame_shelves_03_1k.gltf", Vector3(-9.5, 0, -1.2), 90.0)
	_prop(root, "steel_frame_shelves_03/steel_frame_shelves_03_1k.gltf", Vector3(-9.5, 0, 1.4), 90.0)
	_prop(root, "cardboard_box_01/cardboard_box_01_1k.gltf", Vector3(-9.45, 1.18, -1.2), 90.0, 1.1, false)
	_prop(root, "cardboard_box_01/cardboard_box_01_1k.gltf", Vector3(-9.45, 0.05, 1.4), 80.0, 1.1, false)
	_prop(root, "cardboard_box_01/cardboard_box_01_1k.gltf", Vector3(-8.2, 0.0, 0.2), 30.0, 1.3)
	# Pared este: barriles, neumáticos, escalera y cuadro eléctrico.
	for b in [Vector2(9.3, -6.0), Vector2(8.6, -5.7), Vector2(9.4, -5.1)]:
		_prop(root, "barrel_02/Barrel_02_1k.gltf", Vector3(b.x, 0, b.y), randf() * 360.0)
	for stack in [Vector2(8.6, 2.0), Vector2(8.6, 3.3), Vector2(7.5, 5.3)]:
		for k in 5:
			_prop(root, "old_tyre/old_tyre_1k.gltf", Vector3(stack.x, 0.165 * k, stack.y), 12.0 * k, 1.1, k == 0, false, Vector3(90, 0, 0))
	_prop(root, "ladder_sectioned_01/ladder_sectioned_01_1k.gltf", Vector3(9.75, 0, -2.2), -90.0, 1.0, false, false, Vector3(0, 0, 8))
	_prop(root, "power_box_01/power_box_01_1k.gltf", Vector3(9.8, 1.5, 0.2), -90.0, 1.6, false)
	_prop(root, "tire_pump/tire_pump_1k.gltf", Vector3(6.6, 0, -2.4), 40.0, 1.3, false)
	_prop(root, "industrial_storage_cart/industrial_storage_cart_1k.gltf", Vector3(6.6, 0, -5.8), 0.0)
	_prop(root, "spray_paint_bottles/spray_paint_bottles_1k.gltf", Vector3(-7.4, 0.95, -hd + 0.45), 20.0, 1.8, false)
	# Luces: tres puntos fríos-cálidos, uno con sombra.
	_omni(root, Vector3(-5.0, 5.0, 0.0), Color(1.0, 0.95, 0.86), 2.2, 15.0, true)
	_omni(root, Vector3(4.5, 5.0, -1.5), Color(1.0, 0.96, 0.9), 2.2, 15.0)
	_omni(root, Vector3(2.0, 5.0, 4.5), Color(1.0, 0.92, 0.82), 1.8, 14.0)
	_label(root, "VARGAS AUTO WORKS", Vector3(-5.5, 3.6, -hd + 0.06), 0.0, 100, Color(1, 0.55, 0.25), 0.0075)


# ---- Comisaría ----

func _fill_police(root: Node3D, size: Vector2) -> void:
	var h := 3.2
	var hd := size.y * 0.5
	var hw := size.x * 0.5
	var blue := _mat(Color(0.06, 0.12, 0.3), 0.5, 0.2)
	var bar_m := _mat(Color(0.12, 0.13, 0.15), 0.4, 0.8)
	_label(root, "SOUTH VEYRA PD", Vector3(-1.0, 2.2, -hd + 0.06), 0.0, 120, Color(0.85, 0.92, 1.0), 0.0095)
	_rbox(root, Vector3(-1.0, 1.55, -hd + 0.04), Vector3(7.4, 0.08, 0.04), _glow(Color(0.9, 0.7, 0.15)), false)
	# Mostrador (dos mesas de oficina), lámpara y sillas del personal.
	_prop(root, "metal_office_desk/metal_office_desk_1k.gltf", Vector3(-3.0, 0, -0.8), 0.0)
	_prop(root, "metal_office_desk/metal_office_desk_1k.gltf", Vector3(-1.0, 0, -0.8), 0.0)
	_prop(root, "desk_lamp_arm_01/desk_lamp_arm_01_1k.gltf", Vector3(-3.4, 0.79, -1.0), 160.0, 1.0, false)
	_prop(root, "modern_arm_chair_01/modern_arm_chair_01_1k.gltf", Vector3(-3.0, 0, -2.2), 180.0, 0.9)
	_prop(root, "shelf_01/Shelf_01_1k.gltf", Vector3(-4.2, 0, -hd + 0.2), 0.0)
	_prop(root, "shelf_01/Shelf_01_1k.gltf", Vector3(-6.2, 0, -hd + 0.2), 0.0)
	_prop(root, "drawer_cabinet/drawer_cabinet_1k.gltf", Vector3(-7.0, 0, -2.4), 90.0)
	_prop(root, "security_camera_01/security_camera_01_1k.gltf", Vector3(-hw + 0.5, h - 0.45, hd - 0.5), 135.0, 1.4, false)
	# Sala de espera.
	for k in 4:
		_prop(root, "plastic_monobloc_chair_01/plastic_monobloc_chair_01_1k.gltf", Vector3(-6.3 + k * 0.8, 0, hd - 0.6), 180.0, 1.0, k == 0)
	_prop(root, "side_table_01/side_table_01_1k.gltf", Vector3(-2.2, 0, hd - 0.5), 0.0)
	_prop(root, "wetfloorsign_01/WetFloorSign_01_1k.gltf", Vector3(-3.0, 0, 2.2), 30.0, 1.0, false)
	# Celda de detención (esquina noreste) con barrotes finos y un banco.
	var cx0 := 3.0
	var cz1 := -1.4
	var cell_w := hw - cx0
	var cell_d := cz1 + hd
	for sidx in 2:
		var along_x := sidx == 0
		var length := cell_w if along_x else cell_d
		var count := int(length / 0.22)
		for k in count + 1:
			var off := float(k) * length / float(count)
			var px: float = cx0 + off if along_x else cx0
			var pz: float = cz1 if along_x else -hd + off
			var bar := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.022
			cyl.bottom_radius = 0.022
			cyl.height = h - 0.1
			cyl.radial_segments = 6
			cyl.rings = 1
			cyl.material = bar_m
			bar.mesh = cyl
			bar.position = Vector3(px, (h - 0.1) * 0.5, pz)
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(bar)
	for ry in [0.15, 1.1, h - 0.15]:
		_rbox(root, Vector3(cx0 + cell_w * 0.5, ry, cz1), Vector3(cell_w, 0.06, 0.06), bar_m, false)
		_rbox(root, Vector3(cx0, ry, -hd + cell_d * 0.5), Vector3(0.06, 0.06, cell_d), bar_m, false)
	_rbox(root, Vector3(cx0 + cell_w * 0.5, 1.5, cz1), Vector3(cell_w, 3.0, 0.1), bar_m, true).visible = false
	_rbox(root, Vector3(cx0, 1.5, -hd + cell_d * 0.5), Vector3(0.1, 3.0, cell_d), bar_m, true).visible = false
	_rbox(root, Vector3(hw - 1.3, 0.25, -hd + 0.5), Vector3(2.4, 0.5, 0.5), _mat(Color(0.35, 0.36, 0.38), 0.6, 0.4))
	_rbox(root, Vector3(hw - 0.5, 0.2, -hd + 2.0), Vector3(0.9, 0.4, 1.4), _mat(Color(0.25, 0.26, 0.3), 0.8))
	_label(root, "CELDA 1", Vector3(cx0 + 0.02, 2.55, -hd + cell_d * 0.5), 90.0, 40, Color(1, 0.4, 0.3), 0.005)
	# Agentes de servicio (modelo real de policía con esqueleto).
	for c in [["cop_reyes", Vector3(-1.0, 0.05, -3.3), 180.0], ["cop_park", Vector3(-5.2, 0.05, 0.6), 90.0]]:
		var npc := NPC.new()
		root.add_child(npc)
		npc.setup(String(c[0]), "")
		npc.position = c[1]
		npc.face(root.position + (c[1] as Vector3) + Vector3(sin(deg_to_rad(float(c[2]))), 0, cos(deg_to_rad(float(c[2])))) * 3.0)
		_model_npcs.append(npc)
	# Luces: paneles fluorescentes azulados.
	for lx in [-4.5, 0.0, 4.5]:
		_ceiling_panel(root, Vector3(lx, h - 0.04, 0.5), Vector3(2.4, 0.06, 0.5), Color(0.92, 0.96, 1.0))
	_omni(root, Vector3(-3.0, 2.7, 0.3), Color(0.9, 0.95, 1.0), 1.3, 10.0, true)
	_omni(root, Vector3(3.5, 2.7, 1.5), Color(0.9, 0.94, 1.0), 1.0, 9.0)
	_omni(root, Vector3(5.5, 2.7, -3.2), Color(0.85, 0.9, 1.0), 1.0, 5.5)
	_rbox(root, Vector3(5.5, h - 0.04, -3.2), Vector3(0.6, 0.06, 0.6), blue, false)


func _glow(c: Color) -> StandardMaterial3D:
	return _mat(c, 0.5, 0.0, c, 0.6)


# ---- Hospital ----

func _fill_hospital(root: Node3D, size: Vector2) -> void:
	var h := 3.4
	var hd := size.y * 0.5
	var hw := size.x * 0.5
	var red := _mat(Color(0.85, 0.05, 0.08), 0.4, 0.0, Color(1.0, 0.05, 0.08), 0.35)
	var curtain := _mat(Color(0.62, 0.85, 0.9), 0.9)
	# Cruz roja y nombre en la pared norte.
	_rbox(root, Vector3(1.0, 2.3, -hd + 0.04), Vector3(1.1, 0.34, 0.05), red, false)
	_rbox(root, Vector3(1.0, 2.3, -hd + 0.04), Vector3(0.34, 1.1, 0.05), red, false)
	_label(root, "WESTBROOK GENERAL", Vector3(1.0, 1.55, -hd + 0.05), 0.0, 90, Color(0.2, 0.3, 0.35), 0.008)
	# Tres camas con cortinas, mesitas y muletas.
	for k in 3:
		var bx := -5.5 + k * 3.4
		_prop(root, "vintage_day_bed/vintage_day_bed_1k.gltf", Vector3(bx, 0, -hd + 1.0), 0.0)
		_prop(root, "side_table_tall_01/side_table_tall_01_1k.gltf", Vector3(bx + 1.35, 0, -hd + 0.3), 0.0)
		_rbox(root, Vector3(bx + 1.7, 1.7, -hd + 1.9), Vector3(0.04, 2.2, 1.7), curtain, false)
	_prop(root, "vintage_crutches_01/vintage_crutches_01_1k.gltf", Vector3(-hw + 0.3, 0, -1.0), 90.0, 1.0, false, false, Vector3(0, 0, 6))
	_prop(root, "vintage_crutches_01/vintage_crutches_01_1k.gltf", Vector3(-hw + 0.45, 0, -0.7), 90.0, 1.0, false, false, Vector3(0, 0, 6))
	# Recepción y sala de espera.
	_prop(root, "metal_office_desk/metal_office_desk_1k.gltf", Vector3(4.5, 0, -0.2), 0.0)
	_prop(root, "metal_office_desk/metal_office_desk_1k.gltf", Vector3(6.5, 0, -0.2), 0.0)
	_prop(root, "desk_lamp_arm_01/desk_lamp_arm_01_1k.gltf", Vector3(4.0, 0.79, -0.4), 180.0, 1.0, false)
	_prop(root, "modern_arm_chair_01/modern_arm_chair_01_1k.gltf", Vector3(5.0, 0, -1.4), 180.0, 0.9)
	for k in 5:
		_prop(root, "plastic_monobloc_chair_01/plastic_monobloc_chair_01_1k.gltf", Vector3(-1.2 + k * 0.8, 0, hd - 0.6), 180.0, 1.0, k == 0)
	_prop(root, "plastic_monobloc_chair_01/plastic_monobloc_chair_01_1k.gltf", Vector3(hw - 0.6, 0, 3.2), 270.0)
	_prop(root, "plastic_monobloc_chair_01/plastic_monobloc_chair_01_1k.gltf", Vector3(hw - 0.6, 0, 4.0), 270.0)
	_prop(root, "wetfloorsign_01/WetFloorSign_01_1k.gltf", Vector3(-2.0, 0, 2.4), -25.0, 1.1, false)
	_prop(root, "shelf_01/Shelf_01_1k.gltf", Vector3(hw - 0.2, 0, -3.0), 270.0)
	_prop(root, "security_camera_01/security_camera_01_1k.gltf", Vector3(hw - 0.5, h - 0.45, hd - 0.5), -135.0, 1.4, false)
	# Franja verde de guía en el suelo y luces fluorescentes.
	_rbox(root, Vector3(-4.0, 0.012, 2.5), Vector3(0.18, 0.024, 4.0), _mat(Color(0.2, 0.7, 0.4), 0.6), false)
	for lx in [-5.0, 0.0, 5.0]:
		for lz in [-3.0, 2.0]:
			_ceiling_panel(root, Vector3(lx, h - 0.04, lz), Vector3(2.0, 0.06, 0.5), Color(0.92, 1.0, 0.98))
	var doc := NPC.new()
	root.add_child(doc)
	doc.setup("doctor_pinch", "")
	doc.position = Vector3(-2.2, 0.05, 1.2)
	doc.face(root.position + Vector3(-2.2, 0, 6.0))
	_model_npcs.append(doc)
	_omni(root, Vector3(-3.5, 2.8, -1.5), Color(0.92, 1.0, 0.98), 1.2, 10.0, true)
	_omni(root, Vector3(3.5, 2.8, 1.5), Color(0.92, 1.0, 0.98), 1.0, 10.0)
	_omni(root, Vector3(-3.0, 2.8, 4.0), Color(0.9, 1.0, 0.98), 1.0, 7.0)


# ---------------------------------------------------------------- interiores con modelo 3D

func _model_mesh(path: String) -> Mesh:
	var inst := (load(path) as PackedScene).instantiate()
	var mi := inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var m := mi.mesh
	inst.free()
	return m


## Altura del suelo (triángulo horizontal más alto por debajo de ymax) en el punto (x, z).
func _floor_y(mesh: Mesh, x: float, z: float, ymax: float) -> float:
	var best := -1000.0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var p0 := v[idx[t]]
			var p1 := v[idx[t + 1]]
			var p2 := v[idx[t + 2]]
			var top := maxf(p0.y, maxf(p1.y, p2.y))
			if top > ymax or top <= best:
				continue
			if absf(p0.y - p1.y) > 0.05 or absf(p0.y - p2.y) > 0.05:
				continue
			var d := (p1.z - p2.z) * (p0.x - p2.x) + (p2.x - p1.x) * (p0.z - p2.z)
			if absf(d) < 0.0001:
				continue
			var l1 := ((p1.z - p2.z) * (x - p2.x) + (p2.x - p1.x) * (z - p2.z)) / d
			var l2 := ((p2.z - p0.z) * (x - p2.x) + (p0.x - p2.x) * (z - p2.z)) / d
			if l1 >= 0.0 and l2 >= 0.0 and l1 + l2 <= 1.0:
				best = top
	return best


func _fill_model_interior(root: Node3D, p: Dictionary) -> void:
	var mesh := _model_mesh(String(p["model"]))
	var anc: Vector2 = p["anchor"]
	var fy := _floor_y(mesh, anc.x, anc.y, float(p["floor_ymax"]))
	if p.has("floor_y"):
		fy = float(p["floor_y"])
	if fy < -500.0:
		fy = 0.0
	if p.get("double_sided", false):
		# Parte del suelo del modelo tiene las normales invertidas: se dibuja por ambas caras.
		for si in mesh.get_surface_count():
			var sm := mesh.surface_get_material(si)
			if sm is BaseMaterial3D:
				(sm as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	var holder := Node3D.new()
	holder.name = "Model"
	holder.position = Vector3(-anc.x, -fy, -anc.y)
	root.add_child(holder)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	var faces := PackedVector3Array()
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for t in idx:
			faces.append(v[t])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	holder.add_child(body)
	for n in p.get("npcs", []):
		var rel: Vector2 = n[1]
		var gy := _floor_y(mesh, anc.x + rel.x, anc.y + rel.y, fy + 0.8)
		var npc := NPC.new()
		root.add_child(npc)
		npc.setup(String(n[0]), "")
		npc.position = Vector3(rel.x, (gy - fy if gy > -500.0 else 0.0) + 0.05, rel.y)
		npc.face(root.position + Vector3(0, 0, 40.0))
		_model_npcs.append(npc)


func _set_follow_light(on: bool) -> void:
	if on and (_follow_light == null or not is_instance_valid(_follow_light)):
		_follow_light = OmniLight3D.new()
		_follow_light.light_color = Color(0.95, 0.97, 1.0)
		_follow_light.light_energy = 1.1
		_follow_light.omni_range = 16.0
		_follow_light.shadow_enabled = false
		_follow_light.position = Vector3(0, 2.4, 0)
		main.player.add_child(_follow_light)
	elif not on and _follow_light != null and is_instance_valid(_follow_light):
		_follow_light.queue_free()
		_follow_light = null
