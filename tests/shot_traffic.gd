extends Node3D

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(4.0).timeout
	main.set_process(false)
	main.title_menu.visible = false
	main.hud.set_letterbox(false)
	main.ui_layer.visible = false
	main.sky.apply_preset("golden", 0.0)
	main.rig.cinematic_shot(CameraRig.look_from(Vector3(-32, 4.5, 24), Vector3(-50, 3, 0)), CameraRig.look_from(Vector3(-32, 4.5, 24), Vector3(-50, 3, 0)), 30.0, 60.0, 60.0)
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_traffic_day.png")
	main.sky.resume_cycle()
	main.sky.set_time_of_day(23 * 60)
	await get_tree().create_timer(2.0).timeout
	main.sky.set_time_of_day(23 * 60)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_traffic_night.png")
	get_tree().quit()
