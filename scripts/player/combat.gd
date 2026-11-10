class_name Combat
extends Node3D
## Combate del jugador a pie: puños y pistola con apuntado automático (pensado para pantalla
## táctil). Los objetivos son los peatones (Pedestrians) y los agentes (Police).
## También dibuja los efectos compartidos de disparo (fogonazo, trazadora, chispas), que usa
## la policía con fx_shot().

const WEAPONS := ["fist", "pistol"]
const PISTOL_RANGE := 55.0
const PISTOL_DAMAGE := 34.0
const PISTOL_RATE := 0.30
const PISTOL_CONE := 0.86      # cos del semiángulo de apuntado automático (~31 grados)
const PUNCH_RANGE := 1.9
const PUNCH_DAMAGE := 22.0
const PUNCH_RATE := 0.48
const PUNCH_CONE := 0.35

signal weapon_changed(kind: String)

## Nodo principal (main.gd).
var main
var _cd: float = 0.0
var _punch_t: float = 1.0     # segundos desde el último puñetazo
var _punch_side: int = 1
var _aim_t: float = 0.0       # segundos que quedan con el arma levantada
var _empty_warned: bool = false
var _tracer_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D


func _ready() -> void:
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.86, 0.45)
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1.0, 0.8, 0.35)
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func weapon() -> String:
	return GameState.weapon


func set_weapon(kind: String) -> void:
	if not WEAPONS.has(kind):
		kind = "fist"
	GameState.weapon = kind
	_aim_t = 0.0
	_refresh_model()
	weapon_changed.emit(kind)


func cycle_weapon() -> void:
	var i := WEAPONS.find(GameState.weapon)
	set_weapon(WEAPONS[(i + 1) % WEAPONS.size()])


## ¿Lleva el arma a la vista? (la policía dispara antes a alguien armado)
func armed() -> bool:
	return GameState.weapon == "pistol"


func _refresh_model() -> void:
	var p: Player = main.player
	if p and p.model:
		p.model.set_gun(GameState.weapon == "pistol")


## Llamado por main cada fotograma mientras se juega a pie.
func update(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	_punch_t += delta
	_aim_t = maxf(0.0, _aim_t - delta)
	if Controls.just_pressed("weapon"):
		cycle_weapon()
	if GameState.weapon == "pistol":
		var want := Controls.is_down("attack")
		if Controls.just_pressed("attack"):
			want = true
		if want and _cd <= 0.0:
			_fire_pistol()
	elif Controls.just_pressed("attack") and _cd <= 0.0:
		_punch()
	_update_pose()


func reset() -> void:
	_cd = 0.0
	_aim_t = 0.0
	_punch_t = 1.0
	_refresh_model()
	_update_pose()


# ------------------------------------------------------------------ objetivos

func _camera_forward() -> Vector3:
	var yaw: float = main.rig.yaw
	return Vector3(-sin(yaw), 0, -cos(yaw))


## Objetivo más cercano dentro del cono: {"kind": "cop"|"ped", "cop": Node, "ped": int, "pos": Vector3}.
## Los agentes tienen prioridad (son los que disparan).
func find_target(origin: Vector3, dir: Vector3, max_range: float, cos_half: float) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	if main.police:
		for c in main.police.cops:
			if c.dead:
				continue
			var to: Vector3 = c.global_position - origin
			to.y = 0.0
			var dist := to.length()
			if dist > max_range or dist < 0.05:
				continue
			var dot := to.normalized().dot(dir)
			if dot < cos_half:
				continue
			var score := dist * (2.0 - dot) * 0.6
			if score < best_score:
				best_score = score
				best = {"kind": "cop", "cop": c, "pos": c.global_position}
	var pi: int = main.pedestrians.nearest_in_cone(origin, dir, max_range, cos_half)
	if pi >= 0:
		var h: Node3D = main.pedestrians.peds[pi]["node"]
		var to2 := h.global_position - origin
		to2.y = 0.0
		var score2 := to2.length() * (2.0 - to2.normalized().dot(dir))
		if score2 < best_score:
			best = {"kind": "ped", "ped": pi, "pos": h.global_position}
	return best


# --------------------------------------------------------------------- puños

func _punch() -> void:
	var p: Player = main.player
	_cd = PUNCH_RATE
	_punch_t = 0.0
	_punch_side = 1 - _punch_side
	var origin := p.global_position
	var facing := Vector3(-sin(p.face_yaw()), 0, -cos(p.face_yaw()))
	var t := find_target(origin, facing, PUNCH_RANGE, PUNCH_CONE)
	if t.is_empty():
		t = find_target(origin, _camera_forward(), PUNCH_RANGE, PUNCH_CONE)
	if t.is_empty():
		return
	var to: Vector3 = (t["pos"] as Vector3) - origin
	to.y = 0.0
	var dir := to.normalized()
	p.set_facing(atan2(-dir.x, -dir.z))
	# El golpe llega un instante después de empezar el gesto.
	await get_tree().create_timer(0.13).timeout
	if not is_inside_tree() or main.current_vehicle:
		return
	Sfx.play_at(main, origin + dir * 0.8 + Vector3.UP * 1.3, "punch", 2.0, 40.0)
	main.rig.shake(0.12)
	if t["kind"] == "cop":
		var c = t["cop"]
		if is_instance_valid(c):
			main.police.hurt(c, PUNCH_DAMAGE, dir)
	else:
		# Los índices pueden haber cambiado: se vuelve a buscar al peatón de delante.
		var pi: int = main.pedestrians.nearest_in_cone(origin, dir, PUNCH_RANGE + 0.4, 0.2)
		if pi >= 0:
			main.pedestrians.strike(pi, dir, 2.6, 1.7)
	main.pedestrians.panic(origin, 9.0, 5.0)


# -------------------------------------------------------------------- pistola

func _fire_pistol() -> void:
	var p: Player = main.player
	if GameState.ammo <= 0:
		_cd = 0.4
		Sfx.play_at(main, p.global_position + Vector3.UP * 1.3, "click", -4.0, 20.0)
		if not _empty_warned:
			_empty_warned = true
			main.hud.toast("SIN MUNICIÓN", "Los agentes caídos sueltan balas", 3.0)
		return
	_empty_warned = false
	GameState.ammo -= 1
	_cd = PISTOL_RATE
	_aim_t = 1.6
	var fwd := _camera_forward()
	var origin := p.global_position + Vector3.UP * 1.42
	var t := find_target(origin, fwd, PISTOL_RANGE, PISTOL_CONE)
	var dir := fwd
	var aim_pos := Vector3.INF
	if not t.is_empty():
		aim_pos = (t["pos"] as Vector3) + Vector3.UP * 1.15
		dir = (aim_pos - origin).normalized()
	else:
		# Sin objetivo: la bala sigue la cámara (un poco por encima del horizonte de la mira).
		var pitch: float = main.rig.pitch
		dir = (fwd * cos(pitch + 0.2) + Vector3.UP * sin(pitch + 0.2)).normalized()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	p.set_facing(atan2(-flat.x, -flat.z))
	var muzzle := origin + flat * 0.55
	var end := origin + dir * PISTOL_RANGE
	var hit := _ray(origin, end, [p.get_rid()])
	var hit_cop = null
	if not hit.is_empty():
		end = hit["position"]
		if main.police and main.police.is_cop(hit["collider"]):
			hit_cop = hit["collider"]
	if hit_cop != null:
		main.police.hurt(hit_cop, PISTOL_DAMAGE, flat)
	elif not t.is_empty():
		var d_target := origin.distance_to(aim_pos)
		if hit.is_empty() or origin.distance_to(end) > d_target - 0.6:
			end = aim_pos
			if t["kind"] == "cop" and is_instance_valid(t["cop"]):
				main.police.hurt(t["cop"], PISTOL_DAMAGE, flat)
			elif t["kind"] == "ped":
				main.pedestrians.strike(int(t["ped"]), flat, 2.2, 1.2)
		else:
			_spark(end)
	elif not hit.is_empty():
		_spark(end)
	fx_shot(muzzle, end, 0.0)
	main.rig.shake(0.16)
	main.pedestrians.panic(p.global_position, 45.0, 9.0)
	main.on_gunfire()


func _ray(from: Vector3, to: Vector3, exclude: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(q)


## ¿Hay un muro entre los dos puntos? (ignora a los cuerpos de `exclude`)
func blocked(from: Vector3, to: Vector3, exclude: Array) -> bool:
	return not _ray(from, to, exclude).is_empty()


# -------------------------------------------------------------------- efectos

## Fogonazo con luz, trazadora y sonido de un disparo de `from` a `to`.
func fx_shot(from: Vector3, to: Vector3, volume_db: float) -> void:
	Sfx.play_at(main, from, "shot", volume_db, 160.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.4)
	light.light_energy = 3.5
	light.omni_range = 7.0
	light.shadow_enabled = false
	add_child(light)
	light.global_position = from
	var flash := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.32, 0.32)
	qm.material = _flash_mat
	flash.mesh = qm
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	flash.global_position = from
	var len := from.distance_to(to)
	var tracer: MeshInstance3D = null
	if len > 1.5:
		tracer = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.018, 0.018, minf(len, 26.0))
		bm.material = _tracer_mat
		tracer.mesh = bm
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tracer)
		var dir := (to - from).normalized()
		var mid := from + dir * (len - bm.size.z * 0.5) if len > 26.0 else from.lerp(to, 0.5)
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		tracer.global_transform = Transform3D(Basis.looking_at(dir, up), mid)
	await get_tree().create_timer(0.06).timeout
	if is_instance_valid(light):
		light.queue_free()
	if is_instance_valid(flash):
		flash.queue_free()
	if tracer and is_instance_valid(tracer):
		tracer.queue_free()


## Chispas y polvo donde la bala da en un muro o en el suelo.
func _spark(pos: Vector3) -> void:
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.amount = 10
	ps.lifetime = 0.35
	ps.direction = Vector3.UP
	ps.spread = 70.0
	ps.initial_velocity_min = 1.5
	ps.initial_velocity_max = 4.0
	ps.gravity = Vector3(0, -9.0, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.radial_segments = 4
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.8, 0.7)
	sm.material = m
	ps.mesh = sm
	add_child(ps)
	ps.global_position = pos
	ps.emitting = true
	Sfx.play_at(main, pos, "impact", -6.0, 40.0)
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(ps):
		ps.queue_free()


# ---------------------------------------------------------------------- poses

func _update_pose() -> void:
	var p: Player = main.player
	if p == null or p.model == null:
		return
	var o: Dictionary = {}
	if GameState.weapon == "pistol" and _aim_t > 0.0:
		# Brazo derecho extendido al frente; el izquierdo sigue el paso.
		o["arm"] = [null, 1.5]
		o["elbow"] = [null, 0.08]
		o["arm_out"] = [null, -0.12]
		o["torso_y"] = -0.18
	elif _punch_t < 0.34:
		var k := _punch_t / 0.34
		var ext := sin(clampf(k * 1.6, 0.0, 1.0) * PI)   # 0 -> 1 -> 0
		var s := _punch_side
		var arm := [null, null]
		var elbow := [null, null]
		var out := [null, null]
		arm[s] = lerpf(0.7, 1.5, ext)
		elbow[s] = lerpf(1.9, 0.1, ext)
		out[s] = -0.15
		arm[1 - s] = 0.75
		elbow[1 - s] = 1.9
		out[1 - s] = -0.2
		o["arm"] = arm
		o["elbow"] = elbow
		o["arm_out"] = out
		o["torso_y"] = (0.35 if s == 1 else -0.35) * ext
	p.model.overlay = o
