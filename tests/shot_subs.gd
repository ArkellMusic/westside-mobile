extends Node
## Captura rápida: subtítulo con franjas de cine.
var out := "/home/claude/shots"
var main: Node

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out = String(a).substr(6)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	GameState.new_game()
	main.title_menu.visible = false
	GameState.in_game = true
	main._start_play()
	main.hud.set_letterbox(true)
	await get_tree().create_timer(2.0).timeout
	main.hud.show_subtitle("Big Ray", "Mack... it's Ray. You need to come home. Something's wrong in Westbrook.", 10.0)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/subs.png")
	get_tree().quit()
