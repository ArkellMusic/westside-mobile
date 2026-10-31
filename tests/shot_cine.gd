extends Node
## Capturas de cinemáticas (intro + misión 01) para revisar el encuadre con franjas.
##   godot --path . --resolution 1560x720 res://tests/shot_cine.tscn -- --out=/ruta

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


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	main.title_menu.visible = false
	main.new_game()
	var t := 0.0
	for at in [6.0, 14.0, 24.0, 36.0, 50.0, 64.0, 80.0, 100.0, 120.0]:
		await get_tree().create_timer(at - t).timeout
		t = at
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/cine_%03d.png" % [out, int(at)])
		print("SHOT ", at)
	get_tree().quit()
