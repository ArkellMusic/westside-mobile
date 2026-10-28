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

	print("== Resultado: %d correctas, %d fallos" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
