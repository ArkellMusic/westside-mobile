extends Node3D
## Ajuste de la física del coche: prueba varias fuerzas de motor en una recta.
func _ready() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(4000, 1, 4000)
	cs.shape = b
	cs.position.y = -0.5
	ground.add_child(cs)
	add_child(ground)
	for f in [95.0, 400.0, 1200.0, 3000.0, 6000.0]:
		var car := Car.new()
		add_child(car)
		car.setup(1, Color.RED, "t")
		car.max_engine_force = f
		car.global_position = Vector3(0, 1, 0)
		for i in 30:
			await get_tree().physics_frame
		car.set_driver(true)
		Controls.enabled = true
		Controls.touch_move = Vector2(0, 1)
		for i in 360:
			await get_tree().physics_frame
		var s6 := car.speed_kmh()
		for i in 600:
			await get_tree().physics_frame
		print("force ", f, " 6s=", snappedf(s6, 0.1), " 16s=", snappedf(car.speed_kmh(), 0.1), " up=", snappedf(car.global_basis.y.y, 0.01), " y=", snappedf(car.global_position.y, 0.01))
		Controls.touch_move = Vector2(0, -1)
		for i in 240:
			await get_tree().physics_frame
		print("   brake 4s -> ", snappedf(car.speed_kmh(), 0.1))
		Controls.touch_move = Vector2.ZERO
		car.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
