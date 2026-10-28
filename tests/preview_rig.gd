extends Node3D
func _ready() -> void:
	_go.call_deferred()
func _go() -> void:
	var root := Node3D.new()
	add_child(root)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.21, 0.24)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	var we := WorldEnvironment.new(); we.environment = e; root.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35, 150, 0); root.add_child(sun)
	var ids := ["mack", "big_ray", "keisha"]
	var hs := []
	for i in 3:
		var h := Humanoid.new()
		root.add_child(h)
		h.setup(GameData.character_look(ids[i]))
		h.position = Vector3(-1.6 + i * 1.6, 0, 0)
		h.rotation.y = PI
		hs.append(h)
	var cam := Camera3D.new(); root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.2, 5.0), Vector3(0, 0.95, 0))
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/rig_idle.png")
	for k in 20:
		for h in hs: h.animate(0.03, 5.0, true)
	(hs[0] as Humanoid).animate(0.0, 5.0, true)
	await RenderingServer.frame_post_draw
	cam.look_at_from_position(Vector3(4.5, 1.2, 1.5), Vector3(0, 0.95, 0))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/rig_run.png")
	(hs[1] as Humanoid).pose_idle_stance("arms_crossed")
	(hs[0] as Humanoid).set_seated(true)
	cam.look_at_from_position(Vector3(0, 1.2, 5.0), Vector3(0, 0.95, 0))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/rig_poses.png")
	get_tree().quit()
