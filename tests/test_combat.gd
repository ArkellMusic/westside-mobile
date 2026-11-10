extends Node
## Prueba del combate, la policía y el robo de coches sobre el mundo real:
##   godot --headless --path . res://tests/test_combat.tscn
## Con ventana y --out=/ruta guarda además capturas:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##     --resolution 1560x720 res://tests/test_combat.tscn -- --out=/ruta

var out := ""
var main: Node
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
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out = String(a).substr(6)
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)


func tap(action: String) -> void:
	Controls.press(action, true)
	await get_tree().process_frame
	await get_tree().process_frame
	Controls.press(action, false)


func _run() -> void:
	await wait(1.0)
	GameState.new_game()
	main.title_menu.visible = false
	GameState.in_game = true
	main._reset_heat()
	main._start_play()
	GameState.world_minutes = 11 * 60 + 17
	main.sky.apply_preset("morning", 0.0)
	await wait(0.5)
	var P: Pedestrians = main.pedestrians
	var player: Player = main.player

	print("== Armas")
	check(GameState.weapon == "fist" and GameState.ammo == GameState.START_AMMO, "empieza con puños y %d balas" % GameState.START_AMMO)
	await tap("weapon")
	await physics(3)
	check(GameState.weapon == "pistol" and main.hud._weapon_kind == "pistol", "el botón Arma cambia a pistola (HUD incluido)")
	check(player.model._gun != null and player.model._gun.visible, "pistola visible en la mano de Mack")

	print("== Disparo a un peatón")
	# Peatón a 9 m delante de la cámara, en una calle despejada.
	var ped: Dictionary = P.peds[0]
	var h: Node3D = ped["node"]
	var base: Vector3 = h.global_position
	var c0: Vector2 = ped["corners"][ped["next"]]
	var along := Vector3(c0.x - base.x, 0, c0.y - base.z).normalized()
	player.place(base - along * 9.0 + Vector3.UP * 0.3, 0.0)
	main.rig.yaw = atan2(-along.x, -along.z)
	main.rig.pitch = -0.12
	await physics(20)
	var peds_before := P.peds.size()
	var ammo_before := GameState.ammo
	await tap("attack")
	await physics(4)
	await shot("combate_disparo")
	if out != "":
		main.combat._aim_t = 99.0
		var pp: Vector3 = player.global_position
		var side := Vector3(-along.z, 0, along.x)
		var from := pp + side * 2.6 + along * 1.2 + Vector3.UP * 1.5
		main.rig.cinematic_shot(CameraRig.look_from(from, pp + Vector3.UP * 1.15), CameraRig.look_from(from, pp + Vector3.UP * 1.15), 999.0, 45.0, 45.0)
		await wait(0.3)
		await shot("combate_pose_apuntar")
		main.rig.end_cinematic()
		main.combat._aim_t = 1.0
		if "--only-pose" in OS.get_cmdline_user_args():
			get_tree().quit()
			return
	check(GameState.ammo == ammo_before - 1, "un disparo gasta una bala")
	check(P.peds.size() == peds_before - 1 and P.downed.size() >= 1, "el peatón apuntado cae")
	check(main.wanted >= 1, "disparar en la calle da estrellas (%d)" % main.wanted)
	var far_ped: Dictionary = P.peds[P.peds.size() - 1]
	P.panic((far_ped["node"] as Node3D).global_position, 3.0)
	check(float(far_ped.get("panic", 0.0)) > 0.0, "los peatones cercanos a un disparo huyen")
	check(player.model.overlay.has("arm"), "pose de apuntar aplicada")

	print("== Policía")
	main.set_wanted(1)
	var t := 0.0
	while t < 8.0 and main.police.alive_count() < 2:
		await wait(0.25)
		t += 0.25
	check(main.police.alive_count() >= 2, "llegan agentes con 1 estrella (%d en %.1f s)" % [main.police.alive_count(), t])
	check(main.police.patrols.size() >= 1, "con coche patrulla aparcado")
	var cop = main.police.cops[0]
	var d0: float = cop.global_position.distance_to(player.global_position)
	await wait(3.0)
	var d1: float = cop.global_position.distance_to(player.global_position)
	check(d1 < d0 - 4.0, "el agente corre hacia el jugador (%.0f m -> %.0f m)" % [d0, d1])
	# Con 2 estrellas disparan: el agente se coloca a la vista, a 8 m.
	main.set_wanted(2)
	for c in main.police.cops:
		c.global_position = player.global_position + along * (8.0 + 1.5 * main.police.cops.find(c)) + Vector3.UP * 0.3
		c.see_cd = 0.0
		c.shoot_cd = 0.2
	main.rig.yaw = atan2(-along.x, -along.z)
	GameState.set_health(GameState.MAX_HEALTH)
	t = 0.0
	while t < 12.0 and GameState.health >= GameState.MAX_HEALTH:
		await wait(0.25)
		t += 0.25
		main.refresh_wanted()
		if t == 1.0:
			await shot("combate_policia")
	check(GameState.health < GameState.MAX_HEALTH, "los agentes hieren al jugador con 2 estrellas (vida %.0f tras %.1f s)" % [GameState.health, t])
	check(main.police.any_seen, "la policía ve al jugador (las estrellas no bajan)")
	# Dos balas tumban a un agente y suben la búsqueda.
	GameState.set_health(GameState.MAX_HEALTH)
	var alive_before: int = main.police.alive_count()
	var ammo2 := GameState.ammo
	for i in 3:
		await tap("attack")
		await wait(0.4)
	await shot("combate_agente_caido")
	check(main.police.alive_count() < alive_before or main.police.cops.any(func(c) -> bool: return c.health < 60.0), "las balas del jugador dañan a los agentes")
	check(main.wanted >= 2, "atacar a un agente mantiene o sube la búsqueda (%d)" % main.wanted)
	check(GameState.ammo != ammo2, "la munición cambia (gasto y recogida)")

	print("== Detención")
	main.police.clear()
	main.set_wanted(1)
	GameState.set_health(GameState.MAX_HEALTH)
	main.police._spawn_cop(player.global_position + along * 1.2)
	var money := GameState.money
	t = 0.0
	while t < 8.0 and main.wanted > 0:
		await wait(0.25)
		t += 0.25
	await wait(3.5)
	check(main.wanted == 0 and GameState.money == money - Interiors.BUST_FINE, "DETENIDO: multa de $%d y sin estrellas" % Interiors.BUST_FINE)
	check(GameState.ammo == 0 and GameState.weapon == "fist", "munición confiscada")
	var station: Transform3D = main.interiors.police_respawn_point()
	check(player.global_position.distance_to(station.origin) < 3.0, "reaparece en la comisaría")

	print("== Puñetazo")
	ped = P.peds[1]
	h = ped["node"]
	player.place(h.global_position + Vector3(0, 0.2, 1.1), 0.0)
	main.rig.yaw = 0.0
	await physics(3)
	player.place(h.global_position + Vector3(0, 0.2, 1.1), 0.0)
	peds_before = P.peds.size()
	await tap("attack")
	await wait(0.2)
	await shot("combate_punetazo")
	await wait(0.2)
	check(P.peds.size() == peds_before - 1, "un puñetazo tumba al peatón de delante")
	check(main.wanted >= 1, "pegar a un peatón da una estrella")

	print("== Robo de coche")
	main.police.clear()
	main.set_wanted(0)
	var tc = main.traffic.cars[0]
	var n_traffic: int = main.traffic.cars.size()
	var left := Vector3(tc.heading.z, 0, -tc.heading.x)
	player.place(tc.global_position + left * 2.4 + Vector3.UP * 0.3, 0.0)
	tc.speed = 0.0
	await physics(2)
	player.place(tc.global_position + left * 2.4 + Vector3.UP * 0.3, 0.0)
	await physics(2)
	main._update_interaction()
	check(main.touch._interact_label == "Robar", "junto a un coche del tráfico aparece «Robar» (%s)" % main.touch._interact_label)
	var peds_n := P.peds.size()
	await tap("interact")
	await wait(0.6)
	check(main.current_vehicle != null and String(main.current_vehicle.vehicle_id).begins_with("stolen_"), "el jugador conduce el coche robado")
	check(main.traffic.cars.size() == n_traffic, "el tráfico repone el coche (%d)" % main.traffic.cars.size())
	check(P.peds.size() == peds_n + 1, "el conductor sale corriendo")
	check(main.wanted >= 1, "robar un coche da una estrella")
	Controls.touch_move = Vector2(0, 1)
	await wait(2.5)
	Controls.touch_move = Vector2.ZERO
	check(main.current_vehicle.speed_kmh() > 8.0, "el coche robado se conduce (%.0f km/h)" % main.current_vehicle.speed_kmh())
	await shot("combate_coche_robado")

	print("== Guardado")
	GameState.ammo = 33
	GameState.weapon = "pistol"
	var d := GameState.to_dict()
	GameState.ammo = 0
	GameState.weapon = "fist"
	GameState.from_dict(d)
	check(GameState.ammo == 33 and GameState.weapon == "pistol", "arma y munición se guardan")
	check(Sfx.stream("shot").data.size() > 1000 and Sfx.stream("siren").loop_mode == AudioStreamWAV.LOOP_FORWARD, "efectos de sonido generados")

	print("== Resultado combate: %d correctas, %d fallos" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
