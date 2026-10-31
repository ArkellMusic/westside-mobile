extends Node3D
## Pose "phone" de Humanoid con modelo riguado (Mack): mano junto a la oreja y móvil en la mano.
##   godot --path . res://tests/shot_phone_pose.tscn -- --out=/ruta [--id=mack]
var out := "/home/claude/shots"
var id := "mack"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out = String(a).substr(6)
		if String(a).begins_with("--id="):
			id = String(a).substr(5)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.34, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 150, 0)
	add_child(sun)
	var h := Humanoid.new()
	add_child(h)
	h.setup(GameData.character_look(id))
	h.pose_idle_stance("phone")
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	await get_tree().create_timer(0.5).timeout
	var views := {
		"front": [Vector3(0, 1.5, -1.0), Vector3(0, 1.45, 0)],
		"side": [Vector3(-1.2, 1.5, 0.0), Vector3(0, 1.45, 0)],
		"right": [Vector3(1.2, 1.5, 0.0), Vector3(0, 1.45, 0)],
		"full": [Vector3(0, 1.1, -3.2), Vector3(0, 0.95, 0)],
	}
	for k in views:
		var v: Array = views[k]
		cam.global_transform = Transform3D(Basis.looking_at(v[1] - v[0], Vector3.UP), v[0])
		cam.fov = 40 if k != "full" else 35
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/phonepose_%s_%s.png" % [out, id, k])
	get_tree().quit()
