extends Node
## Capturas de calidad gráfica: calle de día, atardecer, noche con farolas y
## faros, primer plano de coche y cinemática con profundidad de campo. Uso:
##   godot --path . --resolution 1560x720 res://tests/shot_gfx.tscn -- --out=/ruta --prefix=gfx_after_ [--quality=high]

var out := "/home/claude/shots"
var prefix := "gfx_"
var main: Node
var no_sdfgi := false
var no_volfog := false
var no_fsr := false
var only: PackedStringArray = []  # p. ej. --only=3,5 (para ir por partes si falta RAM)
var no_probe := false  # lavapipe se queda sin RAM con la sonda + SDFGI en el contenedor


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out = s.substr(6)
		elif s.begins_with("--prefix="):
			prefix = s.substr(9)
		elif s.begins_with("--quality="):
			Settings.set_quality(s.substr(10))
		elif s == "--no-probe":
			no_probe = true
		elif s.begins_with("--only="):
			only = s.substr(7).split(",")
		elif s == "--no-fsr":
			no_fsr = true
		elif s == "--no-volfog":
			no_volfog = true
		elif s == "--no-sdfgi":
			no_sdfgi = true
	DirAccess.make_dir_recursive_absolute(out)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	if no_probe:
		main.sky.probe.visible = false
		main.sky.probe.process_mode = Node.PROCESS_MODE_DISABLED
	if no_sdfgi:
		main.sky.env.sdfgi_enabled = false
	if no_volfog:
		main.sky.env.volumetric_fog_enabled = false
	if no_fsr:
		# FSR2 -> TAA a resolución nativa (los shaders de FSR2 agotan la RAM de lavapipe).
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = 1.0
		get_viewport().use_taa = true
	_run.call_deferred()


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s%s.png" % [out, prefix, name])
	print("SHOT ", name)


func want(n: String) -> bool:
	return only.is_empty() or only.has(n)


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _run() -> void:
	await wait(2.0)
	GameState.new_game()
	main.title_menu.visible = false
	GameState.in_game = true
	main._start_play()
	main.hud.visible = false
	main.touch.visible = false
	GameState.world_minutes = 11 * 60
	# 6. Mirador: vista lejana de la ciudad a mediodía (nitidez, neblina y distancia de dibujado).
	if want("6"):
		GameState.world_minutes = 12 * 60 + 30
		var eye6 := Vector3(-150, 95, 230)
		var at6 := Vector3(60, 0, -160)
		main.rig.cinematic_shot(CameraRig.look_from(eye6, at6), CameraRig.look_from(eye6, at6), 999.0, 55.0, 55.0)
		await wait(4.0)
		await shot("6_mirador")
		var eye7 := Vector3(-42, 1.7, 30)
		var at7 := Vector3(-42, 3.0, -200)
		main.rig.cinematic_shot(CameraRig.look_from(eye7, at7), CameraRig.look_from(eye7, at7), 999.0, 60.0, 60.0)
		await wait(3.0)
		await shot("7_avenida")
		main.rig.end_cinematic()
		if only.size() == 1:
			get_tree().quit()
			return
	# 1. Calle de día, a pie.
	main.player.place(Vector3(-42, 0.3, 12), PI * 0.75)
	main.rig.yaw = PI * 0.75 + PI
	main.rig.pitch = -0.12
	if want("1"):
		await wait(3.0)
		await shot("1_calle_dia")
	print("MEM static=%.0f MB  texturas_vram=%.0f MB  vram_total=%.0f MB  objetos_dibujados=%d  primitivas=%d" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	# 2. Primer plano de un coche con reflejos (mañana).
	var car: Car = main.vehicle("free_sedan")
	var cx: Transform3D = car.global_transform
	var eye: Vector3 = cx * Vector3(2.6, 1.0, -3.6)
	var at: Vector3 = cx * Vector3(0, 0.55, 0)
	if want("4"):
		main.rig.cinematic_shot(CameraRig.look_from(eye, at), CameraRig.look_from(eye, at), 2.0, 45.0, 45.0)
		await wait(2.5)
		await shot("4_coche_reflejos")
		main.rig.end_cinematic()
	# 3. Atardecer.
	GameState.world_minutes = 18 * 60 + 55
	main.player.place(Vector3(-42, 0.3, 12), PI * 0.75)
	main.rig.yaw = -PI * 0.5
	if want("2") or want("5"):
		await wait(3.0)
	if want("2"):
		await shot("2_atardecer")
	# 4. Cinemática con profundidad de campo (atardecer, personaje en primer plano).
	var pp: Vector3 = main.player.global_position
	var e2 := pp + Vector3(1.6, 1.55, 1.6)
	var a2 := pp + Vector3(0, 1.45, 0)
	if want("5"):
		main.rig.cinematic_shot(CameraRig.look_from(e2, a2), CameraRig.look_from(e2, a2), 2.0, 40.0, 40.0)
		await wait(2.5)
		await shot("5_cinematica_dof")
		main.rig.end_cinematic()
	if not want("3"):
		print("SHOT done")
		get_tree().quit()
		return
	# 5. Noche con farolas y faros, en coche.
	GameState.world_minutes = 22 * 60 + 30
	main.player.place(car.global_position + Vector3(0, 0.3, -2.5), 0.0)
	await wait(0.5)
	await main.board(car, "driver")
	main.touch.visible = false
	Controls.enabled = true
	Controls.touch_move = Vector2(0, 0.6)
	await wait(3.0)
	Controls.touch_move = Vector2.ZERO
	await wait(1.0)
	await shot("3_noche_farolas_faros")
	print("SHOT done")
	get_tree().quit()
