class_name ImpactSystem
extends Node
## Convierte coches de tráfico cinemáticos golpeados en cuerpos físicos y los limpia.

var traffic: Traffic
var _knocked: Array = []   # {"body": RigidBody3D, "t": float}


func knock_traffic_car(tc: Node3D, impulse: Vector3, at: Vector3) -> void:
	if tc == null or not is_instance_valid(tc) or tc is RigidBody3D:
		return
	if traffic != null:
		traffic.cars.erase(tc)
	# Se hace diferido: normalmente se llama desde la señal de contacto.
	_convert.call_deferred(tc, impulse, at)


func _convert(tc: Node3D, impulse: Vector3, at: Vector3) -> void:
	if not is_instance_valid(tc) or not tc.is_inside_tree():
		return
	var parent := tc.get_parent()
	var rb := RigidBody3D.new()
	rb.mass = 1200.0
	rb.linear_damp = 0.15
	rb.angular_damp = 0.8
	rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	rb.center_of_mass = Vector3(0, 0.4, 0)
	var co := tc as CollisionObject3D
	if co:
		rb.collision_layer = co.collision_layer
		rb.collision_mask = co.collision_mask
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.1
	rb.physics_material_override = pm
	var xf := tc.global_transform
	parent.add_child(rb)
	rb.global_transform = xf
	for c in tc.get_children():
		(c as Node).reparent(rb, false)
	tc.queue_free()
	rb.apply_impulse(impulse, at - rb.global_position)
	rb.angular_velocity = Vector3(0, signf(impulse.x + 0.001) * 1.5, 0)
	_knocked.append({"body": rb, "t": 25.0})


func _physics_process(delta: float) -> void:
	if _knocked.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	for i in range(_knocked.size() - 1, -1, -1):
		var k: Dictionary = _knocked[i]
		var b: RigidBody3D = k["body"]
		if not is_instance_valid(b):
			_knocked.remove_at(i)
			continue
		k["t"] = float(k["t"]) - delta
		var far := cam != null and cam.global_position.distance_to(b.global_position) > 120.0
		if float(k["t"]) <= 0.0 or far:
			b.queue_free()
			_knocked.remove_at(i)
