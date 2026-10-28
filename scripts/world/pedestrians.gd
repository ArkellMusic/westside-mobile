class_name Pedestrians
extends Node3D
## Peatones que dan la vuelta a las manzanas por la acera. Se apartan si un coche
## se les echa encima. Sin física para que sean baratos en móvil.

var peds: Array = []
var danger: Array = []  # nodos peligrosos (coche del jugador)
var rng := RandomNumberGenerator.new()


func setup(count: int) -> void:
	rng.seed = 404
	var blocks := CityLayout.blocks()
	for i in count:
		var blk: Dictionary = blocks[rng.randi() % blocks.size()]
		var r: Rect2 = (blk["rect"] as Rect2).grow(-CityLayout.SIDEWALK * 0.5)
		var h := Humanoid.new()
		add_child(h)
		h.setup(Humanoid.random_look(rng))
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		if rng.randf() < 0.5:
			corners.reverse()
		var start := rng.randi() % 4
		var t := rng.randf()
		var a: Vector2 = corners[start]
		var b: Vector2 = corners[(start + 1) % 4]
		var p := a.lerp(b, t)
		h.position = Vector3(p.x, 0.12, p.y)
		peds.append({"node": h, "corners": corners, "next": (start + 1) % 4, "speed": rng.randf_range(1.1, 1.6), "dodge": 0.0})


func _physics_process(delta: float) -> void:
	for ped in peds:
		var h: Humanoid = ped["node"]
		var target: Vector2 = ped["corners"][ped["next"]]
		var p := Vector2(h.position.x, h.position.z)
		var d := target - p
		if d.length() < 0.3:
			ped["next"] = (int(ped["next"]) + 1) % 4
			continue
		var dir := d.normalized()
		var speed: float = ped["speed"]
		for n in danger:
			var car := n as Node3D
			if car == null or not car.is_visible_in_tree():
				continue
			var cd := Vector2(car.global_position.x, car.global_position.z) - p
			var v := (car as RigidBody3D).linear_velocity.length() if car is RigidBody3D else 0.0
			if cd.length() < 6.0 and v > 4.0:
				ped["dodge"] = 1.2
				dir = -cd.normalized()
				speed = 4.5
		if float(ped["dodge"]) > 0.0:
			ped["dodge"] = float(ped["dodge"]) - delta
		var np := p + dir * speed * delta
		h.position = Vector3(np.x, 0.12, np.y)
		h.rotation.y = lerp_angle(h.rotation.y, atan2(-dir.x, -dir.y), clampf(delta * 8.0, 0, 1))
		h.animate(delta, speed, true)
