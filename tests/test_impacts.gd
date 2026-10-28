extends Node3D
## Prueba de impactos: coche contra muro + atropello de peatón.
##   godot --headless --path . res://tests/test_impacts.tscn

var _fails: int = 0
var _hits: int = 0
var _crashes: int = 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  OK   ", what)
	else:
		_fails += 1
		printerr("  FALLO ", what)


func _ready() -> void:
	var ground := StaticBody3D.new()
	var gcs := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(400, 1, 400)
	gcs.shape = gs
	ground.add_child(gcs)
	ground.position.y = -0.5
	add_child(ground)

	# Muro a 15 m en +Z.
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var ws := BoxShape3D.new()
	ws.size = Vector3(10, 4, 1)
	wcs.shape = ws
	wall.add_child(wcs)
	wall.position = Vector3(0, 2, 17)
	add_child(wall)

	var impact := ImpactSystem.new()
	add_child(impact)

	var car := Car.new()
	add_child(car)
	car.setup(0, Color.RED, "t", "Test")
	car.position = Vector3(0, 0.6, 0)   # el frente del coche mira a +Z
	car.impact_system = impact
	car.crashed.connect(func(_s: float, _p: Vector3, _o: Node) -> void: _crashes += 1)
	car.set_driver(true)

	var peds := Pedestrians.new()
	add_child(peds)
	peds.setup(1)
	peds.vehicle = car
	peds.pedestrian_hit.connect(func(_p: Vector3, _s: float) -> void: _hits += 1)
	var h: Humanoid = peds.peds[0]["node"]
	peds.peds[0]["corners"] = [Vector2(0, 8), Vector2(0, 8.1), Vector2(0, 8.2), Vector2(0, 8.3)]
	peds.peds[0]["dodger"] = false
	h.position = Vector3(0, 0.12, 8.0)

	Controls.enabled = true
	Controls.touch_move = Vector2(0, 1)
	var t := 0.0
	while t < 8.0 and car.damage <= 0.0:
		await get_tree().physics_frame
		Controls.touch_move = Vector2(0, 1)
		t += get_physics_process_delta_time()
	await get_tree().create_timer(0.3).timeout

	print("damage=", car.damage, " crashes=", _crashes, " hits=", _hits, " t=", t)
	check(car.damage > 0.0, "el coche acumula daño tras chocar con el muro")
	check(_crashes > 0, "señal crashed emitida")
	check(_hits == 1, "pedestrian_hit emitido al atropellar")
	check(peds.downed.size() == 1 and peds.peds.is_empty(), "peatón fuera de la lista de caminantes")
	car.repair()
	check(car.damage == 0.0, "repair() restaura el daño")
	Controls.touch_move = Vector2.ZERO

	var traffic := Traffic.new()
	add_child(traffic)
	impact.traffic = traffic
	var tc := Traffic.TrafficCar.new()
	var tcs := CollisionShape3D.new()
	tcs.shape = BoxShape3D.new()
	tc.add_child(tcs)
	tc.add_child(MeshInstance3D.new())
	add_child(tc)
	tc.position = Vector3(50, 0.5, 50)
	traffic.cars.append(tc)
	impact.knock_traffic_car(tc, Vector3(0, 0, 20000), tc.global_position)
	await get_tree().create_timer(0.5).timeout
	var rbs := 0
	for c in get_children():
		if c is RigidBody3D and not (c is Car):
			rbs += 1
	check(traffic.cars.is_empty() and rbs == 1, "coche de tráfico golpeado pasa a RigidBody3D")
	print("Resultado impactos: ", _fails, " fallos")
	get_tree().quit(1 if _fails > 0 else 0)
