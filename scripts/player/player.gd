class_name Player
extends CharacterBody3D
## Mack a pie: movimiento relativo a la cámara, correr, saltar y gravedad.

const WALK_SPEED := 2.4
const JOG_SPEED := 4.2
const SPRINT_SPEED := 6.8
const JUMP_VELOCITY := 4.8
const TURN_SPEED := 10.0

var model: Humanoid
var camera_yaw: float = 0.0
var input_enabled: bool = true
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.33
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	model = Humanoid.new()
	model.name = "Model"
	add_child(model)
	model.setup(GameData.character_look("mack"))
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)


func _physics_process(delta: float) -> void:
	var mv := Controls.move if input_enabled else Vector2.ZERO
	var forward := Vector3(-sin(camera_yaw), 0, -cos(camera_yaw))
	var right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
	var dir := (right * mv.x + forward * mv.y)
	var amount := minf(dir.length(), 1.0)
	if dir.length() > 0.01:
		dir = dir.normalized()
	var target_speed := 0.0
	if amount > 0.05:
		target_speed = lerpf(WALK_SPEED, JOG_SPEED, clampf((amount - 0.3) / 0.6, 0.0, 1.0))
		if input_enabled and Controls.is_down("sprint"):
			target_speed = SPRINT_SPEED
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var accel := 18.0 if is_on_floor() else 4.0
	horizontal = horizontal.move_toward(dir * target_speed, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		if input_enabled and Controls.just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= gravity * delta
	move_and_slide()

	if horizontal.length() > 0.3:
		var target_yaw := atan2(-horizontal.x, -horizontal.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
	model.animate(delta, horizontal.length(), is_on_floor())

	# Si cae al mar (lejos de la orilla) vuelve a la arena.
	if global_position.y < CityLayout.WATER_LEVEL - 0.9:
		global_position = CityLayout.landmark("beach") + Vector3.UP


func face_yaw() -> float:
	return model.rotation.y


func set_facing(yaw: float) -> void:
	model.rotation.y = yaw


func place(pos: Vector3, yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	model.rotation.y = yaw
