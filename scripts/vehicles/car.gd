class_name Car
extends VehicleBody3D
## Coche conducible con física de VehicleBody3D: suspensión, tracción trasera,
## dirección que se reduce con la velocidad, freno, marcha atrás y freno de mano
## para derrapar. Con conductor lee los controles; sin conductor queda frenado.

signal driver_changed(has_driver: bool)
## strength 0..1 aprox. (impacto / 25 m/s), punto de contacto y el otro cuerpo.
signal crashed(strength: float, point: Vector3, other: Node)

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
var _headlights: Array = []
var lights_on: bool = false

## Daños e impactos.
var damage: float = 0.0           # 0..100
var impact_system: ImpactSystem = null
var _prev_vel: Vector3 = Vector3.ZERO
var _crash_cd: float = 0.0
var _smoke: CPUParticles3D
var _dmg_mat: StandardMaterial3D
var _crumple: float = 0.0
static var _debris_mesh: BoxMesh
static var _debris_mat: StandardMaterial3D


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
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	var real_id := RealCarModel.for_style(style)
	var real: Dictionary = RealCarModel.data(real_id) if real_id != "" else {}
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	if real.is_empty():
		_body_mesh.mesh = CarModel.build(style, body_color, false)
	else:
		_body_mesh.mesh = RealCarModel.painted_body(real_id, body_color)
		_spec = _spec.duplicate()
		_spec["half_w"] = real["half_w"]
		_spec["length"] = real["length"]
		_spec["height"] = real["height"]
		_spec["wheel_r"] = real["wheel_r"]
		_spec["track"] = real["track"]
	add_child(_body_mesh)

	var half_w: float = _spec["half_w"]
	var length: float = _spec["length"]
	var height: float = _spec["height"]
	var shape := BoxShape3D.new()
	shape.size = Vector3(half_w * 2.0, height - 0.35, length)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.35 + (height - 0.35) * 0.5, float(real.get("center_z", 0.0)))
	add_child(cs)

	_headlights.clear()
	for sx in [-1.0, 1.0]:
		var hl := SpotLight3D.new()
		hl.light_color = Color(1.0, 0.94, 0.82)
		hl.light_energy = 4.0
		hl.spot_range = 38.0
		hl.spot_angle = 30.0
		hl.spot_attenuation = 0.8
		hl.shadow_enabled = false
		hl.position = Vector3(sx * (float(_spec["half_w"]) - 0.3), 0.7, float(_spec["length"]) * 0.5 + 0.1)
		hl.rotation = Vector3(-0.06, PI, 0)
		hl.visible = false
		add_child(hl)
		_headlights.append(hl)
	var wheel_mesh := CarModel.wheel_mesh(style)
	var r: float = _spec["wheel_r"]
	var defs: Array = []
	if real.is_empty():
		for front in [true, false]:
			for sx in [-1.0, 1.0]:
				defs.append({"front": front, "side": sx, "pos": Vector3(sx * float(_spec["track"]), r, (1.0 if front else -1.0) * float(_spec["wheel_z"])), "mesh": null})
	else:
		defs = real["wheels"]
	for wd in defs:
		var front: bool = wd["front"]
		var sx: float = wd["side"]
		if true:
			var w := VehicleWheel3D.new()
			var wp: Vector3 = wd["pos"]
			w.position = Vector3(wp.x, wp.y + 0.12, wp.z)
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
			if wd["mesh"] != null:
				wm.mesh = wd["mesh"]
			else:
				wm.mesh = wheel_mesh
				if sx < 0.0:
					wm.rotation.y = PI
			w.add_child(wm)
			add_child(w)
			_wheels.append(w)
			if not front:
				_rear_wheels.append(w)


func set_lights(on: bool) -> void:
	if on == lights_on:
		return
	lights_on = on
	for hl in _headlights:
		(hl as SpotLight3D).visible = on


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
	_crash_cd = maxf(0.0, _crash_cd - delta)
	_prev_vel = linear_velocity
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
	if damage >= 100.0:
		force = 0.0
		brk = maxf(brk, 4.0)
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


## Medio tamaño de la caja del coche en (x = ancho/2, y = largo/2).
func body_half_extents() -> Vector2:
	return Vector2(float(_spec.get("half_w", 1.0)), float(_spec.get("length", 4.5)) * 0.5)


func _on_body_entered(other: Node) -> void:
	if _crash_cd > 0.0:
		return
	var other_vel := Vector3.ZERO
	if other is RigidBody3D:
		other_vel = (other as RigidBody3D).linear_velocity
	elif other.get("speed") != null and other.get("heading") != null:
		other_vel = (other.get("heading") as Vector3) * float(other.get("speed"))
	var drop := (_prev_vel - linear_velocity).length()
	var rel := (_prev_vel - other_vel).length()
	var impact := maxf(drop, rel * 0.5)
	if impact < 4.0:
		return
	_crash_cd = 0.3
	var dir := _prev_vel.normalized() if _prev_vel.length() > 0.5 else global_basis.z
	var point := global_position + dir * float(_spec.get("length", 4.5)) * 0.5 + Vector3.UP * 0.5
	if other is Node3D:
		# Punto de contacto aproximado: sobre el borde del coche hacia el otro cuerpo.
		var to_other := ((other as Node3D).global_position - global_position)
		to_other.y = 0.0
		if to_other.length() > 0.1 and to_other.normalized().dot(dir) > 0.2:
			point = global_position + to_other.normalized() * minf(to_other.length() * 0.5, 2.2) + Vector3.UP * 0.5
	var strength := clampf(impact / 25.0, 0.0, 1.0)
	add_damage(impact * 1.6)
	_crumple_body(strength)
	_spawn_debris(point, strength)
	if impact_system != null and impact_system.traffic != null and other is Node3D and impact_system.traffic.cars.has(other):
		impact_system.knock_traffic_car(other as Node3D, _prev_vel * mass * 0.6, point)
	crashed.emit(strength, point, other)


func add_damage(amount: float) -> void:
	damage = clampf(damage + amount, 0.0, 100.0)
	_update_damage_visuals()


## Cambia el color de la carrocería sin reconstruir el coche (ruedas, asiento y
## ocupantes siguen en su sitio).
func repaint(color: Color) -> void:
	body_color = color
	if _body_mesh == null:
		return
	var real_id := RealCarModel.for_style(style)
	if real_id != "" and not RealCarModel.data(real_id).is_empty():
		_body_mesh.mesh = RealCarModel.painted_body(real_id, color)
	else:
		_body_mesh.mesh = CarModel.build(style, color, false)


func repair() -> void:
	damage = 0.0
	_crumple = 0.0
	if _body_mesh:
		_body_mesh.position = Vector3.ZERO
		_body_mesh.rotation = Vector3.ZERO
		_body_mesh.material_overlay = null
	if _smoke:
		_smoke.emitting = false


func _update_damage_visuals() -> void:
	if _body_mesh and damage > 5.0:
		if _dmg_mat == null:
			_dmg_mat = StandardMaterial3D.new()
			_dmg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_dmg_mat.roughness = 1.0
			_dmg_mat.metallic = 0.0
		_dmg_mat.albedo_color = Color(0.05, 0.04, 0.035, clampf(damage / 100.0 * 0.6, 0.0, 0.6))
		_body_mesh.material_overlay = _dmg_mat
	if damage > 60.0:
		if _smoke == null:
			_smoke = CPUParticles3D.new()
			_smoke.amount = 10
			_smoke.lifetime = 1.4
			_smoke.direction = Vector3.UP
			_smoke.spread = 20.0
			_smoke.initial_velocity_min = 1.0
			_smoke.initial_velocity_max = 1.8
			_smoke.gravity = Vector3(0, 0.6, 0)
			_smoke.scale_amount_min = 0.5
			_smoke.scale_amount_max = 1.0
			_smoke.local_coords = false
			var sm := SphereMesh.new()
			sm.radius = 0.25
			sm.height = 0.5
			sm.radial_segments = 6
			sm.rings = 3
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.7, 0.7, 0.72, 0.45)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.material = mat
			_smoke.mesh = sm
			_smoke.position = Vector3(0, 0.95, float(_spec.get("length", 4.5)) * 0.33)
			add_child(_smoke)
		_smoke.emitting = true


func _crumple_body(strength: float) -> void:
	if strength < 0.25 or _body_mesh == null:
		return
	_crumple = minf(_crumple + strength, 1.5)
	var k := _crumple
	_body_mesh.position = Vector3(randf_range(-0.03, 0.03), -0.02 * k, randf_range(-0.04, 0.04)) * k
	_body_mesh.rotation = Vector3(randf_range(-0.03, 0.03), randf_range(-0.04, 0.04), randf_range(-0.04, 0.04)) * k


func _spawn_debris(point: Vector3, strength: float) -> void:
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return
	if _debris_mesh == null:
		_debris_mesh = BoxMesh.new()
		_debris_mesh.size = Vector3(0.08, 0.05, 0.08)
		_debris_mat = StandardMaterial3D.new()
		_debris_mat.albedo_color = Color(0.9, 0.75, 0.35)
		_debris_mat.emission_enabled = true
		_debris_mat.emission = Color(1.0, 0.6, 0.2)
		_debris_mat.emission_energy_multiplier = 1.2
		_debris_mesh.material = _debris_mat
	var p := CPUParticles3D.new()
	p.amount = 20
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.7
	p.mesh = _debris_mesh
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0 + strength * 5.0
	p.gravity = Vector3(0, -12.0, 0)
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	parent.add_child(p)
	p.global_position = point
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
