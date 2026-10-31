extends Node
## Capturas del HUD, radar y GPS. Uso:
##   godot --path . --resolution 1560x720 res://tests/shot_hud.tscn -- --out=/ruta

var out := "/home/claude/shots"
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
	await get_tree().create_timer(t, true, false, true).timeout


func _run() -> void:
	await wait(2.0)
	GameState.new_game()
	main.title_menu.visible = false
	GameState.in_game = true
	main._start_play()
	main.hud.set_objective("")
	GameState.world_minutes = 11 * 60 + 17
	GameState.money = 550
	EventBus.money_changed.emit(550)
	main.hud.set_armor(100.0)
	main.wanted = 3
	main._wanted_timer = 999.0
	main.hud.set_wanted(3)
	# (a) HUD + radar a pie, de día
	main.player.place(Vector3(-42, 0.3, 12), PI * 0.75)
	main.rig.yaw = PI * 0.75 + PI
	await wait(3.5)
	await shot("a_hud_radar_a_pie")
	# (d) radar con ruta azul (a pie)
	main.gps.set_waypoint(CityLayout.landmark("vargas_garage"))
	await wait(1.5)
	await shot("d_radar_ruta_azul")
	main.gps.clear_waypoint()
	# (b) en coche con ruta de misión amarilla
	var car: Car = main.vehicle("free_sedan")
	main.player.place(car.global_position + Vector3(0, 0.3, -2.5), 0.0)
	await wait(0.5)
	await main.board(car, "driver")
	main.hud.set_objective("Ve al taller de Vargas")
	main.set_marker(CityLayout.landmark("vargas_garage"))
	Controls.enabled = true
	Controls.touch_move = Vector2(0, 0.7)
	await wait(4.0)
	await shot("b_coche_ruta_mision")
	Controls.touch_move = Vector2.ZERO
	# (c) mapa de pausa con waypoint y ruta azul
	main.gps.set_waypoint(Vector3(-150, 0, 100))
	main._open_map()
	main.map_screen._zoom = 1.0
	main.map_screen._center = Vector2(-20, 0)
	await wait(0.5)
	await shot("c_mapa_waypoint_ruta_azul")
	print("SHOT done")
	get_tree().quit()
