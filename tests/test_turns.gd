extends Node3D
## Prueba de vuelco: acelera a fondo y gira bruscamente a varias velocidades.
## Pasa si el coche nunca supera ~35° de inclinación.
func _ready() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(6000, 1, 6000)
	cs.shape = b
	cs.position.y = -0.5
	ground.add_child(cs)
	add_child(ground)
	var fails := 0
	for style in [0, 2, 3]:
		for secs in [3.0, 6.0, 10.0]:
			var car := Car.new()
			add_child(car)
			car.setup(style, Color.RED, "t")
			car.global_position = Vector3(0, 1, 0)
			for i in 30:
				await get_tree().physics_frame
			car.set_driver(true)
			Controls.enabled = true
			Controls.touch_move = Vector2(0, 1)
			for i in int(secs * 60):
				await get_tree().physics_frame
			var kmh := car.speed_kmh()
			var min_up := 1.0
			var yaw0 := car.global_rotation.y
			var max_yaw := 0.0
			# Volantazo a un lado, luego al otro (eslalon).
			for side in [1.0, -1.0, 1.0]:
				Controls.touch_move = Vector2(side, 1)
				for i in 70:
					await get_tree().physics_frame
					min_up = minf(min_up, car.global_basis.y.y)
					max_yaw = maxf(max_yaw, absf(angle_difference(yaw0, car.global_rotation.y)))
			var ok := min_up > 0.82
			if not ok:
				fails += 1
			print("estilo ", style, " a ", int(kmh), " km/h -> up mín ", snappedf(min_up, 0.01), " giro máx ", int(rad_to_deg(max_yaw)), "° ", "OK" if ok else "VUELCA")
			Controls.touch_move = Vector2.ZERO
			car.queue_free()
			await get_tree().physics_frame
	print("== Vuelcos: ", fails)
	get_tree().quit()
