extends Node3D
## Punto de entrada del juego. Construye Westbrook, crea a Mack, la cámara, los
## coches, los personajes y la interfaz, y gestiona los estados: menú principal,
## cinemática, misión, exploración libre y pausa.

enum State { TITLE, INTRO, PLAYING }

const RAY_CAR_COLOR := Color(0.12, 0.26, 0.18)

var state: State = State.TITLE
var city: CityBuilder
var sky: SkyEnv
var traffic: Traffic
var pedestrians: Pedestrians
var player: Player
var rig: CameraRig
var runner: MissionRunner

var hud: HUD
var touch: TouchControls
var pause_menu: PauseMenu
var map_screen: MapScreen
var title_menu: TitleMenu
var ui_layer: CanvasLayer

var vehicles: Dictionary = {}
var actors: Dictionary = {}
var current_vehicle: Car = null
var current_seat: String = ""
var allow_free_vehicles: bool = true
var parked_bus: Node3D = null

var _interactable: Dictionary = {}
var _marker: Node3D
var _marker_pos: Vector3 = Vector3.INF
var _props: Dictionary = {}
var _occupants: Dictionary = {}   # "car_id:seat" -> Humanoid
var _movers: Array = []           # coches de escena (Redline Kings)
var _photo_texture: Texture2D
var _photo_rect: Control
var _ambient_talk: Dictionary = {}
var _last_location: String = ""
var _title_shot: int = 0
var _gameplay_on: bool = false


func _ready() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	var theme_root := Control.new()
	theme_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_root.theme = UITheme.make_theme()
	ui_layer.add_child(theme_root)

	sky = SkyEnv.new()
	add_child(sky)
	city = CityBuilder.new()
	city.name = "Westbrook"
	add_child(city)
	city.build()
	sky.city = city
	sky.apply_preset("golden", 0.0)

	traffic = Traffic.new()
	add_child(traffic)
	traffic.setup(Settings.traffic_count())
	pedestrians = Pedestrians.new()
	add_child(pedestrians)
	pedestrians.setup(Settings.pedestrian_count())

	player = Player.new()
	player.name = "Mack"
	add_child(player)
	player.place(CityLayout.landmark("player_spawn") + Vector3.UP * 0.2, PI * 0.5)
	rig = CameraRig.new()
	add_child(rig)
	rig.exclude(player)
	traffic.obstacles.append(player)

	_spawn_vehicles()
	_spawn_actors()
	_spawn_scenery_people()
	_make_marker()
	_spawn_prop_bag()

	runner = MissionRunner.new()
	runner.world = self
	add_child(runner)
	runner.mission_finished.connect(_on_mission_finished)

	hud = HUD.new()
	theme_root.add_child(hud)
	hud.radar.footprints = city.footprints
	hud.pause_requested.connect(_open_pause)
	hud.map_requested.connect(_open_map)
	touch = TouchControls.new()
	theme_root.add_child(touch)
	theme_root.move_child(touch, 0)
	map_screen = MapScreen.new()
	map_screen.footprints = city.footprints
	map_screen.visible = false
	theme_root.add_child(map_screen)
	map_screen.closed.connect(_close_map)
	pause_menu = PauseMenu.new()
	pause_menu.visible = false
	theme_root.add_child(pause_menu)
	pause_menu.resume_requested.connect(_close_pause)
	pause_menu.map_requested.connect(func() -> void:
		pause_menu.close()
		_open_map())
	pause_menu.quit_to_title_requested.connect(_quit_to_title)
	title_menu = TitleMenu.new()
	theme_root.add_child(title_menu)
	title_menu.new_game_requested.connect(new_game)
	title_menu.continue_requested.connect(func() -> void: load_game(SaveSystem.AUTOSAVE_SLOT))
	title_menu.load_requested.connect(load_game)
	_photo_rect = _make_photo_overlay()
	theme_root.add_child(_photo_rect)

	_setup_ambient_talk()
	_enter_title()
	_render_photo.call_deferred()

	var args := OS.get_cmdline_user_args()
	for a in args:
		if String(a).begins_with("--capture="):
			var cap: Node = load("res://scripts/tools/capture.gd").new()
			cap.set("world", self)
			cap.set("out_dir", String(a).substr(10))
			add_child(cap)


# ---------------------------------------------------------------- estados

func _enter_title() -> void:
	state = State.TITLE
	GameState.in_game = false
	set_gameplay(false)
	hud.set_letterbox(false)
	title_menu.visible = true
	title_menu.refresh()
	player.visible = false
	sky.apply_preset("golden", 0.0)
	_title_shot = 0
	_next_title_shot()


func _next_title_shot() -> void:
	var shots := [
		[Vector3(-300, 40, 140), Vector3(-120, 5, 0), Vector3(-280, 34, 60), Vector3(-80, 5, -40)],
		[Vector3(-90, 4, 60), Vector3(-100, 3, 15), Vector3(-60, 6, 70), Vector3(-100, 3, 15)],
		[Vector3(200, 60, 160), Vector3(500, 60, -500), Vector3(120, 55, 120), Vector3(560, 70, -520)],
		[Vector3(-420, 8, 75), Vector3(-260, 6, 40), Vector3(-400, 10, 40), Vector3(-240, 8, 10)],
	]
	var s: Array = shots[_title_shot % shots.size()]
	rig.cinematic_shot(CameraRig.look_from(s[0], s[1]), CameraRig.look_from(s[2], s[3]), 14.0, 55.0, 50.0)
	_title_shot += 1


func new_game() -> void:
	GameState.new_game()
	title_menu.visible = false
	state = State.INTRO
	GameState.in_game = true
	_reset_story_positions()
	var intro := IntroCinematic.new()
	intro.world = self
	add_child(intro)
	intro.finished.connect(func() -> void:
		intro.queue_free()
		_start_play()
		runner.start("m01"))
	intro.run()


func load_game(slot: int) -> void:
	if not SaveSystem.load_slot(slot):
		return
	title_menu.visible = false
	GameState.in_game = true
	_reset_story_positions()
	if parked_bus == null:
		parked_bus = BusModel.build()
		add_child(parked_bus)
		parked_bus.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), CityLayout.landmark("bus_bay") + Vector3(0, 0.05, 0))
	if GameState.active_mission != "":
		_prepare_resume(GameState.mission_step)
		_start_play()
		runner.start(GameState.active_mission, GameState.mission_step)
	else:
		if GameState.has_position:
			player.place(GameState.player_position + Vector3.UP * 0.3, GameState.player_yaw)
		_start_play()
		_after_mission_world()
		hud.set_objective("Explora Westbrook · Próxima misión: OLD KEYS (en desarrollo)")


func _start_play() -> void:
	state = State.PLAYING
	rig.end_cinematic()
	sky.apply_preset("morning", 0.0)
	player.visible = true
	rig.follow(player, false)
	rig.yaw = player.face_yaw()
	set_gameplay(true)


func _quit_to_title() -> void:
	get_tree().paused = false
	pause_menu.close()
	pause_menu.visible = false
	runner.stop()
	if current_vehicle:
		_force_exit_vehicle()
	_enter_title()


func _on_mission_finished(_id: String) -> void:
	_after_mission_world()


func _after_mission_world() -> void:
	if GameState.is_mission_completed(1):
		var ray: NPC = actors["big_ray"]
		ray.visible = true
		ray.global_position = Vector3(-96, 0.15, 13.0)
		_ambient_talk["big_ray"] = ["Ve a ver a Okafor si necesitas algo. Y no hagas tonterías.", "La casa no se va a defender sola, Mack."]
		_spawn_prop_door_threat()


## Coloca a cada personaje y coche en su sitio de inicio de historia.
func _reset_story_positions() -> void:
	var car: Car = vehicles["ray_car"]
	_place_car(car, CityLayout.landmark("ray_car"), Vector3(-1, 0, 0))
	for id in actors:
		var a: NPC = actors[id]
		a.visible = true
		a.process_mode = Node.PROCESS_MODE_INHERIT
	_place_actor("big_ray", CityLayout.landmark("big_ray"))
	_clear_occupants()


func _prepare_resume(step: int) -> void:
	var mission := GameData.load_mission(GameState.active_mission)
	var steps: Array = mission.get("steps", [])
	var checkpoints := 0
	for i in mini(step, steps.size()):
		if String(steps[i]["type"]) == "checkpoint":
			checkpoints += 1
	despawn_prop("bag")
	match checkpoints:
		1:
			player.place(Vector3(99, 0.3, -8.2), PI * 0.5)
		2:
			_place_car(vehicles["ray_car"], CityLayout.landmark("mart_stop") + Vector3(0, 0, 2.3), Vector3(-1, 0, 0))
			player.place(Vector3(-16, 0.3, -8.0), 0.0)
			_place_actor("big_ray", Vector3(-23, 0.15, -8.5))
		3:
			_place_car(vehicles["ray_car"], CityLayout.landmark("mack_house_curb"), Vector3(1, 0, 0))
			player.place(Vector3(-96, 0.3, 8.0), PI)
			_place_actor("big_ray", Vector3(-104, 0.15, 7.5))


# ---------------------------------------------------------------- bucle

func _process(delta: float) -> void:
	if state == State.TITLE:
		if rig._cine_t >= 1.0:
			_next_title_shot()
		return
	if state != State.PLAYING:
		_update_movers(delta)
		return
	_update_movers(delta)
	var focus: Node3D = current_vehicle if current_vehicle else player
	if not current_vehicle:
		player.camera_yaw = rig.yaw
	hud.radar.player_pos = focus.global_position
	hud.radar.player_heading = (current_vehicle.global_rotation.y + PI) if current_vehicle else player.face_yaw()
	hud.radar.view_yaw = rig.yaw
	hud.set_speed_kmh(current_vehicle.speed_kmh() if current_vehicle and current_seat == "driver" else -1.0)
	var loc := CityLayout.nearest_street_name(focus.global_position)
	if loc != _last_location:
		_last_location = loc
		hud.show_location(loc)
	if _marker_pos != Vector3.INF:
		_marker.global_position = _marker_pos
		_marker.rotation.y += delta * 1.5
		var bob: Node3D = _marker.get_child(1)
		bob.position.y = 3.2 + sin(Time.get_ticks_msec() * 0.004) * 0.25
	_update_interaction()
	if Controls.just_pressed("pause"):
		_open_pause()
	elif Controls.just_pressed("map"):
		_open_map()
	GameState.set_health(GameState.health)


func _update_interaction() -> void:
	if not _gameplay_on:
		touch.set_interact_label("")
		return
	var label := ""
	var action := Callable()
	if current_vehicle:
		if current_seat == "driver" and allow_free_vehicles:
			if Controls.just_pressed("interact"):
				leave_vehicle()
		return
	if not _interactable.is_empty():
		var p: Vector3 = _interactable["pos"]
		var f: Node3D = _interactable.get("follow")
		if f and is_instance_valid(f):
			p = f.global_position
		if _flat_dist(player.global_position, p) < float(_interactable["radius"]):
			label = _interactable["label"]
			action = _interactable["callback"]
	if label == "" and allow_free_vehicles:
		for id in vehicles:
			var car: Car = vehicles[id]
			if _flat_dist(player.global_position, car.global_position) < 3.4:
				label = "Subir"
				action = func() -> void: board(car, "driver")
				break
	if label == "":
		for id in _ambient_talk:
			var a: NPC = actors.get(id)
			if a and a.visible and _flat_dist(player.global_position, a.global_position) < 2.6:
				label = "Hablar"
				action = func() -> void: _ambient_line(id)
				break
	touch.set_interact_label(label)
	if label != "" and Controls.just_pressed("interact"):
		action.call()


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------- API para misiones

func set_gameplay(on: bool) -> void:
	_gameplay_on = on
	Controls.release_all()
	Controls.enabled = on
	player.input_enabled = on
	hud.set_gameplay_visible(on)
	if not on:
		touch.set_mode("hidden")
	elif current_vehicle:
		touch.set_mode("car" if current_seat == "driver" else "hidden")
	else:
		touch.set_mode("foot")


func resolve_point(target: Variant) -> Vector3:
	if typeof(target) == TYPE_ARRAY:
		var a: Array = target
		return Vector3(float(a[0]), float(a[1]) if a.size() > 2 else 0.0, float(a[a.size() - 1]))
	var id := String(target)
	if actors.has(id):
		return (actors[id] as Node3D).global_position
	if _props.has(id):
		return (_props[id] as Node3D).global_position
	return CityLayout.landmark(id)


func actor(id: String) -> Node3D:
	if id == "player":
		return player
	return actors.get(id)


func vehicle(id: String) -> Car:
	return vehicles.get(id)


func set_marker(pos: Vector3) -> void:
	_marker_pos = pos
	_marker.visible = pos != Vector3.INF
	var markers: Array = []
	if pos != Vector3.INF:
		markers.append({"pos": pos, "color": Color(0.95, 0.78, 0.2), "label": "!"})
	hud.radar.markers = markers
	map_screen.mission_marker = pos


func set_interactable(label: String, pos: Vector3, radius: float, callback: Callable, follow: Node3D = null) -> void:
	_interactable = {"label": label, "pos": pos, "radius": radius, "callback": callback, "follow": follow}


func clear_interactable() -> void:
	_interactable = {}


func capture_state() -> void:
	var n: Node3D = current_vehicle if current_vehicle else player
	GameState.player_position = n.global_position
	GameState.player_yaw = player.face_yaw()
	GameState.has_position = true


func is_blocked(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func face_each_other(a: Node3D, b: Node3D) -> void:
	if a is NPC:
		(a as NPC).face(b.global_position)
	elif a == player:
		var d := b.global_position - a.global_position
		player.set_facing(atan2(-d.x, -d.z))
	if b is NPC:
		(b as NPC).face(a.global_position)
	elif b == player:
		var d := a.global_position - b.global_position
		player.set_facing(atan2(-d.x, -d.z))


func on_dialogue_line(_speaker: String, _english: String) -> void:
	# Punto de enganche para las voces en inglés cuando estén grabadas.
	pass


func board(car: Car, seat: String) -> void:
	if current_vehicle:
		return
	current_vehicle = car
	current_seat = seat
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.collision_layer = 0
	_seat_model("player", GameData.character_look("mack"), car, seat)
	rig.exclude(car)
	rig.follow(car, true)
	car.set_driver(seat == "driver")
	if seat == "driver":
		pedestrians.danger = [car]
		traffic.obstacles = [car]
	touch.set_mode("car" if seat == "driver" else "hidden")
	await get_tree().process_frame


func leave_vehicle() -> void:
	if current_vehicle == null:
		return
	var car := current_vehicle
	car.set_driver(false)
	var t := 0.0
	while car.linear_velocity.length() > 2.5 and t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	# Conductor por la izquierda (+X local); copiloto por la derecha, hacia la acera.
	var side := 1.0 if current_seat == "driver" else -1.0
	var exit := car.exit_point(side)
	if _point_blocked(exit):
		exit = car.exit_point(-side)
	_remove_seat_model(car, current_seat)
	current_vehicle = null
	current_seat = ""
	player.collision_layer = 1
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.place(exit, car.global_rotation.y + PI)
	player.visible = true
	rig.clear_excludes()
	rig.exclude(player)
	rig.follow(player, false)
	rig.yaw = car.global_rotation.y + PI
	pedestrians.danger = []
	traffic.obstacles = [player]
	touch.set_mode("foot" if _gameplay_on else "hidden")


func _force_exit_vehicle() -> void:
	if current_vehicle:
		_remove_seat_model(current_vehicle, current_seat)
		current_vehicle.set_driver(false)
	current_vehicle = null
	current_seat = ""
	player.collision_layer = 1
	player.process_mode = Node.PROCESS_MODE_INHERIT


func _point_blocked(p: Vector3) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.9)
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func seat_actor(a: Node3D, car: Car, seat: String) -> void:
	if a == null or car == null:
		return
	var npc := a as NPC
	a.visible = false
	a.process_mode = Node.PROCESS_MODE_DISABLED
	_seat_model(npc.character_id if npc else "x", GameData.character_look(npc.character_id) if npc else {}, car, seat)


func unseat_actor(a: Node3D, pos: Vector3) -> void:
	if a == null:
		return
	for key in _occupants.keys():
		var h: Humanoid = _occupants[key]
		if h.get_meta("who", "") == (a as NPC).character_id:
			h.queue_free()
			_occupants.erase(key)
	a.process_mode = Node.PROCESS_MODE_INHERIT
	a.global_position = pos
	a.visible = true


func _seat_model(who: String, look: Dictionary, car: Car, seat: String) -> void:
	var key := "%s:%s" % [car.vehicle_id, seat]
	if _occupants.has(key):
		(_occupants[key] as Node).queue_free()
	var h := Humanoid.new()
	car.add_child(h)
	h.setup(look)
	h.set_seated(true)
	h.set_meta("who", who)
	h.position = Vector3(0.4 if seat == "driver" else -0.4, -0.52, -0.15)
	h.rotation.y = PI
	_occupants[key] = h


func _remove_seat_model(car: Car, seat: String) -> void:
	var key := "%s:%s" % [car.vehicle_id, seat]
	if _occupants.has(key):
		(_occupants[key] as Node).queue_free()
		_occupants.erase(key)


func _clear_occupants() -> void:
	for k in _occupants:
		(_occupants[k] as Node).queue_free()
	_occupants.clear()


func spawn_prop(id: String) -> void:
	if id == "door_threat":
		_spawn_prop_door_threat()


func despawn_prop(id: String) -> void:
	if _props.has(id):
		(_props[id] as Node).queue_free()
		_props.erase(id)


func spawn_redline_car() -> void:
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = CarModel.build(1, Color(0.62, 0.05, 0.06), true)
	node.add_child(mi)
	add_child(node)
	var start := Vector3(-200, 0.04, 2.6)
	node.global_transform = Transform3D(Basis.looking_at(Vector3(-1, 0, 0), Vector3.UP), start)
	var k1 := Humanoid.new()
	node.add_child(k1)
	k1.setup(GameData.character_look("viper"))
	k1.set_seated(true)
	k1.position = Vector3(0.4, -0.52, -0.15)
	k1.rotation.y = PI
	_movers.append({"node": node, "dir": Vector3(1, 0, 0), "speed": 9.0, "life": 45.0})


func _update_movers(delta: float) -> void:
	for m in _movers.duplicate():
		var n: Node3D = m["node"]
		n.global_position += (m["dir"] as Vector3) * float(m["speed"]) * delta
		m["life"] = float(m["life"]) - delta
		if float(m["life"]) <= 0.0:
			n.queue_free()
			_movers.erase(m)


func show_photo(caption: String, duration: float) -> void:
	var tex_rect: TextureRect = _photo_rect.get_node("Frame/Photo")
	tex_rect.texture = _photo_texture
	(_photo_rect.get_node("Frame/Caption") as Label).text = caption
	_photo_rect.visible = true
	_photo_rect.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_photo_rect, "modulate:a", 1.0, 0.8)
	tw.tween_interval(maxf(duration - 1.6, 0.5))
	tw.tween_property(_photo_rect, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void: _photo_rect.visible = false)


# ---------------------------------------------------------------- pausa y mapa

func _open_pause() -> void:
	if state != State.PLAYING or runner.running and not _gameplay_on:
		return
	capture_state()
	get_tree().paused = true
	pause_menu.visible = true
	pause_menu.open()


func _close_pause() -> void:
	pause_menu.close()
	pause_menu.visible = false
	get_tree().paused = false


func _open_map() -> void:
	if state != State.PLAYING:
		return
	var focus: Node3D = current_vehicle if current_vehicle else player
	map_screen.player_pos = focus.global_position
	map_screen.player_heading = player.face_yaw()
	get_tree().paused = true
	map_screen.open()


func _close_map() -> void:
	map_screen.close()
	get_tree().paused = false


# ---------------------------------------------------------------- creación

func _place_car(car: Car, pos: Vector3, heading: Vector3) -> void:
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.global_transform = Transform3D(Basis.looking_at(-heading, Vector3.UP), pos + Vector3.UP * 0.15)


func _place_actor(id: String, pos: Vector3) -> void:
	var a: Node3D = actors.get(id)
	if a:
		a.global_position = pos + Vector3.UP * 0.15


func _spawn_vehicles() -> void:
	var defs := [
		["ray_car", 1, RAY_CAR_COLOR, CityLayout.landmark("ray_car"), Vector3(-1, 0, 0), "Coche de Big Ray"],
		["free_sedan", 0, Color(0.55, 0.06, 0.07), Vector3(-130, 0, 4.95), Vector3(1, 0, 0), ""],
		["free_suv", 2, Color(0.08, 0.08, 0.09), Vector3(124, 0, -95.05), Vector3(1, 0, 0), ""],
		["free_pickup", 3, Color(0.75, 0.72, 0.65), Vector3(-200, 0, 104.95), Vector3(1, 0, 0), ""],
	]
	for d in defs:
		var car := Car.new()
		car.name = String(d[0])
		add_child(car)
		car.setup(int(d[1]), d[2], String(d[0]), String(d[5]))
		_place_car(car, d[3], d[4])
		vehicles[String(d[0])] = car


func _spawn_actors() -> void:
	var defs := [
		["big_ray", "big_ray", "arms_crossed"],
		["dre", "dre_corner", "arms_crossed"],
		["ghost", "ghost", "hands_together"],
		["loco", "loco", ""],
		["keisha", "keisha", ""],
		["viper", "viper", "hands_together"],
		["okafor", "neighbor", "arms_crossed"],
	]
	for d in defs:
		var npc := NPC.new()
		add_child(npc)
		npc.setup(String(d[0]), String(d[2]))
		npc.player = player
		npc.global_position = CityLayout.landmark(String(d[1])) + Vector3.UP * 0.15
		actors[String(d[0])] = npc
	(actors["dre"] as NPC).face(CityLayout.landmark("ghost"))
	(actors["ghost"] as NPC).face(CityLayout.landmark("dre_corner"))


func _spawn_scenery_people() -> void:
	# Viajeros en la terminal y dos Redline Kings con Viper.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var spots := [Vector3(88, 0.12, -14), Vector3(110, 0.12, -16), Vector3(116, 0.12, -12), Vector3(94, 0.12, -20), Vector3(122, 0.12, -9)]
	for p in spots:
		var h := Humanoid.new()
		add_child(h)
		h.setup(Humanoid.random_look(rng))
		h.position = p
		h.rotation.y = rng.randf() * TAU
	for i in 2:
		var look := Humanoid.random_look(rng)
		look["top"] = Color(0.62, 0.06, 0.07)
		look["top_type"] = "tee"
		look["female"] = false
		look["head"] = "cap"
		look["head_color"] = Color(0.1, 0.1, 0.1)
		var k := Humanoid.new()
		add_child(k)
		k.setup(look)
		k.position = CityLayout.landmark("viper") + Vector3(1.4 + i * 0.9, 0.12, 1.2 - i * 2.2)
		k.rotation.y = -0.6 + i
		k.pose_idle_stance("arms_crossed")
	# Taxis en la terminal.
	var taxi := CarModel.build(0, Color(0.95, 0.75, 0.1), true)
	for x in [128.0, 135.0, 142.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = taxi
		add_child(mi)
		mi.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), Vector3(x, 0.03, -4.95))


func _make_marker() -> void:
	_marker = Node3D.new()
	add_child(_marker)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 0.9
	cyl.height = 40.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.78, 0.2, 0.22)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	cyl.material = m
	beam.mesh = cyl
	beam.position.y = 20.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(beam)
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5
	cone.bottom_radius = 0.0
	cone.height = 0.9
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(1.0, 0.8, 0.2)
	am.emission_enabled = true
	am.emission = Color(1.0, 0.7, 0.1)
	cone.material = am
	arrow.mesh = cone
	arrow.position.y = 3.2
	_marker.add_child(arrow)
	_marker.visible = false


func _spawn_prop_bag() -> void:
	var bag := Node3D.new()
	var b := MeshBuilder.new()
	b.surface("bag", MeshBuilder.material(Color(0.1, 0.1, 0.11), 0.8))
	b.surface("strap", MeshBuilder.material(Color(0.82, 0.65, 0.2), 0.5, 0.5))
	b.cylinder("bag", Vector3(-0.35, 0.18, 0), 0.18, 0.18, 0.7, 10, Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3.ZERO))
	b.box("strap", Vector3(0, 0.37, 0), Vector3(0.5, 0.03, 0.05))
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	bag.add_child(mi)
	add_child(bag)
	bag.global_position = CityLayout.landmark("bag") + Vector3(0, 0.12, 0)
	_props["bag"] = bag


func _spawn_prop_door_threat() -> void:
	if _props.has("door_threat"):
		return
	var root := Node3D.new()
	add_child(root)
	var door := CityLayout.landmark("mack_house") + Vector3(0, 0, -5.06)
	var paint := Label3D.new()
	paint.text = "VENDE"
	paint.font_size = 160
	paint.pixel_size = 0.0045
	paint.modulate = Color(0.85, 0.05, 0.05)
	paint.outline_size = 0
	paint.position = door + Vector3(0, 1.5, -0.03)
	paint.rotation.y = PI
	paint.rotation.z = 0.12
	root.add_child(paint)
	var letter := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.22, 0.3, 0.005)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.95, 0.94, 0.9)
	lm.material = lmat
	letter.mesh = lm
	letter.position = door + Vector3(0.35, 1.0, -0.04)
	root.add_child(letter)
	# Pañuelo negro y dorado de los Saints atado a la barandilla del porche.
	var rail := CityLayout.landmark("mack_house") + Vector3(4.2, 1.2, -8.6)
	for i in 2:
		var cloth := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.36, 0.05, 0.36)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.05, 0.05, 0.05) if i == 0 else Color(0.83, 0.65, 0.17)
		cm.material = cmat
		cloth.mesh = cm
		cloth.position = rail + Vector3(-0.2, -0.15 - i * 0.04, 0.0)
		cloth.rotation = Vector3(0.6, 0.4, 1.0 + i * 0.3)
		root.add_child(cloth)
	_props["door_threat"] = root


func _make_photo_overlay() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	var frame := PanelContainer.new()
	frame.name = "Frame"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.93, 0.88)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 18
	sb.content_margin_bottom = 56
	frame.add_theme_stylebox_override("panel", sb)
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.custom_minimum_size = Vector2(560, 470)
	frame.position = Vector2(-280, -235)
	frame.rotation = -0.04
	root.add_child(frame)
	var photo := TextureRect.new()
	photo.name = "Photo"
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.custom_minimum_size = Vector2(524, 396)
	frame.add_child(photo)
	var cap := Label.new()
	cap.name = "Caption"
	cap.add_theme_color_override("font_color", Color(0.2, 0.18, 0.16))
	cap.add_theme_font_size_override("font_size", 22)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.size_flags_vertical = Control.SIZE_SHRINK_END
	cap.position = Vector2(0, 40)
	frame.add_child(cap)
	return root


## Renderiza la foto vieja de Mack, Dre y Big Ray delante del taller Vargas.
func _render_photo() -> void:
	var front := CityLayout.landmark("vargas_front") + Vector3(0, 0.15, -3.5)
	var people: Array = []
	var ids := ["dre", "mack", "big_ray"]
	for i in 3:
		var h := Humanoid.new()
		add_child(h)
		h.setup(GameData.character_look(ids[i]))
		h.global_position = front + Vector3((i - 1) * 0.85, 0, 0)
		h.rotation.y = PI
		h.pose_idle_stance("arms_crossed" if i != 1 else "hands_together")
		people.append(h)
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 480)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 42.0
	vp.add_child(cam)
	cam.global_transform = CameraRig.look_from(front + Vector3(0.3, 1.5, 5.2), front + Vector3(0, 1.1, 0))
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img and not img.is_empty():
		img.convert(Image.FORMAT_RGB8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
				var vig := 1.0 - 0.45 * pow(Vector2(float(x) / img.get_width() - 0.5, float(y) / img.get_height() - 0.5).length() * 1.4, 2.0)
				img.set_pixel(x, y, Color(l * 1.08, l * 0.92, l * 0.72) * vig)
		_photo_texture = ImageTexture.create_from_image(img)
	vp.queue_free()
	for h in people:
		(h as Node).queue_free()
	(rig.cine_camera if rig.cinematic else rig.camera).current = true


func _setup_ambient_talk() -> void:
	_ambient_talk = {
		"dre": ["Ocho años, Mack. No tengo nada que decirte. Todavía.", "Esta esquina es de los Saints. Tú ya no eres de aquí."],
		"ghost": ["...", "Dre ha dicho que no. Respeta eso."],
		"loco": ["¿Mack? ¿Mack Johnson? Mi viejo siempre decía que volverías. Pasa por el taller.", "Si tu coche hace ruidos raros, tráemelo. Si los hace la policía, no."],
		"keisha": ["Alguien está comprando Westbrook calle a calle. Y lo hace con papeles muy limpios.", "Si te llega una carta de Crestline, no firmes nada. Ven a verme."],
		"viper": ["Mira quién ha vuelto. Esta calle ya no es de tu madre, hermano.", "Sigue andando, Johnson. Mientras puedas."],
		"okafor": ["Tu madre nunca me dejó cerrar en rojo. Ni un mes.", "Vuelve cuando quieras, Marcus."],
		"big_ray": ["Sube al coche, Mack."],
	}


func _ambient_line(id: String) -> void:
	var lines: Array = _ambient_talk.get(id, [])
	if lines.is_empty():
		return
	var line: String = lines[randi() % lines.size()]
	var a: NPC = actors.get(id)
	if a:
		a.face(player.global_position)
	hud.show_subtitle(GameData.character_name(id), line, 4.0)
