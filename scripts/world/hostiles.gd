class_name Hostiles
extends Node3D
## Enemigos de misión y de actividades (pandilleros, matones, guardias): peatones Mixamo que
## persiguen y atacan al jugador. Los crea MissionRunner (pasos fight / defend / sneak / chase)
## y el sistema de actividades. Combat los trata como objetivos igual que a los agentes.
## - armed: disparan a media distancia; si no, pegan cuerpo a cuerpo.
## - alert = false: guardias que no reaccionan hasta ver al jugador de cerca o hasta oír disparos.
## - runner = true: huyen del jugador (paso chase); se les "atrapa" al alcanzarlos o derribarlos.

const RUN_SPEED := 4.7
const FLEE_SPEED := 5.5
const SHOOT_RANGE := 26.0
const HOLD_DIST := 9.0
const MELEE_RANGE := 1.5
const SIGHT := 16.0

## Nodo principal (main.gd).
var main
var units: Array = []
var rng := RandomNumberGenerator.new()


class Unit:
	extends CharacterBody3D
	var model: Node3D
	var health: float = 60.0
	var dead: bool = false
	var dead_t: float = 0.0
	var armed: bool = true
	var alert: bool = true
	var runner: bool = false
	var caught: bool = false
	var group: String = ""
	var attack_cd: float = 1.0
	var see_cd: float = 0.0
	var sees: bool = false
	var side: float = 1.0
	var sidestep_t: float = 0.0
	var stuck_t: float = 0.0
	var last_pos: Vector3 = Vector3.ZERO
	var stagger_t: float = 0.0
	var flee_goal: Vector3 = Vector3.INF
	var yaw: float = 0.0


func _ready() -> void:
	rng.seed = 8086


func is_unit(node) -> bool:
	return node is Unit


## Crea un enemigo. `tint` (0-6) elige el color de ropa del modelo: cada banda usa el suyo.
func spawn(pos: Vector3, group: String, armed: bool = true, alert: bool = true, runner: bool = false, tint: int = 4, health: float = 60.0) -> Unit:
	var u := Unit.new()
	u.name = "Hostil"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.33
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	u.add_child(cs)
	if MixamoPerson.available():
		var m := MixamoPerson.new()
		u.add_child(m)
		m.setup({"model": rng.randi() % MixamoPerson.MODELS.size(), "tint": tint, "scale": rng.randf_range(0.97, 1.05), "phase": rng.randf()})
		u.model = m
	else:
		var h := Humanoid.new()
		u.add_child(h)
		h.setup(Humanoid.random_look(rng))
		u.model = h
	u.floor_snap_length = 0.3
	u.group = group
	u.armed = armed
	u.alert = alert
	u.runner = runner
	u.health = health
	u.side = 1.0 if rng.randf() < 0.5 else -1.0
	u.attack_cd = rng.randf_range(0.8, 2.0)
	add_child(u)
	u.global_position = pos + Vector3.UP * 0.25
	u.last_pos = u.global_position
	units.append(u)
	return u


func alive(group: String = "") -> int:
	var n := 0
	for u in units:
		if not u.dead and not u.caught and (group == "" or u.group == group):
			n += 1
	return n


func clear(group: String = "") -> void:
	for i in range(units.size() - 1, -1, -1):
		var u: Unit = units[i]
		if group == "" or u.group == group:
			if is_instance_valid(u):
				u.queue_free()
			units.remove_at(i)


## Disparos o pelea: todos los guardias a menos de `radius` se ponen en alerta.
func alarm(pos: Vector3, radius: float) -> void:
	for u in units:
		if not u.dead and u.global_position.distance_to(pos) < radius:
			u.alert = true


func hurt(u, damage: float, dir: Vector3) -> void:
	if not (u is Unit) or u.dead:
		return
	u.health -= damage
	u.stagger_t = 0.35
	u.alert = true
	alarm(u.global_position, 30.0)
	if u.health > 0.0:
		return
	u.dead = true
	u.dead_t = 0.0
	u.collision_layer = 0
	u.collision_mask = 0
	u.model.call("animate", 0.1, 0.0, false)
	var yaw := atan2(-dir.x, -dir.z)
	var tw: Tween = u.create_tween()
	tw.set_parallel(true)
	tw.tween_property(u.model, "rotation", Vector3(PI * 0.5, yaw, 0.0), 0.35)
	tw.tween_property(u.model, "position:y", 0.25, 0.35)


func _physics_process(delta: float) -> void:
	if main == null or main.state != main.State.PLAYING:
		return
	var focus: Node3D = main.current_vehicle if main.current_vehicle else main.player
	var ppos := focus.global_position
	for i in range(units.size() - 1, -1, -1):
		var u: Unit = units[i]
		if not is_instance_valid(u):
			units.remove_at(i)
			continue
		if u.dead:
			u.dead_t += delta
			if u.dead_t > 20.0:
				u.queue_free()
				units.remove_at(i)
			continue
		_update_unit(u, delta, focus, ppos)


func _update_unit(u: Unit, delta: float, focus: Node3D, ppos: Vector3) -> void:
	var flat := Vector3(ppos.x - u.global_position.x, 0, ppos.z - u.global_position.z)
	var dist := flat.length()
	var dir := flat.normalized() if dist > 0.01 else Vector3.FORWARD
	u.see_cd -= delta
	if u.see_cd <= 0.0:
		u.see_cd = 0.3 + rng.randf() * 0.15
		var ex: Array = [u.get_rid(), main.player.get_rid()]
		if focus is CollisionObject3D:
			ex.append((focus as CollisionObject3D).get_rid())
		u.sees = dist < 60.0 and not main.combat.blocked(u.global_position + Vector3.UP * 1.5, ppos + Vector3.UP * 1.1, ex)
	if not u.alert and u.sees and dist < SIGHT:
		# Solo ve lo que tiene delante (cono amplio); por la espalda se le puede pasar cerca.
		var fwd := Vector3(-sin(u.yaw), 0, -cos(u.yaw))
		if fwd.dot(dir) > 0.2 or dist < 3.0:
			u.alert = true
			alarm(u.global_position, 18.0)
	u.stagger_t = maxf(0.0, u.stagger_t - delta)
	var move := Vector3.ZERO
	var speed := 0.0
	var active: bool = main._gameplay_on and GameState.health > 0.0
	if u.caught or u.stagger_t > 0.0 or not active:
		pass
	elif u.runner:
		# Huye por las calles alejándose del jugador; cambia de destino al llegar.
		if u.flee_goal == Vector3.INF or u.global_position.distance_to(u.flee_goal) < 3.0:
			u.flee_goal = _flee_point(u.global_position, ppos)
		var to := Vector3(u.flee_goal.x - u.global_position.x, 0, u.flee_goal.z - u.global_position.z)
		move = to.normalized()
		speed = FLEE_SPEED
		if dist < 2.0:
			u.caught = true
	elif not u.alert:
		pass
	elif u.armed and u.sees and dist < HOLD_DIST:
		pass
	elif dist > (MELEE_RANGE - 0.3):
		move = dir
		speed = RUN_SPEED
	if speed > 0.0 and u.sidestep_t > 0.0:
		u.sidestep_t -= delta
		move = (move * 0.35 + Vector3(-move.z, 0, move.x) * u.side).normalized()
	u.velocity.x = move.x * speed
	u.velocity.z = move.z * speed
	if u.is_on_floor():
		u.velocity.y = 0.0
	else:
		u.velocity.y -= 9.8 * delta
	u.move_and_slide()
	if speed > 0.0:
		u.stuck_t += delta
		if u.stuck_t > 0.8:
			if u.global_position.distance_to(u.last_pos) < 0.8:
				u.sidestep_t = 1.4
				u.side = -u.side
				if u.runner:
					u.flee_goal = Vector3.INF
			u.stuck_t = 0.0
			u.last_pos = u.global_position
	else:
		u.stuck_t = 0.0
		u.last_pos = u.global_position
	var face := move if speed > 0.0 else (dir if u.alert else Vector3(-sin(u.yaw), 0, -cos(u.yaw)))
	u.yaw = lerp_angle(u.yaw, atan2(-face.x, -face.z), clampf(delta * 9.0, 0.0, 1.0))
	u.model.rotation.y = u.yaw
	u.model.call("animate", delta, speed, true)
	# Ataque.
	if not u.alert or u.runner or u.caught or not active:
		return
	u.attack_cd -= delta
	if u.attack_cd > 0.0:
		return
	var in_car: bool = main.current_vehicle != null
	if u.armed and u.sees and dist < SHOOT_RANGE:
		u.attack_cd = rng.randf_range(1.0, 1.9)
		var from := u.global_position + Vector3.UP * 1.45
		var target := ppos + Vector3.UP * (0.9 if in_car else 1.2)
		var chance := clampf(0.42 - dist * 0.011, 0.1, 0.42)
		if in_car:
			chance *= 0.7
		if not in_car and main.player.crouching:
			chance *= 0.5
		var hit := rng.randf() < chance
		var end := target
		if not hit:
			end = from + (target + Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(-0.5, 0.9), rng.randf_range(-1.4, 1.4)) - from).normalized() * (dist + 6.0)
		main.combat.fx_shot(from + (target - from).normalized() * 0.5, end, -3.0)
		if hit:
			if in_car:
				main.current_vehicle.add_damage(4.0)
				main.damage_player(rng.randf_range(2.0, 4.0))
			else:
				main.damage_player(rng.randf_range(6.0, 10.0))
	elif not in_car and dist < MELEE_RANGE:
		u.attack_cd = rng.randf_range(0.9, 1.4)
		Sfx.play_at(main, u.global_position + Vector3.UP * 1.3, "punch", 0.0, 40.0)
		main.damage_player(rng.randf_range(5.0, 9.0))


## Cruce de calles cercano que queda más lejos del jugador que el enemigo.
func _flee_point(from: Vector3, threat: Vector3) -> Vector3:
	var nodes: Array = main.traffic.graph["nodes"]
	var best := from + (from - threat).normalized() * 40.0
	var best_score := -INF
	for n in nodes:
		var p := Vector3((n as Vector2).x + 7.5, 0.0, (n as Vector2).y + 7.5)
		var d := p.distance_to(from)
		if d < 20.0 or d > 130.0:
			continue
		var score := p.distance_to(threat) - d * 0.6 + rng.randf() * 10.0
		if score > best_score:
			best_score = score
			best = p
	return best
