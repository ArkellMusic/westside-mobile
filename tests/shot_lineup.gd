extends Node3D
## Fila de los modelos Mixamo con una animación (para revisar escala, pies y texturas).
##   godot --path . res://tests/shot_lineup.tscn -- --out=/ruta --anim=idle|walk|run|phone|sit_talk
var out := "/home/claude/shots"
var anim := "idle"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out = String(a).substr(6)
		if String(a).begins_with("--anim="):
			anim = String(a).substr(7)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 10)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var persons := []
	for k in MixamoPerson.MODELS.size():
		var m := MixamoPerson.new()
		add_child(m)
		m.setup({"model": k, "tint": 0, "scale": 1.0, "phase": 0.0})
		m.position = Vector3(-6.25 + 2.5 * k, 0, 0)
		persons.append(m)
		if anim == "phone":
			m.pose_idle_stance("phone")
		elif anim == "sit_talk":
			m.set_seated(true)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, -9.0)
	cam.rotation.y = PI
	cam.fov = 32
	add_child(cam)
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	var speed := {"idle": 0.0, "walk": 1.3, "run": 5.5, "phone": 0.0, "sit_talk": 0.0}[anim] as float
	for i in 30:
		for m in persons:
			(m as MixamoPerson).animate(0.05, speed, true)
		await get_tree().create_timer(0.05).timeout
	# alturas de pies y cabeza respecto al suelo
	for m in persons:
		var sk: Skeleton3D = (m as MixamoPerson)._skel
		var lf := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftToeBase")).origin
		var rf := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_RightToeBase")).origin
		var hd := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_HeadTop_End")).origin
		print("MODEL ", (m as MixamoPerson).look["model"], " toeL.y=", snappedf(lf.y, 0.001), " toeR.y=", snappedf(rf.y, 0.001), " head.y=", snappedf(hd.y, 0.001))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/lineup_%s.png" % [out, anim])
	get_tree().quit()
