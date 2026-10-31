extends Node
## Capturas de los peatones de Mixamo:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##     --resolution 1560x720 res://tests/shot_peatones.tscn -- --out=/ruta [--mode=world|intro]
## world: calle con varios peatones, primer plano y peatón atropellado. intro: Mack al teléfono.

var out := "/home/claude/shots"
var mode := "world"
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out = String(a).substr(6)
		if String(a).begins_with("--mode="):
			mode = String(a).substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)


func cam(from: Vector3, at: Vector3, fov: float = 55.0) -> void:
	main.rig.cinematic_shot(CameraRig.look_from(from, at), CameraRig.look_from(from, at), 999.0, fov, fov)


func _run() -> void:
	await wait(2.0)
	if mode == "intro":
		await _intro()
	else:
		await _world()
	get_tree().quit()


func _intro() -> void:
	# Salta rápido hasta la llamada de Big Ray (Engine.time_scale) y captura a Mack con el móvil.
	main.title_menu.visible = false
	Engine.time_scale = 6.0
	main.new_game()
	var intro: IntroCinematic = null
	for i in 40:
		for c in main.get_children():
			if c is IntroCinematic:
				intro = c
		if intro:
			break
		await wait(0.25)
	var waited := 0.0
	while waited < 240.0 and not (intro.phone_light != null and intro.phone_light.light_energy > 1.0):
		await wait(0.25)
		waited += 0.25
	Engine.time_scale = 1.0
	print("llamada empezada tras ", waited, " s")
	for i in 5:
		await wait(2.5)
		await shot("peatones_intro_%02d" % i)


func _setup_world() -> Pedestrians:
	GameState.new_game()
	main.title_menu.visible = false
	GameState.in_game = true
	main._start_play()
	main.hud.visible = false
	main.touch.visible = false
	GameState.world_minutes = 11 * 60 + 17
	main.sky.apply_preset("morning", 0.0)
	await wait(1.0)
	return main.pedestrians


## Rellena la acera del peatón `seed_i` con n peatones más (andando a su paso).
func _crowd(P: Pedestrians, seed_i: int, n: int) -> void:
	var seed_ped: Dictionary = P.peds[seed_i]
	var h0: Node3D = seed_ped["node"]
	var tgt: Vector2 = seed_ped["corners"][seed_ped["next"]]
	var dir := (tgt - Vector2(h0.position.x, h0.position.z)).normalized()
	for k in n:
		var h: Node3D = P._make_person()
		var off := dir * (-9.0 + k * 2.6) + Vector2(-dir.y, dir.x) * (0.5 if k % 2 == 0 else -0.5)
		var p := Vector2(h0.position.x, h0.position.z) + off
		h.position = Vector3(p.x, 0.12, p.y)
		P.peds.append({"node": h, "corners": seed_ped["corners"], "next": seed_ped["next"], "speed": 1.15 + 0.07 * k, "dodge": 0.0, "dodger": false})


func _world() -> void:
	var P: Pedestrians = await _setup_world()
	var best := 0
	var best_d := 1e9
	var pp: Vector3 = main.player.global_position
	for i in P.peds.size():
		var d: float = (P.peds[i]["node"].global_position - pp).length()
		if d < best_d:
			best_d = d
			best = i
	if mode == "street" or mode == "world":
		_crowd(P, best, 9)
		var c: Vector3 = P.peds[best]["node"].global_position
		main.player.place(c + Vector3(0, 0.3, 40), 0.0)
		await wait(2.5)
		c = P.peds[best]["node"].global_position
		var tgt: Vector2 = P.peds[best]["corners"][P.peds[best]["next"]]
		var dir := Vector3(tgt.x - c.x, 0, tgt.y - c.z).normalized()
		var ctr := Vector2.ZERO
		for q in P.peds[best]["corners"]:
			ctr += q
		ctr /= 4.0
		var out_v := Vector3(c.x - ctr.x, 0, c.z - ctr.y).normalized()
		cam(c - dir * 13.0 + out_v * 5.5 + Vector3(0, 2.0, 0), c + dir * 3.0 + Vector3(0, 1.1, 0), 52.0)
		await wait(1.0)
		await shot("peatones_calle")
	if mode == "close" or mode == "world":
		var c: Vector3 = P.peds[best]["node"].global_position
		var made := []
		var models := [0, 3, 5]
		for k in 3:
			var m := MixamoPerson.new()
			main.add_child(m)
			m.setup({"model": models[k], "tint": 0, "scale": 1.0, "phase": 0.3 * k})
			m.global_position = c + Vector3(-1.1 + 1.1 * k, 0.0, -3.0 + 0.3 * absf(k - 1))
			m.rotation.y = PI + 0.25 * (1 - k)
			made.append(m)
		(made[2] as MixamoPerson).pose_idle_stance("phone")
		cam(c + Vector3(0.4, 1.55, 1.2), c + Vector3(0, 1.15, -3.0), 40.0)
		for i in 40:
			(made[0] as MixamoPerson).animate(0.05, 1.2, true)
			(made[1] as MixamoPerson).animate(0.05, 0.0, true)
			(made[2] as MixamoPerson).animate(0.05, 0.0, true)
			await wait(0.05)
		await shot("peatones_primer_plano")
		for m in made:
			m.queue_free()
	if mode == "down" or mode == "world":
		var tgt_i := best
		var h: Node3D = P.peds[tgt_i]["node"]
		P._knock_down(tgt_i, Vector3(0, 0, -9.0), 9.0)
		for i in 80:
			await wait(0.25)
			if P.downed.size() > 0 and int(P.downed[0]["state"]) == 1:
				break
		await wait(0.5)
		var lp := h.global_position
		print("tumbado en ", lp, " rot ", h.rotation)
		cam(lp + Vector3(2.4, 1.5, 2.6), lp + Vector3(0, 0.3, 0), 50.0)
		await wait(0.3)
		await shot("peatones_atropellado")
