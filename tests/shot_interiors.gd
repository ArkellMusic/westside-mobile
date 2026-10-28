extends Node
## Capturas de los interiores y lugares nuevos (casa de Mack, taller Vargas, Pinta y
## Listo, comisaría, hospital). Uso:
##   godot --path . --resolution 1560x720 res://tests/shot_interiors.tscn -- --out=/ruta

var out := "/tmp/claude-0/shots_interiors"
var main: Node
var I: Interiors


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out = String(a).substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func cam(pos: Vector3, at: Vector3, fov: float = 70.0) -> void:
	main.rig.cinematic_shot(CameraRig.look_from(pos, at), CameraRig.look_from(pos, at), 100.0, fov, fov)
	await wait(0.5)


func local(i: int, p: Vector3) -> Vector3:
	return Interiors.BASE + Vector3(i * Interiors.SPACING, 0, 0) + p


func _run() -> void:
	await wait(2.0)
	GameState.new_game()
	main.title_menu.visible = false
	GameState.in_game = true
	main._start_play()
	main.hud.set_objective("")
	I = main.interiors
	GameState.world_minutes = 12 * 60
	await wait(1.0)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			only = String(a).substr(7)
	if only == "interiors":
		await _interiors()
		print("SHOT done")
		get_tree().quit()
		return
	if only == "flows":
		await cam(Vector3(70.5, 3.2, -111.3), Vector3(70.5, 1.2, -122), 75.0)
		await shot("06_pinta_y_listo_interior")
		main.rig.end_cinematic()
		await _flows()
		print("SHOT done")
		get_tree().quit()
		return
	# --- exteriores (cámara libre)
	await cam(Vector3(58, 3.0, -97), Vector3(70.5, 2.0, -113))
	await shot("01_pinta_y_listo_exterior")
	await cam(Vector3(106, 3.5, -97), Vector3(122, 3.0, -112))
	await shot("02_comisaria_exterior")
	await cam(Vector3(155, 5.0, -95), Vector3(176, 5.0, -112))
	await shot("03_hospital_exterior")
	await cam(Vector3(79, 2.2, -111), Vector3(87, 1.4, -121))
	await shot("04_taller_puerta_lateral")
	await cam(Vector3(-100, 4.0, 4), Vector3(-100, 2.0, 17), 65.0)
	await shot("05_casa_mack_puerta")
	# respray dentro, de día
	await cam(Vector3(70.5, 3.2, -111.3), Vector3(70.5, 1.2, -122), 75.0)
	await shot("06_pinta_y_listo_interior")
	# Aviso "Entrar" a pie ante la puerta de la comisaría
	main.rig.end_cinematic()
	main.player.place(Vector3(122.25, 0.3, -107.2), PI)
	main.rig.yaw = PI
	main.rig.global_position = main.player.global_position + Vector3.UP * 1.6
	await wait(1.5)
	print("INTERACT police: ", I.interaction(main.player.global_position, true).get("label", "-"))
	await shot("07_comisaria_prompt_entrar")
	await _interiors()
	await _flows()
	print("SHOT done")
	get_tree().quit()


func _interiors() -> void:
	main.rig.end_cinematic()
	var specs := {
		"house": [[Vector3(-5.2, 2.1, 4.6), Vector3(-1.0, 0.8, -1.5)], [Vector3(2.4, 2.3, 1.4), Vector3(4.8, 0.5, 3.4)], [Vector3(5.5, 2.4, -4.4), Vector3(-2.5, 0.8, -0.5)]],
		"garage": [[Vector3(-8.5, 3.2, 6.2), Vector3(2.0, 1.3, -2.0)], [Vector3(9.0, 3.0, 5.5), Vector3(-5.0, 1.0, -4.0)], [Vector3(0.0, 2.5, 6.0), Vector3(6.5, 0.8, -4.0)]],
		"police": [[Vector3(-7.0, 2.4, 4.4), Vector3(0.0, 1.0, -2.0)], [Vector3(0.0, 2.4, 4.4), Vector3(5.5, 1.2, -3.0)]],
		"hospital": [[Vector3(-7.0, 2.6, 5.4), Vector3(0.0, 1.0, -2.5)], [Vector3(1.0, 2.6, 5.2), Vector3(6.0, 0.8, -2.0)]],
	}
	var idx := 10
	for id in ["house", "garage", "police", "hospital"]:
		await I.enter(id)
		await wait(0.8)
		var i := I.place_index(id)
		print("INTERIOR ", id, " pos=", main.player.global_position, " loc=", I.current_name())
		print("INTERACT exit: ", I.interaction(main.player.global_position, true).get("label", "-"))
		await shot("%d_%s_tercera_persona" % [idx, id])
		var n := 0
		for pair in specs[id]:
			await cam(local(i, pair[0]), local(i, pair[1]))
			await shot("%d_%s_vista%d" % [idx, id, n])
			n += 1
		if id == "house":
			main.rig.end_cinematic()
			main.player.place(local(i, Vector3(3.2, 0.1, 2.6)), PI * 0.5)
			main.rig.global_position = main.player.global_position + Vector3.UP * 1.6
			await wait(1.0)
			print("INTERACT bed: ", I.interaction(main.player.global_position, true).get("label", "-"))
			main.player.place(local(i, Vector3(0, 0.1, 3.8)), 0.0)
			await wait(0.3)
			await shot("%d_house_salir_prompt" % idx)
		main.rig.end_cinematic()
		main.player.place(local(i, Vector3(float(I._places[i]["door_x"]), 0.1, I._places[i]["size"].y * 0.5 - 1.0)), 0.0)
		await wait(0.3)
		await I.leave()
		await wait(0.8)
		print("AFTER LEAVE ", id, " pos=", main.player.global_position, " inside=", I.inside)
		idx += 10


func _flows() -> void:
	# --- Pinta y Listo: flujo con coche
	GameState.money = 500
	var car: Car = main.vehicle("free_sedan")
	car.add_damage(70.0)
	main.wanted = 3
	main.hud.set_wanted(3)
	main.player.place(Vector3(70.5, 0.3, -104), 0.0)
	await wait(0.3)
	main._place_car(car, Vector3(70.5, 0, -113.5), Vector3(0, 0, -1))
	await main.board(car, "driver")
	await wait(0.2)
	main.rig.global_position = car.global_position + Vector3(0, 2, 6)
	await shot("60_respray_antes")
	print("RESPRAY before: damage=", car.damage, " color=", car.body_color, " wanted=", main.wanted, " money=", GameState.money)
	car.linear_velocity = Vector3.ZERO
	await wait(0.9)
	await shot("61_respray_negro")
	await wait(2.0)
	await shot("62_respray_despues")
	print("RESPRAY after: damage=", car.damage, " color=", car.body_color, " wanted=", main.wanted, " money=", GameState.money)
	# --- Wasted
	await main.leave_vehicle()
	main.player.place(Vector3(0, 0.3, 4), 0.0)
	GameState.health = 0.0
	await wait(1.0)
	await shot("70_wasted_negro")
	await wait(3.5)
	await shot("71_hospital_reaparicion")
	print("WASTED pos=", main.player.global_position, " health=", GameState.health, " money=", GameState.money)
