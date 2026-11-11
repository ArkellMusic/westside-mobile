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
	# Un segundo peatón detrás del jugador hará de testigo.
	var wit: Dictionary = P.peds[2]
	(wit["node"] as Node3D).position = player.global_position - along * 12.0
	wit["speed"] = 0.0
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
		# Testigo llamando y Mack con otra ropa.
		main.hud._toast_panel.visible = false
		var wn: Node3D = wit["node"]
		var wp: Vector3 = wn.global_position
		var wfrom := wp + side * 2.2 + along * 3.0 + Vector3.UP * 1.6
		main.rig.cinematic_shot(CameraRig.look_from(wfrom, wp + Vector3.UP * 1.3), CameraRig.look_from(wfrom, wp + Vector3.UP * 1.3), 999.0, 45.0, 45.0)
		for i in 30:
			wn.call("animate", 0.05, 0.0, true)
		await wait(0.3)
		await shot("crimen_testigo_llamando")
		main.combat._aim_t = 0.0
		for oi in [1, 3]:
			main.set_outfit(oi)
			from = pp - side * 2.4 + along * 2.2 + Vector3.UP * 1.3
			main.rig.cinematic_shot(CameraRig.look_from(from, pp + Vector3.UP * 1.0), CameraRig.look_from(from, pp + Vector3.UP * 1.0), 999.0, 45.0, 45.0)
			await wait(0.3)
			await shot("crimen_ropa_%d" % oi)
		main.set_outfit(0)
		main.rig.end_cinematic()
		if "--only-pose" in OS.get_cmdline_user_args():
			get_tree().quit()
			return
	check(GameState.ammo == ammo_before - 1, "un disparo gasta una bala")
	check(P.peds.size() == peds_before - 1 and P.downed.size() >= 1, "el peatón apuntado cae")
	check(main.wanted == 0, "sin agentes delante no hay estrellas al instante")
	check(float(wit.get("calling", 0.0)) > 0.0, "un testigo saca el móvil y llama")
	check((wit["node"] as Node3D).get_node_or_null("Testigo") != null, "el testigo lleva el aviso sobre la cabeza")
	var far_ped: Dictionary = P.peds[P.peds.size() - 1]
	P.panic((far_ped["node"] as Node3D).global_position, 3.0)
	check(float(far_ped.get("panic", 0.0)) > 0.0, "los peatones cercanos a un disparo huyen")
	check(player.model.overlay.has("arm"), "pose de apuntar aplicada")

	print("== Testigos y descripción")
	if out == "":
		await wait(1.5)
		var wmp := wit["node"] as MixamoPerson
		check(wmp._player.current_animation == "phone" and wmp._player.is_playing(), "el testigo reproduce la animación del móvil")
		await wait(CrimeSystem.CALL_TIME)
		check(main.wanted >= 1, "cuando el testigo cuelga llegan las estrellas (%d)" % main.wanted)
		check(int(main.crime.description.get("outfit", -1)) == 0 and main.crime.matches(), "la descripción lleva la ropa del jugador")
		check(is_equal_approx(main.crime.recognition_range(), CrimeSystem.RANGE_MATCH_FOOT), "si encajas te reconocen de lejos")
		main.set_outfit(2)
		check(not main.crime.matches() and is_equal_approx(main.crime.recognition_range(), CrimeSystem.RANGE_NO_MATCH_FOOT), "con otra ropa solo te reconocen de cerca")
		# Un agente a 15 m con visión directa no reconoce al jugador cambiado de ropa...
		main.police.clear()
		main.police._spawn_cop(player.global_position + along * 15.0)
		await wait(1.5)
		check(main.police.sees_player_now() and not main.police.any_seen, "un agente a 15 m no reconoce al jugador con otra ropa")
		check(main.hud._searching, "HUD en modo búsqueda (estrellas grises)")
		# ...y sí en cuanto vuelve a vestir como en la descripción.
		main.set_outfit(0)
		await wait(1.0)
		check(main.police.any_seen, "con la ropa de la descripción lo reconoce a 15 m")
		main.police.clear()
		# Testigo silenciado: no hay aviso.
		main.set_wanted(0)
		main.crime._loud_cd = 0.0
		var wit2: Dictionary = P.peds[3]
		(wit2["node"] as Node3D).position = player.global_position - along * 10.0
		wit2["speed"] = 0.0
		for q in P.peds:
			q["calling"] = 0.0
		var n_call: int = main.crime.commit(player.global_position, 1)
		var silenced_id: int = main.crime._crime_n
		check(n_call >= 1 and float(wit2.get("calling", 0.0)) > 0.0, "un delito con gente cerca tiene testigos (%d)" % n_call)
		for i in range(P.peds.size() - 1, -1, -1):
			if float(P.peds[i].get("calling", 0.0)) > 0.0:
				P.strike(i, along, 2.0, 1.2)
		await wait(CrimeSystem.CALL_TIME + 2.0)
		check(not main.crime._reported_ids.has(silenced_id), "un testigo tumbado antes de colgar no da el aviso")
		main.police.clear()
		main.set_wanted(0)
		for q in P.peds:
			q["calling"] = 0.0

	print("== Policía")
	main.crime.last_known = player.global_position
	main.crime.description = main.crime.current_look()
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
	var wit3: Dictionary = P.peds[4]
	(wit3["node"] as Node3D).position = player.global_position + left * 8.0
	wit3["speed"] = 0.0
	wit3["calling"] = 0.0
	var peds_n := P.peds.size()
	await tap("interact")
	await wait(0.6)
	check(main.current_vehicle != null and String(main.current_vehicle.vehicle_id).begins_with("stolen_"), "el jugador conduce el coche robado")
	check(main.traffic.cars.size() == n_traffic, "el tráfico repone el coche (%d)" % main.traffic.cars.size())
	check(P.peds.size() == peds_n + 1, "el conductor sale corriendo")
	var caller_found := false
	for q in P.peds:
		if float(q.get("calling", 0.0)) > 0.0 and String((q["report"]["look"] as Dictionary)["car"]).begins_with("stolen_"):
			caller_found = true
	check(caller_found or main.wanted >= 1, "el testigo del robo describe el coche robado")
	# A una calle despejada para que el tráfico no lo bloquee.
	main._place_car(main.current_vehicle, CityLayout.landmark("coral_checkpoint") + Vector3(0, 0, 3), Vector3(1, 0, 0))
	await wait(0.5)
	Controls.touch_move = Vector2(0, 1)
	await wait(2.5)
	Controls.touch_move = Vector2.ZERO
	check(main.current_vehicle.speed_kmh() > 8.0, "el coche robado se conduce (%.0f km/h)" % main.current_vehicle.speed_kmh())
	await shot("combate_coche_robado")

	print("== Persecución en coche")
	main.police.clear()
	main.crime.description = main.crime.current_look()
	main.crime.last_known = main.current_vehicle.global_position
	main.set_wanted(2)
	main.police._known_t = 3.0
	var tq := 0.0
	while tq < 8.0 and main.police.pursuits.is_empty():
		main.police._known_t = 3.0
		await wait(0.25)
		tq += 0.25
	check(main.police.pursuits.size() >= 1, "sale una patrulla en persecución cuando huyes en coche (%.1f s)" % tq)
	if not main.police.pursuits.is_empty():
		var pc: Car = main.police.pursuits[0]["car"]
		var pd0 := pc.global_position.distance_to(main.current_vehicle.global_position)
		for i in 24:
			main.police._known_t = 3.0
			main.refresh_wanted()
			await wait(0.25)
		var pd1 := pc.global_position.distance_to(main.current_vehicle.global_position)
		check(pd1 < pd0 - 15.0, "la patrulla conduce hacia el jugador (%.0f m -> %.0f m)" % [pd0, pd1])
		check(not main.vehicles.values().has(pc), "las patrullas en persecución no se pueden robar")
	main.police.clear()
	main.set_wanted(0)

	print("== Tiendas")
	if main.current_vehicle:
		await main.leave_vehicle()
	main.police.clear()
	main.set_wanted(0)
	var I: Interiors = main.interiors
	check(I.place_index("clothes") >= 0 and I.place_index("barber") >= 0 and I.place_index("tattoo") >= 0, "hay tienda de ropa, barbería y estudio de tatuajes")
	check(I._shop_fronts.size() == 4 and I.place_index("guns") >= 0 and I.radar_markers(I._shop_fronts[0]["pos"]).size() >= 1, "las tiendas tienen escaparate y marca en el radar")
	check(main.city._houses.size() > 20 and main.city.get_node_or_null("HouseDetails") != null, "chalets con tejado (%d casas y garajes)" % main.city._houses.size())
	GameState.add_money(500)
	GameState.owned_outfits = [0]
	main.set_outfit(0)
	var shop_door: Vector3 = I._places[I.place_index("clothes")]["enter"]
	player.place(shop_door + Vector3.UP * 0.3, 0.0)
	await physics(4)
	main._update_interaction()
	check(main.touch._interact_label == "Entrar", "se puede entrar en la tienda de ropa (%s)" % main.touch._interact_label)
	await I.enter("clothes")
	await wait(0.6)
	check(I.inside == I.place_index("clothes"), "dentro de Veyra Threads")
	var so: Vector3 = I._origin(I.inside)
	player.place(so + Vector3(0, 0.2, -0.6), 0.0)
	await physics(4)
	var act: Dictionary = I.interaction(player.global_position, true)
	check(String(act.get("label", "")).begins_with("Comprar ropa"), "el mostrador ofrece comprar ropa (%s)" % act.get("label", ""))
	var m0 := GameState.money
	main.buy_outfit()
	check(GameState.money == m0 - main.OUTFIT_PRICE and GameState.outfit == 1 and GameState.owned_outfits.has(1), "comprar ropa cobra $%d y te pone el conjunto nuevo" % main.OUTFIT_PRICE)
	main.change_outfit()
	check(GameState.outfit == 0, "el armario alterna entre los conjuntos comprados")
	await I.leave()
	await wait(0.6)
	m0 = GameState.money
	main.buy_head_style()
	check(GameState.head_style == 1 and GameState.money == m0 - main.BARBER_PRICE, "la barbería cambia el tinte y cobra")
	main.crime.description = {"outfit": GameState.outfit, "head": 0, "car": "", "car_color": Color.BLACK, "car_name": ""}
	check(not main.crime.matches(), "con otro tinte ya no encajas con la descripción policial")
	var rep0 := int(GameState.reputation.get("westbrook_saints", 0))
	main.buy_tattoo()
	check(GameState.tattoos == 1 and int(GameState.reputation.get("westbrook_saints", 0)) == rep0 + 4, "un tatuaje da respeto con los Saints")
	main.crime.clear()
	check(main.sky.cloud_mat != null and main.sky.sky.sky_material == main.sky.cloud_mat, "cielo con nubes volumétricas, sol y luna activo")

	print("== Guardado")
	GameState.ammo = 33
	GameState.weapon = "pistol"
	var d := GameState.to_dict()
	GameState.ammo = 0
	GameState.weapon = "fist"
	GameState.from_dict(d)
	check(GameState.ammo == 33 and GameState.weapon == "pistol", "arma y munición se guardan")
	GameState.outfit = 3
	d = GameState.to_dict()
	GameState.outfit = 0
	GameState.from_dict(d)
	check(GameState.outfit == 3, "la ropa se guarda")
	check(Sfx.stream("shot").data.size() > 1000 and Sfx.stream("siren").loop_mode == AudioStreamWAV.LOOP_FORWARD, "efectos de sonido generados")

	print("== Resultado combate: %d correctas, %d fallos" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
