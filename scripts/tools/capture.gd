extends Node
## Herramienta de capturas: recorre el juego de forma automática (menú, cinemática,
## misión 01, conducción, mapa, pausa) y guarda PNG en out_dir. También sirve de
## prueba de humo: si algo se rompe por el camino, se ve en el registro.
## Uso: godot --path . -- --capture=/ruta/salida

var world: Node
var out_dir: String = "user://captures"
var _n: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_n += 1
	var path := "%s/%02d_%s.png" % [out_dir, _n, name]
	if img:
		img.save_png(path)
	print("CAPTURE ", path)


func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func wait_until(cond: Callable, timeout: float) -> bool:
	var e := 0.0
	while e < timeout:
		if cond.call():
			return true
		await get_tree().process_frame
		e += get_process_delta_time()
	print("CAPTURE timeout")
	return false


func press_interact() -> void:
	var cb: Callable = world._interactable.get("callback", Callable())
	if cb.is_valid():
		cb.call()


func _run() -> void:
	await wait(3.0)
	await shot("menu_principal")

	world.new_game()
	await wait(5.0)
	await shot("intro_desierto_noche")
	await wait(7.0)
	await shot("intro_autobus_llamada")
	await wait(16.0)
	await shot("intro_autobus_big_ray")
	await wait_until(func() -> bool: return world._photo_rect.visible and world._photo_rect.modulate.a > 0.9, 90.0)
	await shot("intro_foto_vieja")
	await wait_until(func() -> bool: return world.sky.current.get("energy", 0.0) > 0.8 and world.state == 0 + 1, 30.0)
	await wait(6.0)
	await shot("intro_puente_amanecer_titulo")

	await wait_until(func() -> bool: return world.runner.running, 40.0)
	await wait(2.5)
	await shot("m01_llegada_terminal")
	await wait_until(func() -> bool: return world._gameplay_on, 30.0)
	await wait(1.5)
	await shot("m01_a_pie_terminal")
	# Recoger la bolsa.
	world.player.place(world.resolve_point("bag") + Vector3(0, 0.2, -1.0), PI)
	await wait(1.0)
	press_interact()
	await wait(0.5)
	# Big Ray.
	world.player.place(world.actor("big_ray").global_position + Vector3(1.8, 0.2, 0.3), PI * 0.5)
	await wait(1.0)
	await shot("m01_buscando_a_big_ray")
	press_interact()
	await wait(2.0)
	await shot("m01_dialogo_big_ray")
	await wait_until(func() -> bool: return world._gameplay_on, 40.0)
	world.player.place(world.vehicle("ray_car").global_position + Vector3(0, 0.2, -2.6), 0.0)
	await wait(0.8)
	press_interact()
	await wait(14.0)
	await shot("m01_paseo_con_big_ray")
	await wait(20.0)
	await shot("m01_redline_kings_kingsley")
	await wait_until(func() -> bool: return world.current_vehicle == null and world._gameplay_on, 80.0)
	await wait(1.0)
	await shot("m01_veyra_mart")
	world.player.place(world.actor("okafor").global_position + Vector3(-1.6, 0.2, 0.4), PI * 0.5)
	await wait(0.8)
	press_interact()
	await wait(3.0)
	await shot("m01_okafor")
	await wait_until(func() -> bool: return world._gameplay_on and not world._interactable.is_empty(), 60.0)
	world.player.place(world.vehicle("ray_car").global_position + Vector3(0, 0.2, 2.6), PI)
	await wait(0.8)
	press_interact()
	await wait(1.0)
	# Conducir de verdad unos segundos (física del coche).
	Controls.touch_move = Vector2(0, 1)
	await wait(4.0)
	Controls.touch_move = Vector2(-0.4, 1)
	await wait(1.0)
	await shot("m01_conduciendo")
	Controls.touch_move = Vector2(0, 1)
	await wait(2.0)
	Controls.touch_move = Vector2.ZERO
	var car: Car = world.vehicle("ray_car")
	print("CAPTURE car speed km/h ", car.speed_kmh(), " pos ", car.global_position)
	world._place_car(car, CityLayout.landmark("coral_checkpoint") + Vector3(0, 0, 3), Vector3(1, 0, 0))
	await wait(1.0)
	world._place_car(car, CityLayout.landmark("mack_house_curb"), Vector3(1, 0, 0))
	await wait(2.0)
	await shot("m01_aparcado_casa")
	await wait_until(func() -> bool: return world.current_vehicle == null, 20.0)
	await wait(1.0)
	world.player.place(CityLayout.landmark("mack_door") + Vector3(0, 0.3, -1.0), PI)
	await wait(4.0)
	await shot("m01_puerta_vende")
	await wait(9.0)
	await shot("m01_panuelo_saints")
	await wait_until(func() -> bool: return not world.runner.running, 60.0)
	await wait(1.0)
	await shot("m01_mision_superada")

	# Mapa y pausa.
	world._open_map()
	await wait(1.0)
	await shot("mapa_westbrook")
	world.map_screen.open_tab(1)
	await wait(1.0)
	await shot("mapa_estado")
	world._close_map()
	world._open_pause()
	await wait(1.0)
	await shot("menu_pausa")
	world._close_pause()

	# Exploración libre: playa, muelle, Dre en su esquina, vista aérea.
	world.player.place(Vector3(-300, 0.5, 70), -PI * 0.5)
	world.rig.yaw = -PI * 0.5 + PI
	await wait(2.0)
	await shot("playa_muelle")
	world.player.place(CityLayout.landmark("dre_corner") + Vector3(2.5, 0.3, -2.5), PI * 0.75)
	await wait(2.0)
	await shot("dre_y_ghost_esquina")
	world.player.place(CityLayout.landmark("loco") + Vector3(-2.0, 0.3, 4.0), 0.0)
	await wait(2.0)
	await shot("vargas_auto_works_loco")
	world.rig.cinematic_shot(CameraRig.look_from(Vector3(-160, 120, 220), Vector3(0, 0, -40)), CameraRig.look_from(Vector3(-150, 118, 210), Vector3(0, 0, -40)), 3.0, 55.0, 55.0)
	await wait(1.5)
	await shot("vista_aerea_westbrook")
	print("CAPTURE done")
	get_tree().quit()
