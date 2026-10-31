extends Node3D
## Pruebas automáticas (se ejecutan en CI antes de compilar el IPA):
##   godot --headless --path . res://tests/test_runner.tscn
## Sale con código 0 si todo pasa y 1 si algo falla.

var _failed: int = 0
var _passed: int = 0


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("  OK   ", what)
	else:
		_failed += 1
		printerr("  FALLO ", what)


func _ready() -> void:
	await get_tree().process_frame
	print("== Datos")
	check(GameData.zones.size() == 8, "8 zonas (5 ciudades + 3 islas)")
	check(GameData.factions.size() == 4, "4 bandas")
	for id in ["mack", "dre", "ghost", "keisha", "loco", "big_ray", "viper"]:
		check(not GameData.character_look(id).is_empty(), "personaje con aspecto: %s" % id)
	var m := GameData.load_mission("m01")
	check(m.get("number", 0) == 1 and (m.get("steps", []) as Array).size() > 20, "misión 01 cargada")
	var known := ["phase", "checkpoint", "cutscene", "dialogue", "pickup", "talk", "goto", "drive_to", "enter_vehicle", "exit_vehicle", "scripted_drive", "move_actor_to_vehicle", "move_actor_from_vehicle", "prop", "toast", "reward", "complete", "wait"]
	var all_known := true
	for s in m["steps"]:
		if not known.has(String(s["type"])):
			all_known = false
			printerr("     paso desconocido: ", s["type"])
	check(all_known, "todos los pasos de m01 tienen tipo conocido")

	print("== Progreso y desbloqueos")
	GameState.new_game()
	check(GameState.money == GameState.START_MONEY, "dinero inicial")
	check(GameState.is_zone_unlocked("south_veyra"), "South Veyra abierta al empezar")
	check(not GameState.is_zone_unlocked("san_cordova"), "San Cordova cerrada al empezar")
	var unlocked := []
	EventBus.zone_unlocked.connect(func(z: String) -> void: unlocked.append(z))
	GameState.complete_mission(22)
	check(GameState.is_zone_unlocked("san_cordova") and unlocked.has("san_cordova"), "misión 22 abre San Cordova")
	GameState.complete_mission(69)
	check(GameState.is_zone_unlocked("bahia_solana"), "misión 69 abre Bahía Solana")
	check(GameState.next_mission_number() == 1, "siguiente misión = 1")

	print("== Guardado")
	SaveSystem.save_dir = "user://test_saves"
	GameState.add_money(1000)
	GameState.active_mission = "m01"
	GameState.mission_step = 7
	check(SaveSystem.save_slot(2), "guardar ranura 2")
	var before := GameState.to_dict()
	GameState.new_game()
	check(SaveSystem.load_slot(2), "cargar ranura 2")
	check(GameState.money == int(before["money"]) and GameState.mission_step == 7 and GameState.active_mission == "m01", "los datos sobreviven al guardado")
	var f := FileAccess.open(ProjectSettings.globalize_path(SaveSystem.slot_path(3)), FileAccess.WRITE)
	f.store_string("{esto no es json")
	f.close()
	check(not SaveSystem.load_slot(3), "una partida dañada no se carga ni rompe nada")
	check(SaveSystem.slot_summary(2)["exists"], "resumen de ranura")

	print("== Ciudad")
	var graph := CityLayout.road_graph()
	var symmetric := true
	for i in (graph["links"] as Array).size():
		for j in graph["links"][i]:
			if not (graph["links"][j] as Array).has(i):
				symmetric = false
	check(symmetric and (graph["nodes"] as Array).size() > 20, "grafo de calles coherente")
	var city := CityBuilder.new()
	add_child(city)
	city.build()
	check(city.footprints.size() > 120, "edificios generados: %d" % city.footprints.size())
	var mesh := CarModel.build(0, Color.RED, true)
	check(mesh.get_surface_count() >= 6, "modelo de coche")
	for id in ["mack", "dre", "ghost", "keisha", "loco", "big_ray", "viper", "okafor"]:
		var h := Humanoid.new()
		add_child(h)
		h.setup(GameData.character_look(id))
		check(h.get_child_count() > 0, "modelo de %s" % id)

	print("== Física del coche")
	var car := Car.new()
	add_child(car)
	car.setup(1, Color.GREEN, "test")
	car.global_position = Vector3(-200, 1.0, 2.6)
	car.global_rotation = Vector3(0, PI * 0.5, 0)
	await _physics(30)
	car.set_driver(true)
	Controls.enabled = true
	Controls.touch_move = Vector2(0, 1)
	await _physics(360)
	var top := car.speed_kmh()
	print("     velocidad tras 6 s: %.1f km/h" % top)
	check(top > 45.0 and top < 200.0, "acelera de forma creíble")
	check(car.global_basis.y.y > 0.9, "no vuelca en recta")
	Controls.touch_move = Vector2(0, -1)
	await _physics(240)
	print("     velocidad tras frenar 4 s: %.1f km/h" % car.speed_kmh())
	check(car.speed_kmh() < 25.0, "frena")
	Controls.touch_move = Vector2.ZERO
	car.set_driver(false)

	print("== GPS y radar")
	var gps := GPS.new()
	add_child(gps)
	var far_a := CityLayout.landmark("player_spawn")
	var far_b := CityLayout.landmark("beach")
	var route := gps.find_route(Vector2(far_a.x, far_a.z), Vector2(far_b.x, far_b.z))
	var straight := Vector2(far_a.x, far_a.z).distance_to(Vector2(far_b.x, far_b.z))
	check(route.size() >= 4 and GPS.route_length(route) >= straight * 0.99, "A* encuentra ruta entre dos landmarks lejanos (%d puntos, %.0f m)" % [route.size(), GPS.route_length(route)])
	check(route[0].distance_to(Vector2(far_a.x, far_a.z)) < 0.1 and route[route.size() - 1].distance_to(Vector2(far_b.x, far_b.z)) < 0.1, "la ruta empieza en el jugador y acaba en el destino")
	var desert := CityLayout.landmark("desert_road")
	var hw := gps.find_route(Vector2(far_a.x, far_a.z), Vector2(desert.x, desert.z))
	check(hw.size() >= 3 and GPS.route_length(hw) > 2400.0, "la ruta llega a la autopista del desierto (%.0f m)" % GPS.route_length(hw))
	var pier_pt := CityLayout.landmark("pier")
	var pier_route := gps.find_route(Vector2(far_a.x, far_a.z), Vector2(pier_pt.x, pier_pt.z))
	check(pier_route.size() >= 4, "ruta hasta el muelle")
	gps.player_pos = Vector3(0, 0, 0)
	gps.set_waypoint(Vector3(-150, 0, 100))
	check(gps.has_waypoint() and gps.waypoint_route.size() >= 3, "el waypoint se pone y traza ruta")
	gps.toggle_waypoint(Vector3(-148, 0, 98), 14.0)
	check(not gps.has_waypoint() and gps.waypoint_route.is_empty(), "tocar sobre el waypoint lo quita")
	gps.set_waypoint(Vector3(-150, 0, 100))
	gps.player_pos = Vector3(-140, 0, 96)
	gps.update(0.1)
	check(not gps.has_waypoint(), "el waypoint se borra al llegar (< 15 m)")
	gps.set_mission_target(Vector3(100, 0, -122))
	check(gps.mission_route.size() >= 3, "el GPS de misión traza ruta")
	var radar := Radar.new()
	var hud_test := HUD.new()
	add_child(hud_test)
	add_child(radar)
	radar.size = Vector2(350, 230)
	radar.gps = gps
	radar.player_pos = Vector3(0, 0, 0)
	radar.view_yaw = 0.7
	gps.player_pos = Vector3.ZERO
	gps.set_waypoint(Vector3(-150, 0, 100))
	await get_tree().process_frame
	await get_tree().process_frame
	hud_test.set_wanted(3)
	hud_test.set_armor(60.0)
	hud_test.set_clock(11, 17)
	await get_tree().process_frame
	check(radar.is_inside_tree() and hud_test.radar != null and hud_test.radar.size.x > 100.0, "radar y HUD se instancian y dibujan sin errores")
	check(Radar.clamp_to_ellipse(Vector2(1000, 0), Vector2(170, 110)).is_equal_approx(Vector2(170, 0)), "marcadores se acotan a la elipse")
	radar.queue_free()
	hud_test.queue_free()
	gps.queue_free()

	print("== Peatones Mixamo")
	check(MixamoPerson.available(), "recursos Mixamo disponibles (modelos + librería)")
	for mp in MixamoPerson.MODELS:
		var ps := load(mp) as PackedScene
		check(ps != null and ps.can_instantiate(), "modelo Mixamo carga: %s" % String(mp).get_file())
	var mlib := load(MixamoPerson.LIB_PATH) as AnimationLibrary
	check(mlib != null, "librería de animaciones Mixamo")
	for an in ["walk", "run", "sit_talk", "phone", "idle"]:
		check(mlib != null and mlib.has_animation(an), "animación %s en la librería" % an)
	if mlib != null:
		var walk_a := mlib.get_animation("walk")
		check(walk_a.loop_mode == Animation.LOOP_LINEAR and mlib.get_animation("run").loop_mode == Animation.LOOP_LINEAR, "walk y run en bucle")
		var root_ok := true
		for an in ["walk", "run", "idle", "sit_talk", "phone"]:
			var a := mlib.get_animation(an)
			for t in a.get_track_count():
				if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
					for k in a.track_get_key_count(t):
						var v: Vector3 = a.track_get_key_value(t, k)
						if absf(v.x) > 0.001 or absf(v.z) > 0.001:
							root_ok = false
		check(root_ok, "sin root motion (traslación X/Z de Hips bloqueada)")
	var person_nodes := []
	for k in MixamoPerson.MODELS.size():
		var mpn := MixamoPerson.new()
		add_child(mpn)
		mpn.setup({"model": k, "tint": k, "scale": 1.0, "phase": 0.0})
		person_nodes.append(mpn)
	for mpn: MixamoPerson in person_nodes:
		for sp in [0.0, 1.3, 5.5]:
			for _f in 6:
				mpn.animate(0.1, sp, true)
				await get_tree().process_frame
		var skm := mpn._skel
		check(skm != null and skm.get_bone_count() >= 65 and mpn._player.current_animation == "run", "MixamoPerson %d se anima (%s)" % [mpn.look["model"], mpn._player.current_animation])
		var hipm := skm.find_bone("mixamorig_Hips")
		var feet := skm.global_transform * skm.get_bone_global_pose(skm.find_bone("mixamorig_LeftFoot")).origin
		check(hipm >= 0 and feet.y > -0.05 and feet.y < 0.6, "MixamoPerson %d pisa el suelo (pie y=%.2f)" % [mpn.look["model"], feet.y])
	var down: MixamoPerson = person_nodes[0]
	down.animate(0.1, 0.0, false)
	check(down._downed and not down._player.is_playing(), "MixamoPerson atropellado se congela")
	down.animate(0.1, 1.2, true)
	check(not down._downed, "MixamoPerson se recupera")
	check(MixamoPerson.animated_count() <= MixamoPerson.MAX_ANIMATED, "máximo de peatones animados")
	for mpn in person_nodes:
		mpn.queue_free()
	var peds_test := Pedestrians.new()
	add_child(peds_test)
	peds_test.setup(4)
	check(peds_test.peds.size() == 4 and peds_test.peds[0]["node"] is MixamoPerson, "Pedestrians usa MixamoPerson")
	for _i in 10:
		await _physics(1)
	peds_test.queue_free()
	var phone_h := Humanoid.new()
	add_child(phone_h)
	phone_h.setup(GameData.character_look("mack"))
	phone_h.set_seated(true)
	phone_h.pose_idle_stance("phone")
	var psk := phone_h._skel
	var wrist := psk.get_bone_global_pose(psk.find_bone("r_hand")).origin
	var headp := psk.get_bone_global_pose(psk.find_bone("head")).origin
	check(phone_h._phone != null and phone_h._phone.visible, "pose phone: móvil visible en la mano")
	check(wrist.distance_to(headp + Vector3(0, 0.1, 0)) < 0.2, "pose phone: mano junto a la oreja (%.2f m)" % wrist.distance_to(headp + Vector3(0, 0.1, 0)))
	phone_h.set_seated(true)
	check(not phone_h._phone.visible, "el móvil se oculta al cambiar de pose")
	phone_h.queue_free()

	print("== Resultado: %d correctas, %d fallos" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
