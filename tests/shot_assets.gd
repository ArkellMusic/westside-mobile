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
	await wait(1.2)


func _run() -> void:
	await wait(2.0)
	GameState.new_game()
	main.title_menu.visible = false
	GameState.in_game = true
	main._start_play()
	main.hud.set_objective("")
	GameState.world_minutes = 12 * 60
	await wait(1.0)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			only = String(a).substr(7)
	var jobs := {
		"police": [Vector3(128, 3.0, -92), Vector3(119, 1.2, -108), 70.0],
		"police_npc": [Vector3(119.8, 1.7, -103.5), Vector3(121.5, 1.3, -107.5), 60.0],
		"hospital": [Vector3(250, 9.0, -95), Vector3(205, 2.0, -125), 75.0],
		"hospital_back": [Vector3(240, 14.0, -205), Vector3(200, 1.5, -178), 70.0],
		"hospital_doc": [Vector3(196.5, 1.8, -124.5), Vector3(197.0, 1.3, -128.5), 55.0],
		"prison": [Vector3(1960, 18.0, 90), Vector3(2000, 4.0, 165), 70.0],
		"parking": [Vector3(-90, 7.0, -96), Vector3(-103, 1.0, -125), 70.0],
		"subway": [Vector3(-48, 3.5, -8), Vector3(-59, 1.2, -20), 65.0],
		"cuda": [Vector3(-168, 2.0, -9), Vector3(-180, 0.8, -5), 55.0],
	}
	for k in jobs:
		if only != "" and only != k:
			continue
		var j: Array = jobs[k]
		main.player.place(j[1] + Vector3(0, 0.5, 0), 0.0)
		await cam(j[0], j[1], j[2])
		await shot("assets_" + k)
	if only == "" or only == "police_in" or only == "interiors":
		await main.interiors.enter("police")
		await wait(1.0)
		var o: Vector3 = main.interiors._origin(main.interiors.place_index("police"))
		await cam(o + Vector3(-1.0, 2.0, 3.8), o + Vector3(-3.0, 1.0, -2.0), 75.0)
		await shot("assets_police_interior")
		await cam(o + Vector3(-4.0, 1.6, 3.0), o + Vector3(-5.2, 1.1, 0.6), 55.0)
		await shot("assets_police_interior_cops")
		main.rig.end_cinematic()
		main.interiors.leave()
		await wait(1.5)
	if only == "" or only == "hospital_in" or only == "interiors":
		await main.interiors.enter("hospital")
		await wait(1.0)
		var o3: Vector3 = main.interiors._origin(main.interiors.place_index("hospital"))
		await cam(o3 + Vector3(-0.5, 1.9, 4.8), o3 + Vector3(-2.2, 1.2, 1.2), 65.0)
		await shot("assets_hospital_interior")
		main.rig.end_cinematic()
		main.interiors.leave()
		await wait(1.5)
	if only == "" or only == "subway_in":
		await main.interiors.enter("subway")
		await wait(1.0)
		var o2: Vector3 = main.interiors._origin(main.interiors.place_index("subway"))
		await cam(o2 + Vector3(0, 1.7, 1.5), o2 + Vector3(0, 1.0, 12), 80.0)
		await shot("assets_subway_interior")
		main.rig.end_cinematic()
		main.interiors.leave()
		await wait(1.5)
	print("SHOT done")
	get_tree().quit()
