extends Node
## Capturas de las funciones nuevas: semáforos, mobiliario, ciclo día/noche,
## conducción con choque y atropello. Uso:
##   godot --path . --resolution 1560x720 res://tests/shot_features.tscn -- --out=/ruta

var out := "/tmp/claude-0/shots_features"
var main: Node


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


func _run() -> void:
	await wait(2.0)
	GameState.new_game()
	main.title_menu.visible = false
	GameState.in_game = true
	main._start_play()
	main.hud.set_objective("")
	GameState.world_minutes = 11 * 60
	# 1. Cruce con semáforos a mediodía, a pie.
	main.player.place(Vector3(-42, 0.3, 12), PI * 0.75)
	main.rig.yaw = PI * 0.75 + PI
	await wait(3.0)
	await shot("01_cruce_semaforos_dia")
	# 2. Paseo marítimo con farolas.
	main.player.place(Vector3(-246, 0.3, 30), 0.0)
	main.rig.yaw = PI
	await wait(2.0)
	await shot("02_paseo_maritimo")
	# 3. Conduciendo con tráfico.
	var car: Car = main.vehicle("free_sedan")
	main.player.place(car.global_position + Vector3(0, 0.3, -2.5), 0.0)
	await wait(0.5)
	await main.board(car, "driver")
	Controls.enabled = true
	Controls.touch_move = Vector2(0, 1)
	await wait(4.0)
	await shot("03_conduciendo_trafico")
	# 4. Choque contra una farola o pared.
	Controls.touch_move = Vector2(0.9, 1)
	await wait(3.0)
	await shot("04_tras_el_choque")
	Controls.touch_move = Vector2.ZERO
	print("SHOT damage ", car.damage)
	# 5. Atardecer.
	GameState.world_minutes = 19 * 60 + 10
	await wait(3.0)
	await shot("05_atardecer")
	# 6. Noche con farolas encendidas.
	GameState.world_minutes = 22 * 60 + 30
	main.radio.exit_vehicle()
	await wait(3.0)
	await shot("06_noche_farolas")
	# 7. Vista aérea de noche.
	main.rig.cinematic_shot(CameraRig.look_from(Vector3(-160, 90, 160), Vector3(0, 0, -20)), CameraRig.look_from(Vector3(-150, 88, 150), Vector3(0, 0, -20)), 3.0)
	await wait(2.0)
	await shot("07_aerea_noche")
	print("SHOT done")
	get_tree().quit()
