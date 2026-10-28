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
	mission = GameData.load_mission(id)
	if mission.is_empty():
		push_error("Misión no encontrada: %s" % id)
		return
	mission_id = id
	step_index = from_step
	running = true
	world.allow_free_vehicles = false
	GameState.active_mission = id
	var steps: Array = mission["steps"]
	while running and step_index < steps.size():
		var step: Dictionary = steps[step_index]
		step_started.emit(step_index, step)
		await _run_step(step)
		step_index += 1
	running = false
	world.allow_free_vehicles = true
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
			hud.toast("", "Punto de control", 1.5)
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
			await _goto(world.resolve_point(s["target"]), float(s.get("radius", 3.0)), s, false, false)
		"drive_to":
			await _goto(world.resolve_point(s["target"]), float(s.get("radius", 8.0)), s, true, bool(s.get("stop", false)))
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
		_:
			push_warning("Tipo de paso desconocido: %s" % s["type"])


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
