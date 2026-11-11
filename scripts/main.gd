extends Node3D
## Punto de entrada del juego. Construye Westbrook, crea a Mack, la cámara, los
## coches, los personajes y la interfaz, y gestiona los estados: menú principal,
## cinemática, misión, exploración libre y pausa.

enum State { TITLE, INTRO, PLAYING }

const RAY_CAR_COLOR := Color(0.12, 0.26, 0.18)

var state: State = State.TITLE
var city: CityBuilder
var state_world: StateWorld
var sky: SkyEnv
var traffic: Traffic
var radio: Radio
var pedestrians: Pedestrians
var impact_system: ImpactSystem
var combat: Combat
var police: Police
var crime: CrimeSystem
var hostiles: Hostiles
var activities: Activities
var _extras: Dictionary = {}       # nombre -> MixamoPerson (personajes secundarios de escena)
var _speaking: Node3D = null
var _next_mission: Dictionary = {}  # {"id", "title", "pos"} de la misión disponible
var _stolen: Array = []           # coches robados al tráfico (se reciclan los más viejos)
var _stolen_n: int = 0
var interiors: Interiors
var _radar_timer: float = 0.0
var wanted: int = 0
var _wanted_timer: float = 0.0
var player: Player
var rig: CameraRig
var runner: MissionRunner

var hud: HUD
var touch: TouchControls
var pause_menu: PauseMenu
var map_screen: MapScreen
var gps: GPS
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


# ---------------------------------------------------------------- arranque

const BOOT_LOG := "user://boot.log"
const BOOT_FLAG := "user://booting.flag"
## true cuando el mundo está construido y se han dibujado los primeros fotogramas.
var booted: bool = false
var _boot_layer: CanvasLayer
var _boot_t0: int = 0


## Registro de arranque en user://boot.log (se puede abrir desde la app Archivos): sirve para
## saber en qué paso se queda la app si no llega al menú.
func _boot_log(text: String) -> void:
	var line := "[%6.2f s] %s" % [(Time.get_ticks_msec() - _boot_t0) / 1000.0, text]
	print("BOOT ", line)
	var f := FileAccess.open(BOOT_LOG, FileAccess.READ_WRITE) if FileAccess.file_exists(BOOT_LOG) else FileAccess.open(BOOT_LOG, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()


## Pantalla de carga: se dibuja ANTES de construir el mundo, para que el arranque nunca sea una
## pantalla en negro (construir Westbrook y compilar los shaders tarda varios segundos).
func _show_boot_screen() -> void:
	_boot_layer = CanvasLayer.new()
	_boot_layer.layer = 100
	add_child(_boot_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.039, 0.039, 0.055)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boot_layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_boot_layer.add_child(box)
	var title := Label.new()
	title.text = "WESTSIDE LEGACY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	box.add_child(title)
	var sub := Label.new()
	sub.name = "Estado"
	sub.text = "Cargando Westbrook…"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(0.83, 0.65, 0.17))
	box.add_child(sub)
	var tip := Label.new()
	tip.text = "La primera vez puede tardar hasta un minuto."
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 16)
	tip.add_theme_color_override("font_color", Color(0.6, 0.6, 0.64))
	box.add_child(tip)


## Si el arranque anterior no llegó a terminar (la marca sigue ahí), baja la calidad gráfica:
## esta vez se desactivan los efectos pesados y la próxima se usa el renderizador ligero.
func _boot_safety() -> void:
	if FileAccess.file_exists(BOOT_FLAG):
		_boot_log("el arranque anterior no terminó: modo seguro (calidad baja)")
		if Settings.quality != "low":
			Settings.set_quality("low")
	var f := FileAccess.open(BOOT_FLAG, FileAccess.WRITE)
	if f:
		f.store_line(Time.get_datetime_string_from_system())
		f.close()


## Anota la etapa, la muestra en la pantalla de carga y cede un fotograma para que se vea.
func _boot_stage(log_text: String, shown: String) -> void:
	_boot_log(log_text)
	if _boot_layer:
		var l := _boot_layer.find_child("Estado", true, false) as Label
		if l:
			l.text = shown
	await get_tree().process_frame


func _ready() -> void:
	_boot_t0 = Time.get_ticks_msec()
	if FileAccess.file_exists(BOOT_LOG) and FileAccess.open(BOOT_LOG, FileAccess.READ).get_length() > 60000:
		DirAccess.remove_absolute(BOOT_LOG)
	_boot_log("---- arranque %s · %s · %s · renderizador %s (%s) · %s · %d MB RAM · calidad %s" % [
		Time.get_datetime_string_from_system(), OS.get_name(), OS.get_model_name(),
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(), int(float(OS.get_memory_info().get("physical", 0)) / 1048576.0), Settings.quality])
	_boot_safety()
	_show_boot_screen()
	# Tres fotogramas para que la pantalla de carga llegue a verse antes del trabajo pesado.
	for i in 3:
		await get_tree().process_frame
	_boot_log("pantalla de carga visible; construyendo el mundo")
	await _boot()
	_boot_log("mundo construido; primeros fotogramas (compilación de shaders)")
	for i in 6:
		await get_tree().process_frame
	if _boot_layer:
		_boot_layer.queue_free()
		_boot_layer = null
	if FileAccess.file_exists(BOOT_FLAG):
		DirAccess.remove_absolute(BOOT_FLAG)
	booted = true
	_boot_log("arranque completo: menú principal")


func _boot() -> void:
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
	await _boot_stage("cielo listo; ciudad", "Levantando Westbrook…")
	city = CityBuilder.new()
	city.name = "Westbrook"
	add_child(city)
	city.build()
	var kit_buildings := KitBuildings.new()
	kit_buildings.name = "KitBuildings"
	add_child(kit_buildings)
	kit_buildings.build(city)
	await _boot_stage("ciudad y edificios listos; estado", "Extendiendo el estado de Las Brisas…")
	state_world = StateWorld.new()
	state_world.name = "State"
	add_child(state_world)
	state_world.build(city)
	sky.city = city
	var props := StreetProps.new()
	props.name = "StreetProps"
	add_child(props)
	props.build(city)
	await _boot_stage("estado listo; interiores y tiendas", "Abriendo tiendas e interiores…")
	interiors = Interiors.new()
	interiors.name = "Interiors"
	interiors.main = self
	add_child(interiors)
	interiors.build(city)
	sky.apply_preset("golden", 0.0)

	await _boot_stage("interiores listos; tráfico y peatones", "Poniendo tráfico y gente en la calle…")
	traffic = Traffic.new()
	add_child(traffic)
	traffic.setup(Settings.traffic_count())
	var tcontrol := TrafficControl.new()
	tcontrol.name = "TrafficControl"
	add_child(tcontrol)
	tcontrol.build()
	traffic.control = tcontrol
	pedestrians = Pedestrians.new()
	add_child(pedestrians)
	pedestrians.setup(Settings.pedestrian_count())
	radio = Radio.new()
	radio.name = "Radio"
	add_child(radio)
	radio.station_changed.connect(func(_i: int, st: Dictionary) -> void: hud.show_location(String(st.get("name", ""))))
	radio.track_changed.connect(func(title: String, artist: String) -> void:
		if current_vehicle and title != "":
			hud.show_subtitle(artist, title, 3.5))
	impact_system = ImpactSystem.new()
	add_child(impact_system)
	impact_system.traffic = traffic
	pedestrians.pedestrian_hit.connect(_on_pedestrian_hit)

	await _boot_stage("tráfico y peatones listos; jugador y sistemas", "Preparando a Mack…")
	player = Player.new()
	player.name = "Mack"
	add_child(player)
	player.place(CityLayout.landmark("player_spawn") + Vector3.UP * 0.2, PI * 0.5)
	rig = CameraRig.new()
	add_child(rig)
	rig.exclude(player)
	traffic.obstacles.append(player)
	combat = Combat.new()
	combat.name = "Combat"
	combat.main = self
	add_child(combat)
	police = Police.new()
	police.name = "Police"
	police.main = self
	add_child(police)
	hostiles = Hostiles.new()
	hostiles.name = "Hostiles"
	hostiles.main = self
	add_child(hostiles)
	activities = Activities.new()
	activities.name = "Activities"
	activities.main = self
	add_child(activities)
	crime = CrimeSystem.new()
	crime.name = "Crime"
	crime.main = self
	add_child(crime)
	pedestrians.witness_report.connect(func(payload: Dictionary) -> void:
		if not payload.is_empty():
			crime.report(payload))

	_spawn_vehicles()
	_spawn_actors()
	_spawn_scenery_people()
	_make_marker()
	_spawn_prop_bag()

	runner = MissionRunner.new()
	runner.world = self
	add_child(runner)
	runner.mission_finished.connect(_on_mission_finished)

	await _boot_stage("vehículos y personajes listos; interfaz", "Últimos ajustes…")
	hud = HUD.new()
	theme_root.add_child(hud)
	hud.radar.footprints = city.footprints + state_world.footprints
	gps = GPS.new()
	gps.name = "GPS"
	add_child(gps)
	hud.radar.gps = gps
	hud.radar.markers = interiors.radar_markers(player.global_position)
	hud.pause_requested.connect(_open_pause)
	hud.map_requested.connect(_open_map)
	touch = TouchControls.new()
	theme_root.add_child(touch)
	theme_root.move_child(touch, 0)
	map_screen = MapScreen.new()
	map_screen.footprints = city.footprints + state_world.footprints
	map_screen.gps = gps
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
	combat.weapon_changed.connect(_on_weapon_changed)
	_on_weapon_changed(GameState.weapon)

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


## Deja el mundo sin búsqueda ni agentes y el arma del jugador según la partida.
func _reset_heat() -> void:
	police.clear()
	hostiles.clear()
	activities.stop()
	clear_extras()
	_next_mission = {}
	set_wanted(0)
	set_outfit(GameState.outfit)
	combat.set_weapon(GameState.weapon)
	combat.reset()


func new_game() -> void:
	GameState.new_game()
	_reset_heat()
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
	_reset_heat()
	_reset_story_positions()
	if parked_bus == null:
		parked_bus = BusModel.build()
		add_child(parked_bus)
		parked_bus.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), CityLayout.landmark("bus_bay") + Vector3(0, 0.05, 0))
	if GameState.active_mission != "":
		if GameState.active_mission == "m01":
			_prepare_resume(GameState.mission_step)
		elif GameState.has_position:
			player.place(GameState.player_position + Vector3.UP * 0.3, GameState.player_yaw)
		_start_play()
		runner.start(GameState.active_mission, GameState.mission_step)
	else:
		if GameState.has_position:
			player.place(GameState.player_position + Vector3.UP * 0.3, GameState.player_yaw)
		_start_play()
		_after_mission_world()
		_offer_next_mission()


func _start_play() -> void:
	state = State.PLAYING
	rig.end_cinematic()
	sky.apply_preset("morning", 0.0)
	sky.resume_cycle()
	player.visible = true
	rig.follow(player, false)
	rig.yaw = player.face_yaw()
	set_gameplay(true)


func _quit_to_title() -> void:
	get_tree().paused = false
	pause_menu.close()
	pause_menu.visible = false
	runner.stop()
	interiors.reset()
	if current_vehicle:
		_force_exit_vehicle()
	police.clear()
	set_wanted(0)
	_enter_title()


func _on_mission_finished(_id: String) -> void:
	_after_mission_world()
	_offer_next_mission()


# ---------------------------------------------------------------- misiones 02-80

const CITY_BOUNDS := Rect2(-260.0, -260.0, 580.0, 520.0)
const ZONE_ALIASES := {"westbrook": "south_veyra", "south_veyra": "south_veyra", "san_cordova": "san_cordova", "las_brisas": "las_brisas",
	"northpoint": "northpoint", "bahia_solana": "bahia_solana", "isla_brava": "isla_brava", "isla_coral": "isla_coral", "isla_nacar": "isla_nacar"}


## Altura del suelo en un punto (Westbrook es llano; fuera manda el terreno del estado).
func ground_height(p: Vector3) -> float:
	if CITY_BOUNDS.has_point(Vector2(p.x, p.z)):
		return 0.12
	# Fuera del barrio: lo que haya construido encima (muelle, puente) manda sobre el terreno.
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.z), Vector3(p.x, -6.0, p.z))
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and (hit["position"] as Vector3).y > StateLayout.SEA:
			return (hit["position"] as Vector3).y + 0.12
	return maxf(StateLayout.height_at(p.x, p.z), StateLayout.SEA) + 0.15


## Punto de una misión: nombre de lugar, "player", [x, z] o {"zone": id, "dx": m, "dz": m}.
## Dentro de Westbrook los puntos sueltos se ajustan a la esquina de acera más cercana (a pie)
## o al cruce (en coche), para que nunca caigan dentro de un edificio.
func mission_point(target: Variant, on_foot: bool) -> Vector3:
	var p := Vector3.ZERO
	var snap := true
	if typeof(target) == TYPE_DICTIONARY:
		var zid := String(ZONE_ALIASES.get(String((target as Dictionary).get("zone", "south_veyra")), "south_veyra"))
		var c: Vector2 = StateLayout.zone_center(zid)
		p = Vector3(c.x + float((target as Dictionary).get("dx", 0.0)), 0.0, c.y + float((target as Dictionary).get("dz", 0.0)))
	elif typeof(target) == TYPE_ARRAY:
		var a: Array = target
		p = Vector3(float(a[0]), 0.0, float(a[a.size() - 1]))
	else:
		var id := String(target)
		if id == "player":
			var f: Node3D = current_vehicle if current_vehicle else player
			return f.global_position
		p = resolve_point(id)
		snap = false
	if snap and CITY_BOUNDS.has_point(Vector2(p.x, p.z)):
		var nodes: Array = traffic.graph["nodes"]
		var best := Vector2(p.x, p.z)
		var bd := INF
		for n in nodes:
			var d := (n as Vector2).distance_to(Vector2(p.x, p.z))
			if d < bd:
				bd = d
				best = n
		if on_foot:
			var sx := 1.0 if p.x >= best.x else -1.0
			var sz := 1.0 if p.z >= best.y else -1.0
			p = Vector3(best.x + sx * 8.0, 0.0, best.y + sz * 8.0)
		else:
			p = Vector3(best.x, 0.0, best.y)
	elif snap and not CITY_BOUNDS.has_point(Vector2(p.x, p.z)):
		p = _nearest_land(p)
	p.y = ground_height(p)
	return p


## Fuera de Westbrook: si el punto cae en el agua, busca tierra firme cerca (en anillos).
func _nearest_land(p: Vector3) -> Vector3:
	var limit := StateLayout.SEA + 1.0
	if StateLayout.height_at(p.x, p.z) > limit:
		return p
	for ring in range(1, 26):
		var r := 20.0 * ring
		for k in 16:
			var a := TAU * float(k) / 16.0
			var q := Vector3(p.x + cos(a) * r, 0.0, p.z + sin(a) * r)
			if StateLayout.height_at(q.x, q.z) > limit:
				return q
	return p


## Coloca al reparto de una escena en corro alrededor de `at`, mirando al centro. Los nombres que
## no son personajes de la historia se crean como secundarios (peatones Mixamo) con ese nombre.
func stage_cast(cast: Array, at: Vector3) -> void:
	player.place(at + Vector3(0, 0.25, 1.5), 0.0)
	player.visible = true
	var n := cast.size()
	for i in n:
		var id := String(cast[i])
		var ang := PI + (float(i) - float(n - 1) * 0.5) * 0.85
		var pos := at + Vector3(sin(ang) * 1.9, 0.0, cos(ang) * 1.9 + 0.4)
		var yaw := atan2(-(at.x - pos.x), -(at.z + 0.6 - pos.z))
		if actors.has(id):
			_set_actor_present(id, true)
			var a: NPC = actors[id]
			a.global_position = pos + Vector3.UP * 0.2
			a.velocity = Vector3.ZERO
			a.model.rotation.y = yaw
			a.look_at_player = false
		else:
			var m: Node3D = _extras.get(id)
			if m == null or not is_instance_valid(m):
				if MixamoPerson.available():
					var mp := MixamoPerson.new()
					add_child(mp)
					mp.setup({"model": absi(id.hash()) % MixamoPerson.MODELS.size(), "tint": absi(id.hash() / 7) % 7, "scale": 1.0, "phase": 0.2})
					m = mp
				else:
					var hh := Humanoid.new()
					add_child(hh)
					hh.setup(Humanoid.random_look(RandomNumberGenerator.new()))
					m = hh
				_extras[id] = m
			m.global_position = pos + Vector3.UP * 0.05
			m.rotation.y = yaw
	var d := at + Vector3(0, 0, -0.6) - player.global_position
	player.set_facing(atan2(-d.x, -d.z))


func clear_extras() -> void:
	for k in _extras:
		if is_instance_valid(_extras[k]):
			(_extras[k] as Node).queue_free()
	_extras.clear()
	for id in actors:
		(actors[id] as NPC).look_at_player = true


## Nodo del personaje que dice una frase (por alias: "Mack", "Dre", "Big Ray"... o secundario).
func speaker_node(speaker: String) -> Node3D:
	var key := speaker.to_lower()
	if key == "mack":
		return player
	for id in actors:
		if GameData.character_name(String(id)).to_lower() == key or String(id) == key.replace(" ", "_"):
			var a: Node3D = actors[id]
			return a if a.visible else null
	if _extras.has(speaker) and is_instance_valid(_extras[speaker]):
		return _extras[speaker]
	return null


## El que habla gesticula con las manos mientras dura su frase.
func set_speaking(node: Node3D, on: bool) -> void:
	var model: Node = null
	if node == player:
		model = player.model
	elif node is NPC:
		model = (node as NPC).model
	if model and model.has_method("set_talking"):
		model.call("set_talking", on)
		if not on or node != player:
			model.call("animate", 0.016, 0.0, true)
		if not on and node is NPC and (node as NPC).stance != "":
			model.call("pose_idle_stance", (node as NPC).stance)
	_speaking = node if on else null


## Tras cada misión (o al cargar partida) deja disponible la siguiente en su punto de inicio.
func _offer_next_mission() -> void:
	_next_mission = {}
	var n := GameState.next_mission_number()
	if n < 2 or n > 80 or runner.running:
		return
	var id := "m%02d" % n
	if not FileAccess.file_exists("res://data/missions/%s.json" % id):
		return
	var m := GameData.load_mission(id)
	if m.is_empty():
		return
	var pos := mission_point(m.get("start", "mack_door"), true)
	_next_mission = {"id": id, "title": String(m.get("title", id)), "pos": pos}
	hud.set_objective("Siguiente misión: %s (M en el radar)" % String(m.get("title", id)))
	set_marker(pos)


func start_next_mission() -> void:
	if _next_mission.is_empty() or runner.running or activities.active != "":
		return
	var id: String = _next_mission["id"]
	_next_mission = {}
	set_marker(Vector3.INF)
	police.clear()
	set_wanted(0)
	for a in actors:
		_set_actor_present(String(a), false)
	GameState.active_mission = id
	GameState.mission_step = 0
	runner.start(id)


func _after_mission_world() -> void:
	if GameState.is_mission_completed(1):
		var ray: NPC = actors["big_ray"]
		ray.visible = true
		ray.global_position = Vector3(-96, 0.15, 13.0)
		_ambient_talk["big_ray"] = ["Ve a ver a Okafor si necesitas algo. Y no hagas tonterías.", "La casa no se va a defender sola, Mack."]
		_spawn_prop_door_threat()


## Coloca a cada personaje y coche en su sitio de inicio de historia.
func _reset_story_positions() -> void:
	interiors.reset()
	var car: Car = vehicles["ray_car"]
	_place_car(car, CityLayout.landmark("ray_car"), Vector3(-1, 0, 0))
	for id in actors:
		_set_actor_present(String(id), _story_needs(String(id)))
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
	if rig == null or hud == null:
		return   # todavía cargando
	if state == State.TITLE:
		if rig._cine_t >= 1.0:
			_next_title_shot()
		return
	if state != State.PLAYING:
		_update_movers(delta)
		return
	_update_movers(delta)
	sky.set_time_of_day(GameState.world_minutes)
	if current_vehicle:
		current_vehicle.set_lights(sky.night_amount() > 0.35)
	if wanted > 0:
		# Las estrellas solo bajan mientras ningún agente ve al jugador.
		if police.any_seen:
			_wanted_timer = maxf(_wanted_timer, WANTED_COOLDOWN)
		_wanted_timer -= delta
		if _wanted_timer <= 0.0:
			set_wanted(wanted - 1)
	crime.set_known(police.any_seen)
	hud.set_wanted_searching(wanted > 0 and not police.any_seen)
	if not current_vehicle and _gameplay_on and interiors.inside < 0 and not interiors.busy:
		combat.update(delta)
	elif player.model:
		player.model.overlay = {}
	hud.set_ammo(GameState.ammo if GameState.weapon != "fist" else -1)
	var focus: Node3D = current_vehicle if current_vehicle else player
	if not current_vehicle:
		player.camera_yaw = rig.yaw
	hud.radar.player_pos = focus.global_position
	hud.radar.player_heading = (current_vehicle.global_rotation.y + PI) if current_vehicle else player.face_yaw()
	hud.radar.view_yaw = rig.yaw
	hud.radar.speed_mps = current_vehicle.speed_kmh() / 3.6 if current_vehicle else 0.0
	gps.player_pos = focus.global_position
	gps.active = interiors.inside < 0
	hud.set_speed_kmh(current_vehicle.speed_kmh() if current_vehicle and current_seat == "driver" else -1.0)
	if hud.has_method("set_clock"):
		var mins := int(GameState.world_minutes)
		hud.call("set_clock", mins / 60, mins % 60)
	var loc := CityLayout.nearest_street_name(focus.global_position)
	if interiors.inside >= 0:
		loc = interiors.current_name()
	if loc != _last_location:
		_last_location = loc
		hud.show_location(loc)
	if _marker_pos != Vector3.INF:
		_marker.global_position = _marker_pos
		_marker.rotation.y += delta * 1.5
		var bob: Node3D = _marker.get_child(1)
		bob.position.y = 3.2 + sin(Time.get_ticks_msec() * 0.004) * 0.25
	_update_interaction()
	_radar_timer -= delta
	if _radar_timer <= 0.0:
		_radar_timer = 0.5
		_refresh_radar_markers()
	if GameState.health <= 0.0 and not interiors.busy:
		interiors.wasted_respawn()
	if Controls.just_pressed("pause"):
		_open_pause()
	elif Controls.just_pressed("map"):
		_open_map()
	GameState.set_health(GameState.health)


const WANTED_COOLDOWN := 18.0


func _on_pedestrian_hit(pos: Vector3, _speed: float) -> void:
	crime.commit(pos, 1)


## Fija el nivel de búsqueda (0-6) y reinicia la cuenta atrás para perder una estrella.
func set_wanted(level: int) -> void:
	wanted = clampi(level, 0, 6)
	_wanted_timer = WANTED_COOLDOWN
	hud.set_wanted(wanted)
	if wanted == 0 and crime:
		crime.clear()


func refresh_wanted() -> void:
	_wanted_timer = WANTED_COOLDOWN


## Disparos en la calle: quien lo oiga llama a la policía.
func on_gunfire() -> void:
	crime.commit(player.global_position, 1, true)


const OUTFIT_PRICE := 45
const BARBER_PRICE := 25
const TATTOO_PRICE := 60
const MAX_TATTOOS := 5


## Mack se pone el siguiente conjunto de los que tiene (armario de su casa).
func change_outfit() -> void:
	var owned: Array = GameState.owned_outfits
	if owned.size() < 2:
		hud.toast("SOLO TIENES UN CONJUNTO", "Compra más ropa en Veyra Threads (R en el radar)", 3.0)
		return
	var i := owned.find(GameState.outfit)
	set_outfit(int(owned[(i + 1) % owned.size()]))
	hud.toast("ROPA CAMBIADA", Humanoid.outfit_name(GameState.outfit), 2.5)
	crime.look_changed()


func set_outfit(i: int) -> void:
	GameState.outfit = clampi(i, 0, Humanoid.OUTFITS.size() - 1)
	if not GameState.owned_outfits.has(GameState.outfit):
		GameState.owned_outfits.append(GameState.outfit)
	player.model.set_look(GameState.outfit, GameState.head_style)


func _pay(price: int, shop: String) -> bool:
	if GameState.money < price:
		hud.toast("Necesitas $%d" % price, shop, 2.5)
		return false
	GameState.add_money(-price)
	return true


## Tienda de ropa: compra el siguiente conjunto que no tengas y te lo pone.
func buy_outfit() -> void:
	var next := -1
	for i in Humanoid.OUTFITS.size():
		if not GameState.owned_outfits.has(i):
			next = i
			break
	if next < 0:
		change_outfit()
		return
	if not _pay(OUTFIT_PRICE, "Veyra Threads"):
		return
	set_outfit(next)
	hud.toast("ROPA NUEVA  -$%d" % OUTFIT_PRICE, Humanoid.outfit_name(next), 3.0)
	crime.look_changed()


const AMMO_PRICE := 40
const AMMO_PACK := 36


## Armería: caja de munición.
func buy_ammo() -> void:
	if GameState.ammo >= GameState.MAX_AMMO:
		hud.toast("NO CABE MÁS MUNICIÓN", "", 2.0)
		return
	if not _pay(AMMO_PRICE, "Iron Sights"):
		return
	GameState.ammo = mini(GameState.ammo + AMMO_PACK, GameState.MAX_AMMO)
	hud.toast("+%d BALAS  -$%d" % [AMMO_PACK, AMMO_PRICE], "", 2.0)


## Armería: siguiente arma que no tengas (escopeta y subfusil).
func next_weapon_for_sale() -> String:
	for w in ["shotgun", "smg"]:
		if not GameState.weapons.has(w):
			return w
	return ""


func buy_weapon() -> void:
	var w := next_weapon_for_sale()
	if w == "":
		hud.toast("YA TIENES TODO EL ARSENAL", "", 2.0)
		return
	var st: Dictionary = Combat.STATS[w]
	if not _pay(int(st["price"]), "Iron Sights"):
		return
	GameState.weapons.append(w)
	combat.set_weapon(w)
	hud.toast("%s COMPRADA  -$%d" % [String(st["name"]).to_upper(), int(st["price"])], "Cambia de arma con el botón Arma", 3.0)


## Barbería: siguiente tinte de barba y gorra (cambia cómo te describe la policía).
func buy_head_style() -> void:
	if not _pay(BARBER_PRICE, "Fade Kings"):
		return
	GameState.head_style = (GameState.head_style + 1) % Humanoid.HEAD_STYLES.size()
	player.model.set_look(GameState.outfit, GameState.head_style)
	hud.toast("ESTILO NUEVO  -$%d" % BARBER_PRICE, "Barba y gorra: %s" % Humanoid.head_name(GameState.head_style), 3.0)
	crime.look_changed()


## Estudio de tatuajes: cada tatuaje da respeto con los Westbrook Saints (máximo MAX_TATTOOS).
func buy_tattoo() -> void:
	if GameState.tattoos >= MAX_TATTOOS:
		hud.toast("NO TE QUEDA SITIO", "Ya llevas %d tatuajes" % MAX_TATTOOS, 2.5)
		return
	if not _pay(TATTOO_PRICE, "Ink Saints"):
		return
	GameState.tattoos += 1
	GameState.change_reputation("westbrook_saints", 4)
	hud.toast("TATUAJE NUEVO  -$%d" % TATTOO_PRICE, "+4 de respeto con los Westbrook Saints (%d/%d)" % [GameState.tattoos, MAX_TATTOOS], 3.5)


## Daño al jugador (balas de la policía): destello rojo, sacudida y, a cero, hospital.
func damage_player(amount: float) -> void:
	if GameState.health <= 0.0:
		return
	GameState.set_health(GameState.health - amount)
	hud.damage_flash()
	rig.shake(0.25)
	if player.model:
		player.model.flinch(1.0 if randf() < 0.5 else -1.0)


## Detenido por un agente (1 estrella): multa, sin munición y a la puerta de la comisaría.
func busted() -> void:
	interiors.busted_respawn()


func _on_weapon_changed(kind: String) -> void:
	hud.set_weapon_icon(kind)
	touch.set_attack_label("Disparar" if kind != "fist" else "Golpe")


## Roba un coche del tráfico: lo sustituye por uno conducible igual y echa al conductor.
func steal_traffic_car(tc: Traffic.TrafficCar) -> void:
	if current_vehicle or not is_instance_valid(tc):
		return
	var xf := tc.global_transform
	var heading := tc.heading
	var style := tc.style
	var color := tc.body_color
	traffic.remove_car(tc, xf.origin)
	_stolen_n += 1
	var id := "stolen_%d" % _stolen_n
	var car := Car.new()
	car.name = id
	add_child(car)
	car.setup(style, color, id, "")
	_place_car(car, xf.origin, heading)
	vehicles[id] = car
	_hook_car(car)
	_stolen.append(id)
	while _stolen.size() > 3:
		var old: String = _stolen.pop_front()
		var oc: Car = vehicles.get(old)
		vehicles.erase(old)
		if oc and is_instance_valid(oc):
			oc.queue_free()
	# El conductor sale por la izquierda y huye; con testigos, una estrella.
	var left := Vector3(-heading.z, 0, heading.x) * -1.0
	pedestrians.add_runner(xf.origin + left * 2.0, xf.origin)
	pedestrians.panic(xf.origin, 14.0, 6.0)
	await board(car, "driver")
	# El testigo describe el coche en el que te vas.
	crime.commit(xf.origin, 1)


func _hook_car(car: Car) -> void:
	car.impact_system = impact_system
	if not car.crashed.is_connected(_on_car_crashed):
		car.crashed.connect(_on_car_crashed)


func _on_car_crashed(strength: float, _point: Vector3, _other: Node) -> void:
	rig.shake(strength * 1.2)


func _update_interaction() -> void:
	if not _gameplay_on:
		touch.set_interact_label("")
		return
	var label := ""
	var action := Callable()
	if current_vehicle:
		if Controls.just_pressed("radio"):
			radio.next_station()
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
	if label == "" and not runner.running and interiors.inside < 0:
		var act := activities.interaction(player.global_position)
		if not act.is_empty():
			label = act["label"]
			action = act["action"]
	if label == "" and not _next_mission.is_empty() and not runner.running and activities.active == "" and _flat_dist(player.global_position, _next_mission["pos"]) < 4.0:
		label = "Empezar misión"
		action = func() -> void: start_next_mission()
	if label == "" and allow_free_vehicles:
		var tc := traffic.nearest_car(player.global_position, 3.6)
		if tc != null and tc.speed < 6.0:
			label = "Robar"
			action = func() -> void: steal_traffic_car(tc)
	if label == "":
		for id in _ambient_talk:
			var a: NPC = actors.get(id)
			if a and a.visible and _flat_dist(player.global_position, a.global_position) < 2.6:
				label = "Hablar"
				action = func() -> void: _ambient_line(id)
				break
	if label == "":
		var ia := interiors.interaction(player.global_position, _interactable.is_empty())
		if not ia.is_empty():
			label = ia["label"]
			action = ia["action"]
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
	_refresh_radar_markers()
	map_screen.mission_marker = pos
	gps.set_mission_target(pos)


## Marcador de misión + puntos permanentes (hospital, policía, pintura) cercanos.
func _refresh_radar_markers() -> void:
	var markers: Array = []
	if _marker_pos != Vector3.INF:
		markers.append({"pos": _marker_pos, "color": Color(0.95, 0.78, 0.2), "label": "!"})
	if interiors.inside < 0:
		markers.append_array(interiors.radar_markers(player.global_position))
		if activities:
			markers.append_array(activities.radar_markers(player.global_position))
		if not _next_mission.is_empty() and _marker_pos == Vector3.INF:
			markers.append({"pos": _next_mission["pos"], "color": Color(0.95, 0.78, 0.2), "label": "M"})
	hud.radar.markers = markers


func set_interactable(label: String, pos: Vector3, radius: float, callback: Callable, follow: Node3D = null) -> void:
	_interactable = {"label": label, "pos": pos, "radius": radius, "callback": callback, "follow": follow}


func clear_interactable() -> void:
	_interactable = {}


func capture_state() -> void:
	var n: Node3D = current_vehicle if current_vehicle else player
	GameState.player_position = n.global_position
	GameState.player_yaw = player.face_yaw()
	if interiors.inside >= 0:
		# Dentro de un interior se guarda la puerta de la calle, no la sala lejana.
		var t := interiors.outside_transform()
		GameState.player_position = t.origin
		GameState.player_yaw = t.basis.get_euler().y
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
	player.model.overlay = {}
	_seat_model("player", GameData.character_look("mack"), car, seat)
	rig.exclude(car)
	rig.follow(car, true)
	car.set_driver(seat == "driver")
	_hook_car(car)
	if seat == "driver":
		pedestrians.vehicle = car
		pedestrians.danger = [car]
		traffic.obstacles = [car]
	touch.set_mode("car" if seat == "driver" else "hidden")
	radio.enter_vehicle()
	await get_tree().process_frame


func leave_vehicle() -> void:
	if current_vehicle == null:
		return
	var car := current_vehicle
	car.set_driver(false)
	car.set_lights(false)
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
	pedestrians.vehicle = null
	traffic.obstacles = [player]
	touch.set_mode("foot" if _gameplay_on else "hidden")
	radio.exit_vehicle()


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
	if who == "player":
		h.set_look(GameState.outfit, GameState.head_style)
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
		["free_cuda", 4, Color(0.78, 0.45, 0.1), Vector3(-180, 0, -4.95), Vector3(-1, 0, 0), ""],
		["free_patrol", 5, Color.WHITE, Vector3(140, 0, -104.95), Vector3(1, 0, 0), ""],
		["free_ambulance", 6, Color.WHITE, Vector3(214, 0, -104.95), Vector3(1, 0, 0), ""],
	]
	for d in defs:
		var car := Car.new()
		car.name = String(d[0])
		add_child(car)
		car.setup(int(d[1]), d[2], String(d[0]), String(d[5]))
		_place_car(car, d[3], d[4])
		vehicles[String(d[0])] = car
		_hook_car(car)


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
	for id in actors:
		_set_actor_present(String(id), _story_needs(String(id)))


## Los 7 protagonistas no son gente de la calle: solo aparecen en el mundo
## cuando la misión activa (o la historia ya jugada) los necesita.
const STORY_CAST := ["dre", "ghost", "loco", "keisha", "viper"]


func _story_needs(id: String) -> bool:
	if not STORY_CAST.has(id):
		return true  # Big Ray y Okafor: los coloca la propia historia.
	var mid: String = GameState.active_mission
	if mid == "":
		return false
	var m := GameData.load_mission(mid)
	return JSON.stringify(m).contains("\"%s\"" % id)


func _set_actor_present(id: String, on: bool) -> void:
	var a: NPC = actors.get(id)
	if a == null:
		return
	a.visible = on
	a.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if not on:
		_ambient_talk.erase(id)


func _spawn_scenery_people() -> void:
	# Viajeros en la terminal y dos Redline Kings con Viper.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var spots := [Vector3(88, 0.12, -14), Vector3(110, 0.12, -16), Vector3(116, 0.12, -12), Vector3(94, 0.12, -20), Vector3(122, 0.12, -9)]
	var real := MixamoPerson.available()
	for p in spots:
		var h: Node3D
		if real:
			var mp := MixamoPerson.new()
			add_child(mp)
			mp.setup(MixamoPerson.random_look(rng))
			if rng.randf() < 0.4:
				mp.pose_idle_stance("phone")
			h = mp
		else:
			var hh := Humanoid.new()
			add_child(hh)
			hh.setup(Humanoid.random_look(rng))
			h = hh
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
