extends Node
## Capturas del mapa del estado (fase 1): vista aérea, autopista, desierto, montañas,
## islas con puentes, radar y mapa de pausa ESTADO. Uso:
##   godot.vk --path . --resolution 1560x720 res://tests/shot_mapa.tscn -- --out=/home/claude/shots [--only=1,3]

var out := "/home/claude/shots"
var prefix := "mapa_"
var main: Node
var only: PackedStringArray = []
var cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out = s.substr(6)
		elif s.begins_with("--only="):
			only = s.substr(7).split(",")
		elif s.begins_with("--quality="):
			Settings.set_quality(s.substr(10))
	DirAccess.make_dir_recursive_absolute(out)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	# lavapipe: sin SDFGI ni sonda (RAM del contenedor).
	main.sky.probe.visible = false
	main.sky.probe.process_mode = Node.PROCESS_MODE_DISABLED
	main.sky.env.sdfgi_enabled = false
	main.sky.env.volumetric_fog_enabled = false
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = 1.0
	_run.call_deferred()


func want(n: String) -> bool:
	return only.is_empty() or only.has(n)


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s%s.png" % [out, prefix, name])
	print("SHOT ", name, "  ", stats())


func stats() -> String:
	return "mem_static=%.0f MB tex_vram=%.0f MB vram=%.0f MB objetos=%d primitivas=%d fps=%.1f chunks=%d" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		Performance.get_monitor(Performance.TIME_FPS),
		main.state_world.terrain.loaded_chunks().size()]


## Coloca la cámara libre y espera a que el terreno cargue alrededor.
func view(eye: Vector3, at: Vector3, fov: float = 60.0, max_wait: float = 60.0) -> void:
	cam.global_transform = Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye)
	cam.fov = fov
	cam.make_current()
	print("vista ", eye, " ", stats())
	var t: Terrain = main.state_world.terrain
	t.focus_override = eye
	# En lavapipe va a ~1 fps: se carga todo de golpe en vez de un chunk por frame.
	t.update_sync(eye)
	var waited := 0.0
	await wait(0.5)
	while not t.is_idle() and waited < max_wait:
		await wait(0.5)
		waited += 0.5
	await wait(1.0)


func _run() -> void:
	await wait(1.5)
	GameState.new_game()
	main.title_menu.visible = false
	GameState.in_game = true
	main._start_play()
	main.hud.visible = false
	main.touch.visible = false
	GameState.world_minutes = 11 * 60 + 30
	cam = Camera3D.new()
	cam.far = 16000.0
	cam.near = 0.3
	add_child(cam)
	print("tras start_play ", stats())
	main.state_world.terrain.wait_grid()
	print("tras grid ", stats())
	var env: Environment = main.sky.env
	var fog_d := env.fog_density
	if want("1"):
		cam.near = 20.0
		await view(Vector3(2500, 1500, 3400), Vector3(2500, 0, -1100), 62.0, 120.0)
		main.sky.set_process(false)
		env.fog_density = 0.00007
		env.fog_enabled = false
		print("fog ", env.fog_enabled, " ", env.fog_mode, " sky_affect=", env.fog_sky_affect, " depth=", env.fog_depth_curve, " aerial=", env.fog_aerial_perspective, " hdens=", env.fog_height_density, " exp=", env.tonemap_exposure)
		env.volumetric_fog_enabled = false
		await wait(1.0)
		await shot("1_aerea_estado")
		env.fog_density = fog_d
		main.sky.set_process(true)
		env.fog_enabled = true
		cam.near = 0.3
	if want("2"):
		await view(Vector3(300, 16, -26), Vector3(1100, 2, 8), 60.0)
		await shot("2_autopista_westbrook")
	if want("3"):
		await view(Vector3(2650, 75, -420), Vector3(2820, 25, -1450), 62.0)
		await shot("3_desierto_las_brisas")
	if want("4"):
		await view(Vector3(3200, 70, -1450), Vector3(3700, 230, -2900), 62.0)
		await shot("4_montanas_northpoint")
	if want("5"):
		await view(Vector3(3150, 160, 250), Vector3(3900, 0, 980), 62.0)
		await shot("5_costa_islas_puentes")
	if want("6") or want("7"):
		main.rig.camera.make_current()
		main.state_world.terrain.focus_override = Vector3.INF
		main.player.place(Vector3(470, 0.4, 5), -PI * 0.5)
		main.rig.yaw = -PI * 0.5
		main.hud.visible = true
		main.gps.set_waypoint(Vector3(2800, 0, -1350))
		await wait(4.0)
		if want("6"):
			await shot("6_radar")
		if want("7"):
			main._open_map()
			main.map_screen.open_tab(1)
			await wait(1.0)
			await shot("7_mapa_pausa_estado")
	print("SHOT done")
	get_tree().quit()
