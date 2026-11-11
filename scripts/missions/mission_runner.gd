class_name MissionRunner
extends Node
## Ejecuta misiones definidas en data/missions/*.json paso a paso.
## Cada paso es un tipo (cutscene, dialogue, talk, pickup, goto, enter_vehicle,
## scripted_drive, drive_to, exit_vehicle, checkpoint, reward, complete...).
## El mundo (main.gd) aporta jugador, cámara, HUD, vehículos y actores.

signal mission_finished(mission_id: String)
signal step_started(index: int, step: Dictionary)

var world: Node
var mission: Dictionary = {}
var mission_id: String = ""
var step_index: int = 0
var phase: int = 0
var running: bool = false
var _skip: bool = false


func _input(event: InputEvent) -> void:
	if not running:
		return
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ENTER):
		_skip = true


func start(id: String, from_step: int = 0) -> void:
	var m := GameData.load_mission(id)
	if m.is_empty():
		push_error("Misión no encontrada: %s" % id)
		return
	await start_data(m, id, from_step)


## Ejecuta una misión ya cargada (también la usan las pruebas).
func start_data(m: Dictionary, id: String, from_step: int = 0) -> void:
	mission = m
	mission_id = id
	step_index = from_step
	running = true
	# Solo la misión 01 (tutorial guiado) bloquea los coches libres.
	world.allow_free_vehicles = id != "m01"
	GameState.active_mission = id
	var steps: Array = mission["steps"]
	while running and step_index < steps.size():
		var step: Dictionary = steps[step_index]
		step_started.emit(step_index, step)
		await _run_step(step)
		step_index += 1
	running = false
	world.allow_free_vehicles = true
	world.hostiles.clear("mission")
	world.clear_extras()
	_clear_pickups()
	mission_finished.emit(id)


func stop() -> void:
	running = false


func _run_step(s: Dictionary) -> void:
	var hud: HUD = world.hud
	match String(s["type"]):
		"phase":
			phase = int(s["n"])
		"checkpoint":
			GameState.mission_step = step_index + 1
			world.capture_state()
			SaveSystem.autosave()
			hud.show_location("Punto de control guardado")
		"cutscene":
			await _cutscene(s)
		"dialogue":
			await _dialogue(s)
		"pickup":
			await _interact_at(world.resolve_point(s["target"]), String(s.get("label", "Coger")), s)
			world.despawn_prop(String(s["target"]))
		"talk":
			var actor: Node3D = world.actor(String(s["actor"]))
			await _interact_at(actor.global_position, String(s.get("label", "Hablar")), s, actor)
		"goto":
			await _goto(world.mission_point(s["target"], true), float(s.get("radius", 3.5)), s, false, false)
		"drive_to":
			await _goto(world.mission_point(s["target"], false), float(s.get("radius", 9.0)), s, true, bool(s.get("stop", false)))
		"enter_vehicle":
			await _enter_vehicle(s)
		"exit_vehicle":
			if world.current_vehicle != null:
				await world.leave_vehicle()
		"scripted_drive":
			await _scripted_drive(s)
		"move_actor_to_vehicle":
			world.seat_actor(world.actor(String(s["actor"])), world.vehicle(String(s["vehicle"])), String(s.get("seat", "passenger")))
		"move_actor_from_vehicle":
			world.unseat_actor(world.actor(String(s["actor"])), _vec(s["to"]))
		"prop":
			world.spawn_prop(String(s["id"]))
		"toast":
			hud.toast(String(s.get("title", "")), String(s.get("subtitle", "")), float(s.get("duration", 2.5)))
			await _wait(1.0)
		"reward":
			GameState.add_money(int(s.get("money", 0)))
			var rep: Dictionary = s.get("reputation", {})
			for f in rep:
				GameState.change_reputation(String(f), int(rep[f]))
			hud.toast("MISIÓN SUPERADA", String(s.get("toast", "")), 4.0)
			await _wait(3.0)
		"complete":
			GameState.complete_mission(int(mission.get("number", 0)))
			GameState.active_mission = ""
			GameState.mission_step = 0
			world.capture_state()
			SaveSystem.autosave()
			hud.set_objective(String(s.get("next_objective", "")))
			hud.set_hint("")
			world.set_marker(Vector3.INF)
		"wait":
			await _wait(float(s.get("t", 1.0)))
		"scene":
			await _scene(s)
		"call":
			_objective(s)
			await _play_lines(s.get("lines", []))
		"time":
			GameState.world_minutes = float(s.get("hour", 12.0)) * 60.0
		"give":
			GameState.ammo = mini(GameState.ammo + int(s.get("ammo", 0)), GameState.MAX_AMMO)
			GameState.add_money(int(s.get("money", 0)))
			if s.has("toast"):
				hud.toast(String(s["toast"]), String(s.get("subtitle", "")), 2.5)
		"fight":
			await _fight(s, false)
		"defend":
			await _fight(s, true)
		"sneak":
			await _sneak(s)
		"chase":
			await _chase(s)
		"collect":
			await _collect(s)
		"steal":
			await _steal(s)
		"lose_cops":
			await _lose_cops(s)
		"timed_drive":
			await _timed_drive(s)
		_:
			push_warning("Tipo de paso desconocido: %s" % s["type"])


# ------------------------------------------------------------ pasos genéricos (misiones 02-80)

const FACTION_TINT := {"redline_kings": 2, "midnight_locos": 1, "the_syndicate": 4, "westbrook_saints": 5, "guards": 4, "": 6}
var _pickups: Array = []


## Escena de diálogo al estilo de las cinemáticas de barrio: el reparto se coloca en corro en
## `at`, la cámara corta al que habla en cada frase y el que habla gesticula.
func _scene(s: Dictionary) -> void:
	var hud: HUD = world.hud
	world.set_gameplay(false)
	hud.fade_to(1.0, 0.35)
	await _wait(0.45)
	if world.current_vehicle != null:
		await world.leave_vehicle()
	if s.has("hour"):
		GameState.world_minutes = float(s["hour"]) * 60.0
	var at: Vector3 = world.mission_point(s.get("at", "player"), true)
	world.stage_cast(s.get("cast", []), at)
	hud.set_objective("")
	hud.set_hint("")
	hud.set_letterbox(true)
	if bool(s.get("title_card", false)):
		hud.title_card(String(mission.get("title", "")), String(mission.get("title_es", "")), 3.5)
	# Plano general de situación.
	var wide: Vector3 = at + Vector3(4.6, 2.3, 5.2)
	if world.is_blocked(at + Vector3.UP * 1.5, wide):
		wide = at + Vector3(-4.6, 2.3, -5.2)
	world.rig.cinematic_shot(CameraRig.look_from(wide, at + Vector3.UP * 1.3), CameraRig.look_from(wide.lerp(at, 0.12), at + Vector3.UP * 1.3), 4.0, 50.0, 46.0)
	hud.fade_to(0.0, 0.5)
	await _wait(1.6 if not bool(s.get("title_card", false)) else 3.2)
	var alt := 1.0
	for line in s.get("lines", []):
		_skip = false
		var node: Node3D = world.speaker_node(String(line.get("speaker", "")))
		if node != null:
			var p: Vector3 = node.global_position
			var to_c := Vector3(at.x - p.x, 0, at.z - p.z)
			var fwd := to_c.normalized() if to_c.length() > 0.2 else Vector3(0, 0, 1)
			var sidev := Vector3(-fwd.z, 0, fwd.x)
			var cam := p + fwd * 2.3 + sidev * 0.95 * alt + Vector3.UP * 1.6
			if world.is_blocked(p + Vector3.UP * 1.5, cam):
				cam = p + fwd * 2.3 - sidev * 0.95 * alt + Vector3.UP * 1.6
			var cam2 := cam - fwd * 0.25
			world.rig.cinematic_shot(CameraRig.look_from(cam, p + Vector3.UP * 1.52), CameraRig.look_from(cam2, p + Vector3.UP * 1.52), 6.0, 38.0, 36.0)
			alt = -alt
		world.set_speaking(node, true)
		var t := _say(line)
		var elapsed := 0.0
		while elapsed < t and not _skip:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
		world.set_speaking(node, false)
	hud.show_subtitle("", "", 0.01)
	world.rig.end_cinematic()
	hud.set_letterbox(false)
	world.set_gameplay(true)


func _spawn_group(s: Dictionary, at: Vector3, count: int, alert: bool, runner: bool) -> void:
	var faction := String(s.get("faction", "redline_kings"))
	var tint: int = int(FACTION_TINT.get(faction, 4))
	var armed := bool(s.get("armed", true))
	for i in count:
		# A lo largo de la acera (eje X o Z), no en diagonal: así no acaban dentro de un edificio.
		var along: float = world.hostiles.rng.randf_range(4.0, 15.0) * (1.0 if world.hostiles.rng.randf() < 0.5 else -1.0)
		var off: Vector3 = Vector3(along, 0, world.hostiles.rng.randf_range(-0.8, 0.8)) if i % 2 == 0 else Vector3(world.hostiles.rng.randf_range(-0.8, 0.8), 0, along)
		var pos: Vector3 = at + off
		pos.y = world.ground_height(pos)
		world.hostiles.spawn(pos, "mission", armed and (i % 3 != 2 or bool(s.get("all_armed", false))), alert, runner, tint, float(s.get("health", 60.0)))


## Pelea: aparecen enemigos en `at` (por oleadas si `waves` > 1) y hay que acabar con todos.
## Con defend = true, además hay que aguantar `time` segundos cerca del punto.
func _fight(s: Dictionary, defend: bool) -> void:
	var at: Vector3 = world.mission_point(s["at"], true)
	_objective(s)
	world.set_marker(at)
	# Los enemigos aparecen cuando el jugador se acerca (no antes: el mundo puede estar lejos).
	while _flat(_focus_pos(), at) > 55.0:
		await get_tree().process_frame
	var waves := int(s.get("waves", 1))
	var count := clampi(int(s.get("count", 4)), 1, 8)
	var total_time := float(s.get("time", 0.0))
	var elapsed := 0.0
	for w in waves:
		_spawn_group(s, at, count, true, false)
		if waves > 1:
			world.hud.toast("OLEADA %d / %d" % [w + 1, waves], "", 1.8)
		while world.hostiles.alive("mission") > 0:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			if defend and total_time > 0.0:
				world.hud.set_hint("Aguanta: %d s · enemigos: %d" % [maxi(0, int(total_time - elapsed)), world.hostiles.alive("mission")])
			else:
				world.hud.set_hint("Enemigos: %d" % world.hostiles.alive("mission"))
	if defend:
		while elapsed < total_time:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			world.hud.set_hint("Aguanta: %d s" % maxi(0, int(total_time - elapsed)))
	world.set_marker(Vector3.INF)
	world.hud.set_hint("")


## Sigilo: guardias de espaldas alrededor del objetivo. Se cumple al llegar al punto e
## interactuar; si te ven o disparas, se ponen en alerta y hay que abrirse paso.
func _sneak(s: Dictionary) -> void:
	var at: Vector3 = world.mission_point(s["target"], true)
	_objective(s)
	world.set_marker(at)
	while _flat(_focus_pos(), at) > 55.0:
		await get_tree().process_frame
	var gs := s.duplicate()
	if not gs.has("faction"):
		gs["faction"] = "guards"
	_spawn_group(gs, at, clampi(int(s.get("guards", 3)), 1, 6), false, false)
	for u in world.hostiles.units:
		# De espaldas a la dirección por la que llega el jugador.
		var away: Vector3 = u.global_position - _focus_pos()
		u.yaw = atan2(-away.x, -away.z)
	var done := [false]
	world.set_interactable(String(s.get("label", "Entrar")), at, 2.6, func() -> void: done[0] = true)
	var warned := false
	while not done[0]:
		await get_tree().process_frame
		if not warned:
			for u in world.hostiles.units:
				if u.alert and not u.dead:
					warned = true
					world.hud.toast("TE HAN VISTO", "Ábrete paso hasta el objetivo", 2.5)
					break
	world.clear_interactable()
	world.set_marker(Vector3.INF)
	world.hud.set_hint("")


## Persecución a pie: alguien sale corriendo desde `at`; hay que alcanzarlo o derribarlo.
func _chase(s: Dictionary) -> void:
	var at: Vector3 = world.mission_point(s["at"], true)
	_objective(s)
	world.set_marker(at)
	while _flat(_focus_pos(), at) > 30.0:
		await get_tree().process_frame
	var pos: Vector3 = at + Vector3(6.0, 0, 0)
	pos.y = world.ground_height(pos)
	var u = world.hostiles.spawn(pos, "mission", false, true, true, int(FACTION_TINT.get(String(s.get("faction", "")), 6)), 45.0)
	world.hud.toast(String(s.get("toast", "¡SE ESCAPA!")), "", 2.0)
	while is_instance_valid(u) and not u.dead and not u.caught:
		world.set_marker(u.global_position)
		world.hud.set_hint("Distancia: %d m" % int(_flat(_focus_pos(), u.global_position)))
		# Si se aleja demasiado, se le recoloca un poco por delante para que la misión no se rompa.
		if _flat(_focus_pos(), u.global_position) > 150.0:
			u.global_position = _focus_pos() + (u.global_position - _focus_pos()).normalized() * 60.0
			u.global_position.y = world.ground_height(u.global_position) + 0.3
		await get_tree().process_frame
	world.set_marker(Vector3.INF)
	world.hud.set_hint("")


## Recoger o examinar `count` objetos repartidos alrededor de `at` (cajas, pruebas, documentos).
func _collect(s: Dictionary) -> void:
	var at: Vector3 = world.mission_point(s["at"], true)
	var count := clampi(int(s.get("count", 3)), 1, 6)
	var label := String(s.get("label", "Recoger"))
	_objective(s)
	for i in count:
		var ang := TAU * float(i) / float(count) + 0.6
		var along := 5.0 + 4.0 * float(i)
		var pos: Vector3 = at + (Vector3(along, 0, 0) if i % 2 == 0 else Vector3(0, 0, along)) * (1.0 if i % 4 < 2 else -1.0)
		if count == 1:
			pos = at
		pos.y = world.ground_height(pos)
		var node := _make_pickup(pos)
		world.set_marker(pos)
		world.hud.set_hint("%s (%d / %d)" % [String(s.get("hint", label)), i + 1, count])
		var done := [false]
		world.set_interactable(label, pos, 2.4, func() -> void: done[0] = true)
		while not done[0]:
			await get_tree().process_frame
		world.clear_interactable()
		if is_instance_valid(node):
			node.queue_free()
		_pickups.erase(node)
		var _unused := ang
	world.set_marker(Vector3.INF)
	world.hud.set_hint("")


func _make_pickup(pos: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.4, 0.4)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.42, 0.26)
	m.roughness = 0.85
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.3)
	m.emission_energy_multiplier = 0.35
	bm.material = m
	mi.mesh = bm
	world.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.22
	_pickups.append(mi)
	return mi


func _clear_pickups() -> void:
	for n in _pickups:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_pickups.clear()


## Conseguir un vehículo (robándolo del tráfico o cogiendo uno aparcado).
func _steal(s: Dictionary) -> void:
	_objective(s)
	if not s.has("hint"):
		world.hud.set_hint("Acércate a un coche y pulsa Robar o Subir.")
	while world.current_vehicle == null:
		await get_tree().process_frame
	world.hud.set_hint("")


## La policía te busca con `stars` estrellas: hay que perderla.
func _lose_cops(s: Dictionary) -> void:
	_objective(s)
	world.crime.description = world.crime.current_look()
	world.crime.last_known = _focus_pos()
	world.set_wanted(maxi(world.wanted, clampi(int(s.get("stars", 2)), 1, 5)))
	world.police._known_t = 4.0
	world.hud.set_hint("Aléjate, cambia de coche o de ropa y evita que te reconozcan.")
	while world.wanted > 0:
		await get_tree().process_frame
	world.hud.set_hint("")
	world.hud.toast("LOS HAS PERDIDO", "", 2.0)


## Conducir hasta `target` antes de que acabe el tiempo; si no, se repite desde el punto de salida.
func _timed_drive(s: Dictionary) -> void:
	var target: Vector3 = world.mission_point(s["target"], false)
	_objective(s)
	while world.current_vehicle == null:
		world.hud.set_hint("Consigue un vehículo.")
		await get_tree().process_frame
	var start_xf: Transform3D = (world.current_vehicle as Node3D).global_transform
	var dist := _flat(start_xf.origin, target)
	# Tiempo generoso según la distancia (unos 55 km/h de media) salvo que la misión fije otro.
	var limit := maxf(float(s.get("time", 0.0)), maxf(45.0, dist / 15.0 + 25.0))
	var left := limit
	world.set_marker(target)
	while true:
		await get_tree().process_frame
		left -= get_process_delta_time()
		world.hud.set_hint("Tiempo: %d s" % maxi(0, int(left)))
		var node: Node3D = world.current_vehicle if world.current_vehicle else world.player
		if _flat(node.global_position, target) < float(s.get("radius", 10.0)):
			break
		if left <= 0.0:
			world.hud.toast("DEMASIADO TARDE", "Vuelves al punto de salida", 2.5)
			if world.current_vehicle:
				var car: Car = world.current_vehicle
				car.linear_velocity = Vector3.ZERO
				car.angular_velocity = Vector3.ZERO
				car.global_transform = start_xf
			else:
				world.player.place(start_xf.origin + Vector3.UP * 0.4, 0.0)
			left = limit
	world.set_marker(Vector3.INF)
	world.hud.set_hint("")


func _focus_pos() -> Vector3:
	var node: Node3D = world.current_vehicle if world.current_vehicle else world.player
	return node.global_position


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _vec(v: Variant) -> Vector3:
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout


func _objective(s: Dictionary) -> void:
	var hud: HUD = world.hud
	if s.has("objective"):
		hud.set_objective(String(s["objective"]))
	hud.set_hint(String(s.get("hint", "")))


func _say(line: Dictionary) -> float:
	var t := float(line.get("t", 3.0))
	var speaker := String(line.get("speaker", ""))
	world.hud.show_subtitle(speaker, String(line.get("es", "")), t)
	world.on_dialogue_line(speaker, String(line.get("en", "")))
	return t


func _play_lines(lines: Array) -> void:
	for line in lines:
		_skip = false
		var t := _say(line)
		var elapsed := 0.0
		while elapsed < t and not _skip:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
	world.hud.show_subtitle("", "", 0.01)


func _cutscene(s: Dictionary) -> void:
	world.set_gameplay(false)
	world.hud.set_letterbox(true)
	var shots: Array = s.get("shots", [])
	var lines: Array = s.get("lines", [])
	var lines_done := [false]
	if not lines.is_empty():
		_lines_then_flag(lines, lines_done)
	else:
		lines_done[0] = true
	var total := 0.0
	for shot in shots:
		total += float(shot.get("duration", 3.0))
	var i := 0
	var shot_end := 0.0
	var elapsed := 0.0
	while true:
		if i < shots.size() and elapsed >= shot_end:
			var sh: Dictionary = shots[i]
			var from := CameraRig.look_from(_vec(sh["from"]), _vec(sh["look"]))
			var to := CameraRig.look_from(_vec(sh.get("to", sh["from"])), _vec(sh.get("look_to", sh["look"])))
			var d := float(sh.get("duration", 3.0))
			world.rig.cinematic_shot(from, to, d, float(sh.get("fov", 55.0)), float(sh.get("fov_to", sh.get("fov", 55.0))))
			shot_end += d
			i += 1
		if elapsed >= total and lines_done[0]:
			break
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	world.rig.end_cinematic()
	world.hud.set_letterbox(false)
	world.set_gameplay(true)


func _lines_then_flag(lines: Array, flag: Array) -> void:
	await _play_lines(lines)
	flag[0] = true


func _dialogue(s: Dictionary) -> void:
	world.set_gameplay(false)
	world.hud.set_letterbox(true)
	var actors: Array = s.get("actors", [])
	if actors.size() >= 2:
		var a: Node3D = world.actor(String(actors[0]))
		var b: Node3D = world.actor(String(actors[1]))
		if a and b:
			world.face_each_other(a, b)
			var mid := (a.global_position + b.global_position) * 0.5 + Vector3.UP * 1.55
			var side := (b.global_position - a.global_position).cross(Vector3.UP).normalized()
			var cam := mid + side * 3.4 + Vector3.UP * 0.15 + (b.global_position - a.global_position).normalized() * 0.8
			var cam2 := mid + side * 3.0 + Vector3.UP * 0.1 + (b.global_position - a.global_position).normalized() * 1.2
			if world.is_blocked(mid, cam):
				cam = mid - side * 3.4 + Vector3.UP * 0.15
				cam2 = mid - side * 3.0 + Vector3.UP * 0.1
			world.rig.cinematic_shot(CameraRig.look_from(cam, mid), CameraRig.look_from(cam2, mid), 12.0, 42.0, 40.0)
	await _play_lines(s.get("lines", []))
	world.rig.end_cinematic()
	world.hud.set_letterbox(false)
	world.set_gameplay(true)


func _interact_at(pos: Vector3, label: String, s: Dictionary, follow: Node3D = null) -> void:
	_objective(s)
	world.set_marker(pos)
	var done := [false]
	world.set_interactable(label, pos, 2.6, func() -> void: done[0] = true, follow)
	while not done[0]:
		await get_tree().process_frame
	world.clear_interactable()
	world.set_marker(Vector3.INF)
	world.hud.set_hint("")


func _goto(pos: Vector3, radius: float, s: Dictionary, need_vehicle: bool, must_stop: bool) -> void:
	_objective(s)
	world.set_marker(pos)
	while true:
		var node: Node3D = world.current_vehicle if world.current_vehicle else world.player
		var d := Vector2(node.global_position.x - pos.x, node.global_position.z - pos.z).length()
		var ok := d < radius
		if need_vehicle and world.current_vehicle == null:
			ok = false
		if ok and must_stop and world.current_vehicle and (world.current_vehicle as Car).linear_velocity.length() > 2.0:
			world.hud.set_hint("Frena para aparcar.")
			ok = false
		if ok:
			break
		await get_tree().process_frame
	world.set_marker(Vector3.INF)
	world.hud.set_hint("")


func _enter_vehicle(s: Dictionary) -> void:
	var car: Car = world.vehicle(String(s["vehicle"]))
	_objective(s)
	var seat := String(s.get("seat", "driver"))
	if world.current_vehicle == car:
		return
	var done := [false]
	world.set_marker(car.global_position)
	world.set_interactable(String(s.get("label", "Subir")), car.global_position, 3.6, func() -> void: done[0] = true, car)
	while not done[0]:
		await get_tree().process_frame
	world.clear_interactable()
	world.set_marker(Vector3.INF)
	await world.board(car, seat)


func _scripted_drive(s: Dictionary) -> void:
	var car: Car = world.vehicle(String(s["vehicle"]))
	var driver: Node3D = world.actor(String(s.get("driver", "")))
	if driver:
		world.seat_actor(driver, car, "driver")
	world.hud.set_objective("")
	world.hud.set_hint("")
	var route: Array = []
	for p in s["route"]:
		route.append(Vector3(float(p[0]), car.global_position.y, float(p[1])))
	var lines: Array = s.get("lines", [])
	var events: Array = s.get("events", [])
	var speed := float(s.get("speed", 9.0))
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	var heading := car.global_basis.z
	heading.y = 0
	heading = heading.normalized()
	var v := 0.0
	var elapsed := 0.0
	var next_line := 0
	var next_event := 0
	var idx := 0
	while idx < route.size():
		var dt := get_physics_process_delta_time()
		await get_tree().physics_frame
		elapsed += dt
		while next_line < lines.size() and elapsed >= float(lines[next_line].get("at", 0.0)):
			_say(lines[next_line])
			next_line += 1
		while next_event < events.size() and elapsed >= float(events[next_event].get("t", 0.0)):
			if events[next_event].get("spawn_redline_car", false):
				world.spawn_redline_car()
			next_event += 1
		var target: Vector3 = route[idx]
		var to_t := target - car.global_position
		to_t.y = 0
		var last := idx == route.size() - 1
		if to_t.length() < (0.8 if last else 3.0):
			idx += 1
			continue
		var desired := to_t.normalized()
		var turn := heading.signed_angle_to(desired, Vector3.UP)
		heading = heading.rotated(Vector3.UP, clampf(turn, -1.4 * dt, 1.4 * dt)).normalized()
		var want := speed
		if absf(turn) > 0.35:
			want = 4.5
		if last:
			want = minf(want, maxf(1.5, to_t.length() * 0.8))
		v = move_toward(v, want, 3.0 * dt)
		var pos := car.global_position + heading * v * dt
		car.global_transform = Transform3D(Basis.looking_at(-heading, Vector3.UP), pos)
	# Termina de decir las frases pendientes antes de soltar el coche.
	while next_line < lines.size():
		var t := _say(lines[next_line])
		next_line += 1
		await _wait(t)
	await _wait(0.5)
	car.freeze = false
	car.linear_velocity = Vector3.ZERO
	world.hud.show_subtitle("", "", 0.01)
