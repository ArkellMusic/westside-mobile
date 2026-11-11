extends Node3D
## Fotogramas de la animación por código de Mack (lateral y frontal):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##     --resolution 1600x900 res://tests/shot_anim.tscn -- --out=/ruta

var out := "/tmp/anim"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out = String(a).substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.45, 0.47)
	pm.material = fm
	floor_mi.mesh = pm
	add_child(floor_mi)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.6
	add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), Vector3(0, 1.75, 20))
	cam.current = true
	_run.call_deferred()


## Ocho figuras: 4 fases de andar (perfil), 2 de correr (perfil), reposo y hablando (de frente).
func _run() -> void:
	var defs := [
		["andar", 1.5, 0.0, PI * 0.5], ["andar", 1.5, 0.25, PI * 0.5], ["andar", 1.5, 0.5, PI * 0.5], ["andar", 1.5, 0.75, PI * 0.5],
		["correr", 6.5, 0.1, PI * 0.5], ["correr", 6.5, 0.6, PI * 0.5], ["reposo", 0.0, 0.0, 0.0], ["hablar", 0.0, 0.0, 0.0],
	]
	var figs: Array = []
	for i in defs.size():
		var h := Humanoid.new()
		add_child(h)
		h.setup(GameData.character_look("mack"))
		h.position = Vector3(-2.9 + 1.95 * (i % 4), 2.15 if i < 4 else 0.0, 0)
		h.rotation.y = float(defs[i][3])
		figs.append(h)
	for i in defs.size():
		var h: Humanoid = figs[i]
		var sp := float(defs[i][1])
		if String(defs[i][0]) == "hablar":
			h.set_talking(true)
		# Avanza la animación hasta la fase pedida del ciclo.
		for k in 90:
			h.animate(1.0 / 60.0, sp, true)
		if sp > 0.0:
			var want := float(defs[i][2]) * TAU
			var guard := 0
			while absf(wrapf(h._phase - want, -PI, PI)) > 0.12 and guard < 400:
				h.animate(1.0 / 60.0, sp, true)
				guard += 1
	for k in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/anim.png")
	print("SHOT anim")
	get_tree().quit()
