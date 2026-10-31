class_name CameraRig
extends Node3D
## Cámara en tercera persona: órbita con arrastre táctil o ratón, brazo con
## colisión, seguimiento del coche por detrás y modo cinemático para escenas.

var target: Node3D
var yaw: float = 0.0
var pitch: float = -0.25
var distance: float = 4.2
var height: float = 1.6
var vehicle_mode: bool = false
var cinematic: bool = false

var camera: Camera3D
var cine_camera: Camera3D
var _arm: SpringArm3D
var _pivot: Node3D
var _idle_time: float = 0.0
var _cine_from: Transform3D
var _cine_to: Transform3D
var _cine_t: float = 0.0
var _cine_duration: float = 1.0
var _cine_fov_from: float = 65.0
var _cine_fov_to: float = 65.0
var _shake: float = 0.0
var _attach: Node3D = null


func _ready() -> void:
	# La cámara se actualiza después de mover vehículos y personajes (sin retraso).
	process_priority = 100
	_pivot = Node3D.new()
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_arm.shape = probe
	_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.far = 5000.0
	camera.near = 0.08
	_arm.add_child(camera)
	camera.current = true
	# Cámara aparte para cinemáticas: el SpringArm no la mueve.
	cine_camera = Camera3D.new()
	cine_camera.far = 5000.0
	cine_camera.near = 0.05
	cine_camera.top_level = true
	add_child(cine_camera)


func exclude(body: CollisionObject3D) -> void:
	_arm.add_excluded_object(body.get_rid())


func clear_excludes() -> void:
	_arm.clear_excluded_objects()


func follow(node: Node3D, as_vehicle: bool) -> void:
	target = node
	vehicle_mode = as_vehicle
	distance = 7.0 if as_vehicle else 4.2
	height = 2.0 if as_vehicle else 1.6
	pitch = -0.18 if as_vehicle else -0.25
	if as_vehicle:
		yaw = node.global_rotation.y + PI
	if target:
		global_position = target.global_position + Vector3.UP * height


## Plano cinemático: interpola entre dos transformaciones de cámara.
func cinematic_shot(from: Transform3D, to: Transform3D, duration: float, fov_from: float = 55.0, fov_to: float = 55.0) -> void:
	cinematic = true
	_attach = null
	_cine_from = from
	_cine_to = to
	_cine_t = 0.0
	_cine_duration = maxf(duration, 0.01)
	_cine_fov_from = fov_from
	_cine_fov_to = fov_to
	cine_camera.global_transform = from
	cine_camera.fov = letterbox_fov(fov_from)
	cine_camera.current = true


## Fracción de pantalla tapada por CADA franja negra (la pone el HUD).
static var letterbox_cover: float = 0.0


## Abre el FOV vertical para que lo encuadrado quede en la banda visible entre
## las franjas negras y no se corten las caras.
static func letterbox_fov(fov: float) -> float:
	var visible_frac := maxf(1.0 - 2.0 * letterbox_cover, 0.3)
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) * 0.5) / visible_frac))


## Plano relativo a un nodo en movimiento (p. ej. dentro del autobús).
func attached_shot(node: Node3D, local_from: Transform3D, local_to: Transform3D, duration: float, fov_from: float = 50.0, fov_to: float = 50.0) -> void:
	cinematic_shot(local_from, local_to, duration, fov_from, fov_to)
	_attach = node
	cine_camera.global_transform = node.global_transform * local_from


static func look_from(pos: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(at - pos, Vector3.UP), pos)


func end_cinematic() -> void:
	cinematic = false
	_attach = null
	camera.current = true


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	if cinematic:
		_cine_t = minf(_cine_t + delta / _cine_duration, 1.0)
		var t := _cine_t * _cine_t * (3.0 - 2.0 * _cine_t)
		var xf := _cine_from.interpolate_with(_cine_to, t)
		if _attach and is_instance_valid(_attach):
			xf = _attach.global_transform * xf
		cine_camera.global_transform = xf
		cine_camera.fov = letterbox_fov(lerpf(_cine_fov_from, _cine_fov_to, t))
		return
	if target == null:
		return
	var look := Controls.consume_look()
	var sens := 0.005 * Settings.camera_sensitivity
	if look.length() > 0.0:
		yaw -= look.x * sens
		pitch -= look.y * sens * (-1.0 if Settings.invert_y else 1.0)
		pitch = clampf(pitch, -1.2, 0.5)
		_idle_time = 0.0
	else:
		_idle_time += delta
	if vehicle_mode and _idle_time > 1.2:
		var car := target as Car
		var speed := car.linear_velocity.length() if car else 0.0
		if speed > 2.0:
			var behind := target.global_rotation.y + PI
			if car and car.forward_speed() < -1.0:
				behind = target.global_rotation.y
			yaw = lerp_angle(yaw, behind, clampf(delta * 2.5, 0.0, 1.0))
			pitch = lerpf(pitch, -0.16, delta * 1.5)
	var desired := target.global_position + Vector3.UP * height
	global_position = global_position.lerp(desired, clampf(delta * (14.0 if vehicle_mode else 18.0), 0.0, 1.0))
	_pivot.rotation = Vector3(pitch, yaw, 0)
	var speed_bonus := 0.0
	if vehicle_mode and target is Car:
		speed_bonus = clampf((target as Car).linear_velocity.length() / 40.0, 0.0, 1.0)
	_arm.spring_length = distance + speed_bonus * 1.8
	camera.fov = 65.0 + speed_bonus * 10.0
	if _shake > 0.0:
		camera.h_offset = randf_range(-1, 1) * _shake * 0.1
		camera.v_offset = randf_range(-1, 1) * _shake * 0.1
		_shake = maxf(0.0, _shake - delta * 3.0)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
