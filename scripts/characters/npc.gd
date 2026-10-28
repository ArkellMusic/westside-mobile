class_name NPC
extends CharacterBody3D
## Personaje con nombre (Big Ray, Dre, Loco...). Puede quedarse quieto con una
## pose, mirar al jugador cuando se acerca o caminar hacia un punto.

var character_id: String = ""
var model: Humanoid
var stance: String = ""
var look_at_player: bool = true
var player: Node3D
var _walk_target: Vector3 = Vector3.INF
var _walk_speed: float = 1.6
var gravity: float = 9.8

signal arrived


func setup(id: String, p_stance: String = "") -> void:
	character_id = id
	stance = p_stance
	name = id.capitalize().replace(" ", "")
	var shape := CapsuleShape3D.new()
	shape.radius = 0.33
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	model = Humanoid.new()
	add_child(model)
	model.setup(GameData.character_look(id))
	if stance != "":
		model.pose_idle_stance(stance)


func walk_to(p: Vector3, speed: float = 1.6) -> void:
	_walk_target = p
	_walk_speed = speed


func face(point: Vector3) -> void:
	var d := point - global_position
	model.rotation.y = atan2(-d.x, -d.z)


func _physics_process(delta: float) -> void:
	var speed := 0.0
	if _walk_target != Vector3.INF:
		var d := _walk_target - global_position
		d.y = 0
		if d.length() < 0.4:
			_walk_target = Vector3.INF
			velocity.x = 0
			velocity.z = 0
			arrived.emit()
		else:
			var dir := d.normalized()
			velocity.x = dir.x * _walk_speed
			velocity.z = dir.z * _walk_speed
			model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 8.0, 0, 1))
			speed = _walk_speed
	elif look_at_player and player and player.is_visible_in_tree():
		var to_p := player.global_position - global_position
		to_p.y = 0
		if to_p.length() < 7.0:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(-to_p.x, -to_p.z), clampf(delta * 3.0, 0, 1))
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	if speed > 0.0 or stance == "":
		model.animate(delta, speed, true)
