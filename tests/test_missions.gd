extends Node
## Pruebas de misiones, actividades y armas:
##   godot --headless --path . res://tests/test_missions.tscn
## 1) Las 80 misiones existen, cargan y solo usan pasos que el motor conoce.
## 2) Una misión de prueba recorre todos los tipos de paso nuevos de principio a fin.
## 3) Actividades, armería, armas nuevas y agacharse.

const KNOWN := ["phase", "checkpoint", "cutscene", "dialogue", "pickup", "talk", "goto", "drive_to", "enter_vehicle", "exit_vehicle",
	"scripted_drive", "move_actor_to_vehicle", "move_actor_from_vehicle", "prop", "toast", "reward", "complete", "wait", "scene", "call",
	"time", "give", "fight", "defend", "sneak", "chase", "collect", "steal", "lose_cops", "timed_drive"]

var main: Node
var _failed: int = 0
var _passed: int = 0
var _step: Dictionary = {}


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("  OK   ", what)
	else:
		_failed += 1
		printerr("  FALLO ", what)


func _ready() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _run() -> void:
	while not main.booted:
		await get_tree().process_frame
	await wait(1.0)
	print("== Las 80 misiones")
	var total_steps := 0
	var total_lines := 0
	var bad: Array = []
	for n in range(1, 81):
		var id := "m%02d" % n
		if not FileAccess.file_exists("res://data/missions/%s.json" % id):
			bad.append(id + " (falta)")
			continue
		var m := GameData.load_mission(id)
		if int(m.get("number", 0)) != n or (m.get("steps", []) as Array).size() < 20:
			bad.append(id + " (cabecera o pasos)")
			continue
		if n > 1:
			var sp: Vector3 = main.mission_point(m.get("start", "mack_door"), true)
			if not is_finite(sp.x) or not is_finite(sp.y):
				bad.append(id + " (inicio)")
		for s in m["steps"]:
			total_steps += 1
			if not KNOWN.has(String(s.get("type", ""))):
				bad.append("%s (paso %s)" % [id, s.get("type", "?")])
			total_lines += (s.get("lines", []) as Array).size()
			for k in ["at", "target"]:
				if s.has(k) and n > 1:
					var p: Vector3 = main.mission_point(s[k], true)
					if not is_finite(p.x) or p.y < -50.0:
						bad.append("%s (punto %s)" % [id, str(s[k])])
					elif typeof(s[k]) != TYPE_STRING and not main.CITY_BOUNDS.has_point(Vector2(p.x, p.z)) and StateLayout.height_at(p.x, p.z) < StateLayout.SEA + 0.5:
						bad.append("%s (punto en el agua %s)" % [id, str(s[k])])
	check(bad.is_empty(), "80 misiones cargan con pasos y puntos válidos%s" % ("" if bad.is_empty() else ": " + ", ".join(bad.slice(0, 8))))
	print("     pasos: %d · líneas de diálogo: %d" % [total_steps, total_lines])

	print("== Motor de misiones (misión de prueba)")
	GameState.new_game()
	main.title_menu.visible = false
	GameState.in_game = true
	main._reset_heat()
	main._start_play()
	await wait(0.5)
	var test := {"id": "m02", "number": 2, "title": "PRUEBA", "title_es": "Prueba", "start": "mack_door", "steps": [
		{"type": "phase", "n": 1},
		{"type": "scene", "at": "dre_corner", "cast": ["dre", "ghost", "Nina Cho"], "title_card": true, "lines": [
			{"speaker": "Dre", "en": "You came back.", "es": "Has vuelto.", "t": 2.0},
			{"speaker": "Nina Cho", "en": "He did.", "es": "Así es.", "t": 2.0},
			{"speaker": "Mack", "en": "I did.", "es": "Sí.", "t": 2.0}]},
		{"type": "call", "lines": [{"speaker": "K", "en": "Move.", "es": "Muévete.", "t": 2.0}]},
		{"type": "give", "ammo": 24},
		{"type": "goto", "target": [-40, 100], "objective": "Ve"},
		{"type": "collect", "at": [-40, 100], "count": 2, "label": "Coger", "objective": "Coge"},
		{"type": "fight", "at": [-40, 100], "count": 3, "objective": "Pelea", "faction": "redline_kings"},
		{"type": "sneak", "target": [0, 100], "guards": 2, "objective": "Entra", "label": "Entrar"},
		{"type": "chase", "at": [0, 100], "objective": "Atrapa"},
		{"type": "steal", "objective": "Coche"},
		{"type": "timed_drive", "target": [100, 100], "objective": "Corre"},
		{"type": "lose_cops", "stars": 2, "objective": "Huye"},
		{"type": "defend", "at": [100, 100], "count": 2, "waves": 2, "time": 3, "objective": "Aguanta"},
		{"type": "checkpoint"},
		{"type": "reward", "money": 500, "reputation": {"westbrook_saints": 3}, "toast": "ok"},
		{"type": "complete", "next_objective": "Siguiente"}]}
	main.runner.step_started.connect(func(_i: int, s: Dictionary) -> void: _step = s)
	var seen := {}
	var money0 := GameState.money
	var done := [false]
	main.runner.mission_finished.connect(func(_id: String) -> void: done[0] = true)
	main.runner.start_data(test, "m02")
	var t := 0.0
	var scene_cast_ok := false
	var hostiles_seen := 0
	while not done[0] and t < 140.0:
		await wait(0.2)
		t += 0.2
		var ty := String(_step.get("type", ""))
		seen[ty] = true
		match ty:
			"scene":
				if main.speaker_node("Nina Cho") != null and main.speaker_node("Dre") != null and (main.actors["dre"] as Node3D).visible:
					scene_cast_ok = true
				main.runner._skip = true
			"call":
				main.runner._skip = true
			"goto":
				main.player.place(main.mission_point(_step["target"], true) + Vector3.UP * 0.3, 0.0)
			"collect", "sneak":
				if not main._interactable.is_empty():
					main.player.place((main._interactable["pos"] as Vector3) + Vector3(0.5, 0.3, 0.5), 0.0)
					await wait(0.1)
					(main._interactable.get("callback", Callable()) as Callable).call()
			"fight", "defend":
				hostiles_seen = maxi(hostiles_seen, main.hostiles.alive("mission"))
				main.player.place(main.mission_point(_step["at"], true) + Vector3.UP * 0.3, 0.0)
				GameState.set_health(100.0)
				for u in main.hostiles.units:
					main.hostiles.hurt(u, 200.0, Vector3.FORWARD)
			"chase":
				main.player.place(main.mission_point(_step["at"], true) + Vector3.UP * 0.3, 0.0)
				for u in main.hostiles.units:
					if u.runner:
						main.player.place(u.global_position + Vector3(0.6, 0.2, 0), 0.0)
			"steal":
				if main.current_vehicle == null:
					await main.board(main.vehicle("free_sedan"), "driver")
			"timed_drive":
				if main.current_vehicle:
					main._place_car(main.current_vehicle, main.mission_point(_step["target"], false), Vector3(1, 0, 0))
			"lose_cops":
				if main.wanted > 0 and t > 1.0:
					main.police.clear()
					main.set_wanted(0)
	check(done[0], "la misión de prueba termina (%.0f s)" % t)
	for ty in ["scene", "call", "goto", "collect", "fight", "sneak", "chase", "steal", "timed_drive", "lose_cops", "defend"]:
		check(seen.has(ty), "paso «%s» ejecutado" % ty)
	check(scene_cast_ok, "la escena coloca a Dre y crea al secundario Nina Cho")
	check(hostiles_seen >= 2, "las peleas crean enemigos (%d)" % hostiles_seen)
	check(GameState.money == money0 + 500 and GameState.is_mission_completed(2), "recompensa y misión completada")
	check(main.hostiles.units.is_empty() or main.hostiles.alive("mission") == 0, "los enemigos de misión se retiran al acabar")
	if main.current_vehicle:
		await main.leave_vehicle()
	GameState.completed_missions = [1]
	main._offer_next_mission()
	check(String(main._next_mission.get("id", "")) == "m02", "tras la misión 1 se ofrece la 02 con su marcador")
	main.player.place((main._next_mission["pos"] as Vector3) + Vector3(0.5, 0.3, 0.5), 0.0)
	await wait(0.3)
	main._update_interaction()
	check(main.touch._interact_label == "Empezar misión", "en el marcador aparece «Empezar misión» (%s)" % main.touch._interact_label)

	print("== Enemigos")
	main.hostiles.clear()
	GameState.set_health(100.0)
	var pp: Vector3 = main.player.global_position
	var foe = main.hostiles.spawn(pp + Vector3(6, 0, 0), "t", true, true, false, 2)
	await wait(4.0)
	check(GameState.health < 100.0 or foe.global_position.distance_to(main.player.global_position) < 6.5, "un enemigo armado ataca al jugador (vida %.0f)" % GameState.health)
	var tgt: Dictionary = main.combat.find_target(main.player.global_position, (foe.global_position - main.player.global_position).normalized(), 50.0, 0.5)
	check(String(tgt.get("kind", "")) == "hostile", "el apuntado automático elige al enemigo")
	main.hostiles.hurt(foe, 100.0, Vector3.FORWARD)
	check(foe.dead and main.hostiles.alive("t") == 0, "los enemigos mueren")
	main.hostiles.clear()

	print("== Armas y armería")
	GameState.set_health(100.0)
	GameState.add_money(3000)
	GameState.weapons = ["fist", "pistol"]
	check(main.next_weapon_for_sale() == "shotgun", "la armería ofrece primero la escopeta")
	main.buy_weapon()
	main.buy_weapon()
	check(GameState.weapons.has("shotgun") and GameState.weapons.has("smg") and GameState.weapon == "smg", "se compran escopeta y subfusil")
	var a0 := GameState.ammo
	main.buy_ammo()
	check(GameState.ammo == mini(a0 + main.AMMO_PACK, GameState.MAX_AMMO), "se compra munición")
	main.combat.set_weapon("shotgun")
	check(main.combat.weapon_damage(5.0) > main.combat.weapon_damage(25.0) and is_equal_approx(main.combat.stat("ammo"), 3.0), "la escopeta pega más de cerca y gasta 3 balas")
	main.combat.cycle_weapon()
	check(GameState.weapon == "fist", "el botón Arma recorre solo las armas que tienes")
	main.player.crouching = true
	await wait(0.6)
	check(main.player.model.crouch > 0.8, "agacharse baja la postura")
	main.player.crouching = false
	var d := GameState.to_dict()
	GameState.weapons = ["fist", "pistol"]
	GameState.from_dict(d)
	check(GameState.weapons.has("smg"), "las armas se guardan")

	print("== Actividades")
	check(main.activities.radar_markers(Vector3(100, 0, -100)).size() >= 2, "las actividades salen en el radar")
	var d0: Dictionary = Activities.DEFS[1]
	main.player.place(main.activities.start_pos(d0) + Vector3(0.5, 0.3, 0.5), 0.0)
	await wait(0.3)
	var act: Dictionary = main.activities.interaction(main.player.global_position)
	check(String(act.get("label", "")) == "Reparto", "en su punto se puede empezar el reparto")
	var m1 := GameState.money
	main.activities.start("delivery")
	var tt := 0.0
	while main.activities.active != "" and tt < 30.0:
		await wait(0.2)
		tt += 0.2
		if main._marker_pos != Vector3.INF:
			main.player.place(main._marker_pos + Vector3(0.5, 0.3, 0.5), 0.0)
	check(main.activities.active == "" and GameState.money >= m1 + 240, "el reparto paga al completarlo (+$%d)" % (GameState.money - m1))
	m1 = GameState.money
	main.activities.start("turf")
	tt = 0.0
	while main.activities.active != "" and tt < 40.0:
		await wait(0.2)
		tt += 0.2
		GameState.set_health(100.0)
		if main._marker_pos != Vector3.INF:
			main.player.place(main._marker_pos + Vector3(0.5, 0.3, 0.5), 0.0)
		for u in main.hostiles.units:
			main.hostiles.hurt(u, 200.0, Vector3.FORWARD)
	check(main.activities.active == "" and GameState.money == m1 + 700, "la guerra de bandas paga al limpiar las tres oleadas")
	var h := Humanoid.new()
	add_child(h)
	h.setup(GameData.character_look("mack"))
	h.set_talking(true)
	for i in 30:
		h.animate(1.0 / 60.0, 0.0, true)
	var sk: Skeleton3D = h._skel
	var hand_y := sk.get_bone_global_pose(sk.find_bone("r_hand")).origin.y
	var hip_y := sk.get_bone_global_pose(sk.find_bone("hips")).origin.y
	check(hand_y > hip_y + 0.08, "al hablar levanta las manos para gesticular (mano %.2f, cadera %.2f)" % [hand_y, hip_y])
	h.queue_free()

	print("== Resultado misiones: %d correctas, %d fallos" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
