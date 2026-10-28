class_name Car
extends VehicleBody3D
## Coche conducible con física de VehicleBody3D: suspensión, tracción trasera,
## dirección que se reduce con la velocidad, freno, marcha atrás y freno de mano
## para derrapar. Con conductor lee los controles; sin conductor queda frenado.

signal driver_changed(has_driver: bool)

@export var style: int = 0
@export var body_color: Color = Color(0.8, 0.1, 0.1)

var vehicle_id: String = ""
var display_name: String = ""
var has_driver: bool = false
var max_engine_force: float = 6500.0
var max_brake: float = 28.0
var max_speed: float = 46.0       # m/s (~165 km/h)
var max_reverse: float = 9.0
var steer_low: float = 0.6
var steer_high: float = 0.14

var _steer: float = 0.0
var _wheels: Array = []
var _rear_wheels: Array = []
var _body_mesh: MeshInstance3D
var _spec: Dictionary = {}


func setup(p_style: int, p_color: Color, p_id: String = "", p_name: String = "") -> void:
	style = p_style
	body_color = p_color
	vehicle_id = p_id
	display_name = p_name if p_name != "" else CarModel.STYLE_NAMES[style]
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_wheels.clear()
	_rear_wheels.clear()
	_spec = CarModel.spec(style)
	mass = 1250.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.35, 0.1)
	angular_damp = 0.6
	linear_damp = 0.05
	can_sleep = true
	contact_monitor = true
	max_contacts_reported = 4

	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	_body_mesh.mesh = CarModel.build(style, body_color, false)
	add_child(_body_mesh)

	var half_w: float = _spec["half_w"]
	var length: float = _spec["length"]
	var height: float = _spec["height"]
	var shape := BoxShape3D.new()
	shape.size = Vector3(half_w * 2.0, height - 0.35, length)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.35 + (height - 0.35) * 0.5, 0)
	add_child(cs)

	var wheel_mesh := CarModel.wheel_mesh(style)
	var r: float = _spec["wheel_r"]
	for front in [true, false]:
		for sx in [-1.0, 1.0]:
			var w := VehicleWheel3D.new()
			w.position = Vector3(sx * float(_spec["track"]), r + 0.12, (1.0 if front else -1.0) * float(_spec["wheel_z"]))
			w.wheel_radius = r
			w.wheel_rest_length = 0.16
			w.suspension_travel = 0.18
			w.suspension_stiffness = 55.0
			w.suspension_max_force = 14000.0
			w.damping_compression = 0.45
			w.damping_relaxation = 0.6
			w.wheel_friction_slip = 2.6 if front else 2.4
			w.wheel_roll_influence = 0.12
			w.use_as_steering = front
			w.use_as_traction = not front
			var wm := MeshInstance3D.new()
			wm.mesh = wheel_mesh
			if sx < 0.0:
				wm.rotation.y = PI
			w.add_child(wm)
			add_child(w)
			_wheels.append(w)
			if not front:
				_rear_wheels.append(w)


func set_driver(active: bool) -> void:
	has_driver = active
	if not active:
		engine_force = 0.0
		brake = 6.0
	else:
		sleeping = false
	driver_changed.emit(active)


func forward_speed() -> float:
	return linear_velocity.dot(global_basis.z)


func speed_kmh() -> float:
	return absf(forward_speed()) * 3.6


func _physics_process(delta: float) -> void:
	if not has_driver:
		engine_force = 0.0
		brake = 6.0 if linear_velocity.length() < 3.0 else 2.0
		steering = move_toward(steering, 0.0, delta * 2.0)
		return
	var mv := Controls.move
	var throttle := 1.0 if Controls.is_down("gas") else clampf(mv.y, 0.0, 1.0)
	var brake_in := 1.0 if Controls.is_down("brake") else clampf(-mv.y, 0.0, 1.0)
	var handbrake := Controls.is_down("handbrake")
	var v := forward_speed()

	# Dirección suavizada y limitada por velocidad.
	var speed_t := clampf(absf(v) / 30.0, 0.0, 1.0)
	var max_steer := lerpf(steer_low, steer_high, speed_t)
	var target := -mv.x * max_steer
	_steer = move_toward(_steer, target, delta * (2.6 if absf(target) > absf(_steer) else 4.0))
	steering = _steer

	var force := 0.0
	var brk := 0.0
	if throttle > 0.05:
		if v < -1.0:
			brk = max_brake * throttle
		else:
			var curve := 1.0 - clampf(v / max_speed, 0.0, 1.0)
			force = max_engine_force * throttle * (0.35 + 0.65 * curve)
	elif brake_in > 0.05:
		if v > 1.0:
			brk = max_brake * brake_in
		elif v > -max_reverse:
			force = -max_engine_force * 0.55 * brake_in
	else:
		brk = 0.6
	if handbrake:
		brk = maxf(brk, max_brake * 0.5)
	for w in _rear_wheels:
		(w as VehicleWheel3D).wheel_friction_slip = 1.1 if handbrake else 2.4
	engine_force = force
	brake = brk

	# Fuerza hacia abajo y estabilización para que no vuelque con facilidad.
	apply_central_force(Vector3.DOWN * linear_velocity.length() * 25.0)
	if global_basis.y.y < 0.3 and linear_velocity.length() < 2.0:
		_flip_upright()


func _flip_upright() -> void:
	var yaw := global_rotation.y
	global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * 1.0)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Punto donde aparece el conductor al bajarse (lado izquierdo; derecho si está bloqueado).
func exit_point(side: float = -1.0) -> Vector3:
	var half_w: float = _spec.get("half_w", 1.0)
	return global_position + global_basis.x * side * (half_w + 0.9) + Vector3.UP * 0.2
