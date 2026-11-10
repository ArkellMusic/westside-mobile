class_name Police
extends Node3D
## Respuesta policial según el nivel de búsqueda (main.wanted, 0-6 estrellas).
## - 1 estrella: los agentes persiguen a pie e intentan detener al jugador (DETENIDO).
## - 2 o más (o si el jugador va armado y dispara): abren fuego.
## Llegan en coches patrulla que aparcan cerca con las luces y la sirena puestas.
## Reconocimiento (CrimeSystem): los agentes solo persiguen si RECONOCEN al jugador, es decir,
## si lo ven a menos de crime.recognition_range() (lejos si encaja con la descripción de ropa
## y coche; muy cerca si se ha cambiado). Si no, buscan alrededor del último lugar conocido.
## Las estrellas bajan mientras nadie lo reconoce (lo gestiona main con `any_seen`).

const COUNT := [0, 2, 3, 4, 5, 6, 6]
const MAX_PATROLS := 3
const RUN_SPEED := 4.9
const SHOOT_RANGE := 30.0
const HOLD_DIST := 11.0
const SIGHT := 48.0
const AMMO_DROP := 12
const SEARCH_SPEED := 2.3
const SEARCH_RADIUS := 16.0

## Nodo principal (main.gd).
var main
var cops: Array = []          # Cop (vivos y caídos)
var patrols: Array = []       # {"node": Node3D, "red": OmniLight3D, "blue": OmniLight3D}
var any_seen: bool = false    # algún agente reconoce al jugador ahora (o hace un instante)
var _known_t: float = 0.0     # segundos que la patrulla sigue sabiendo dónde está
var rng := RandomNumberGenerator.new()
var _spawn_cd: float = 0.0
var _blink: float = 0.0
var _calm_t: float = 0.0


class Cop:
	extends CharacterBody3D
	var model: Humanoid
	var health: float = 60.0
	var dead: bool = false
	var dead_t: float = 0.0
	var shoot_cd: float = 1.2
	var see_cd: float = 0.0
	var sees: bool = false
	var arrest_t: float = 0.0
	var side: float = 1.0
	var sidestep_t: float = 0.0
	var stuck_t: float = 0.0
	var last_pos: Vector3 = Vector3.ZERO
	var aim_t: float = 0.0
	var stagger_t: float = 0.0
	var search_off: Vector3 = Vector3.ZERO
	var search_t: float = 0.0


func _ready() -> void:
	rng.seed = 5150


func is_cop(node) -> bool:
	return node is Cop


## ¿Algún agente tiene al jugador a la vista ahora mismo? (un delito delante de él se
## denuncia al instante, sin testigos)
func sees_player_now() -> bool:
	for c in cops:
		if not c.dead and c.sees:
			return true
	return false


func alive_count() -> int:
	var n := 0
	for c in cops:
		if not c.dead:
			n += 1
	return n


## Quita agentes y patrullas (nueva partida, detención, hospital).
func clear() -> void:
	for c in cops:
		if is_instance_valid(c):
			c.queue_free()
	cops.clear()
	for p in patrols:
		if is_instance_valid(p["node"]):
			(p["node"] as Node).queue_free()
	patrols.clear()
	any_seen = false
	_known_t = 0.0
	_spawn_cd = 0.0


func _focus() -> Node3D:
	return main.current_vehicle if main.current_vehicle else main.player


# ------------------------------------------------------------------ aparición

## Punto de la red de calles a 38-75 m del jugador, mejor fuera de la vista de la cámara.
func _spawn_point(ppos: Vector3) -> Dictionary:
	var graph: Dictionary = main.traffic.graph
	var nodes: Array = graph["nodes"]
	var cam: Camera3D = get_viewport().get_camera_3d()
	var cf := -cam.global_transform.basis.z if cam else Vector3.FORWARD
	var p2 := Vector2(ppos.x, ppos.z)
	var best := -1
	var best_score := INF
	for i in nodes.size():
		var n: Vector2 = nodes[i]
		var d := n.distance_to(p2)
		if d < 38.0 or d > 75.0:
			continue
		var to := Vector3(n.x - ppos.x, 0, n.y - ppos.z).normalized()
		var score := d + (40.0 if to.dot(cf) > 0.45 else 0.0) + rng.randf() * 12.0
		if score < best_score:
			best_score = score
			best = i
	if best < 0:
		var a := rng.randf() * TAU
		return {"pos": ppos + Vector3(cos(a), 0, sin(a)) * 42.0, "dir": Vector3(-cos(a), 0, -sin(a)), "road": false}
	var links: Array = graph["links"][best]
	var nb: Vector2 = nodes[links[rng.randi() % links.size()]]
	var a2: Vector2 = nodes[best]
	var dir2 := (nb - a2).normalized()
	var p := a2 + dir2 * 10.0
	return {"pos": Vector3(p.x, 0.0, p.y), "dir": Vector3(dir2.x, 0, dir2.y), "road": true}


func _spawn_unit() -> void:
	# Si no saben dónde está el jugador, acuden al último lugar conocido.
	var ppos := _focus().global_position
	if _known_t <= 0.0 and main.crime.last_known.distance_to(ppos) < 200.0:
		ppos = main.crime.last_known
	var sp := _spawn_point(ppos)
	var pos: Vector3 = sp["pos"]
	var dir: Vector3 = sp["dir"]
	var right := Vector3(-dir.z, 0, dir.x)
	if bool(sp["road"]) and patrols.size() < MAX_PATROLS:
		_spawn_patrol(pos, dir)
	var need: int = int(COUNT[clampi(main.wanted, 0, 6)]) - alive_count()
	for i in mini(2, need):
		_spawn_cop(pos + right * (1.9 if i == 0 else -1.9) + dir * (0.6 * i))


func _spawn_cop(pos: Vector3) -> void:
	var c := Cop.new()
	c.name = "Agente"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.33
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	c.add_child(cs)
	c.model = Humanoid.new()
	c.add_child(c.model)
	c.model.setup(GameData.character_look("cop_reyes"))
	c.floor_snap_length = 0.3
	c.side = 1.0 if rng.randf() < 0.5 else -1.0
	c.shoot_cd = rng.randf_range(0.8, 1.8)
	add_child(c)
	c.global_position = pos + Vector3.UP * 0.25
	c.last_pos = c.global_position
	cops.append(c)


func _spawn_patrol(pos: Vector3, dir: Vector3) -> void:
	var root := StaticBody3D.new()
	root.name = "Patrulla"
	var mi := MeshInstance3D.new()
	var half := Vector3(0.95, 0.7, 2.4)
	if RealCarModel.available("patrol"):
		mi.mesh = RealCarModel.full_mesh("patrol", Color.WHITE)
		var d := RealCarModel.data("patrol")
		half = Vector3(float(d["half_w"]), float(d["height"]) * 0.5, float(d["length"]) * 0.5)
	else:
		mi.mesh = CarModel.build(5, Color.WHITE, true)
	root.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = half * 2.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = half.y + 0.1
	root.add_child(cs)
	var red := OmniLight3D.new()
	red.light_color = Color(1.0, 0.08, 0.08)
	var blue := OmniLight3D.new()
	blue.light_color = Color(0.1, 0.25, 1.0)
	for l in [red, blue]:
		l.omni_range = 16.0
		l.light_energy = 5.0
		l.shadow_enabled = false
		root.add_child(l)
	red.position = Vector3(-0.45, half.y * 2.0 + 0.25, 0.0)
	blue.position = Vector3(0.45, half.y * 2.0 + 0.25, 0.0)
	var siren := AudioStreamPlayer3D.new()
	siren.stream = Sfx.stream("siren")
	siren.volume_db = -7.0
	siren.max_distance = 140.0
	siren.unit_size = 14.0
	root.add_child(siren)
	add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), pos + Vector3.UP * 0.04)
	siren.play()
	patrols.append({"node": root, "red": red, "blue": blue})


# ----------------------------------------------------------------- simulación

func _physics_process(delta: float) -> void:
	_blink += delta
	for p in patrols:
		var on := fmod(_blink, 0.5) < 0.25
		(p["red"] as OmniLight3D).visible = on
		(p["blue"] as OmniLight3D).visible = not on
	if main == null or main.state != main.State.PLAYING:
		return
	var wanted: int = main.wanted
	var focus := _focus()
	var ppos := focus.global_position
	_known_t = maxf(0.0, _known_t - delta)
	any_seen = _known_t > 0.0 and wanted > 0
	if wanted > 0 and main._gameplay_on and main.interiors.inside < 0:
		_calm_t = 0.0
		_spawn_cd -= delta
		if _spawn_cd <= 0.0 and alive_count() < int(COUNT[clampi(wanted, 0, 6)]):
			_spawn_cd = 3.0
			_spawn_unit()
	else:
		_calm_t += delta
	for i in range(cops.size() - 1, -1, -1):
		var c: Cop = cops[i]
		if not is_instance_valid(c):
			cops.remove_at(i)
			continue
		if c.dead:
			c.dead_t += delta
			if c.dead_t > 14.0:
				c.queue_free()
				cops.remove_at(i)
			continue
		var to := ppos - c.global_position
		var dist := Vector2(to.x, to.z).length()
		if dist > 120.0 or (wanted == 0 and (_calm_t > 9.0 or dist > 60.0)):
			c.queue_free()
			cops.remove_at(i)
			continue
		_update_cop(c, delta, wanted, focus, dist)
	# Las patrullas se retiran cuando ya no hay búsqueda y el jugador se ha alejado.
	for i in range(patrols.size() - 1, -1, -1):
		var node: Node3D = patrols[i]["node"]
		var far := node.global_position.distance_to(ppos)
		if far > 150.0 or (wanted == 0 and (_calm_t > 9.0 or far > 70.0)):
			node.queue_free()
			patrols.remove_at(i)


func _update_cop(c: Cop, delta: float, wanted: int, focus: Node3D, dist: float) -> void:
	var ppos := focus.global_position
	var flat := Vector3(ppos.x - c.global_position.x, 0, ppos.z - c.global_position.z)
	var dir := flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	c.see_cd -= delta
	if c.see_cd <= 0.0:
		c.see_cd = 0.3 + rng.randf() * 0.15
		c.sees = dist < SIGHT and not main.combat.blocked(c.global_position + Vector3.UP * 1.5, ppos + Vector3.UP * 1.1, [c.get_rid(), main.player.get_rid(), focus.get_rid()] if focus is CollisionObject3D else [c.get_rid(), main.player.get_rid()])
	if c.sees and wanted > 0 and dist < main.crime.recognition_range():
		# Lo reconoce: avisa por radio (toda la patrulla lo sabe durante unos segundos).
		_known_t = 3.0
		any_seen = true
		main.crime.on_recognised(ppos)
	var known := _known_t > 0.0
	var in_car: bool = main.current_vehicle != null
	var lethal: bool = wanted >= 2 and known
	var speed := 0.0
	var move := Vector3.ZERO
	c.stagger_t = maxf(0.0, c.stagger_t - delta)
	if wanted == 0 or c.stagger_t > 0.0:
		pass   # la búsqueda ha terminado (o acaba de recibir un golpe): se queda en el sitio
	elif not known:
		# Busca a pie alrededor del último lugar conocido, cambiando de punto cada pocos segundos.
		c.search_t -= delta
		if c.search_t <= 0.0:
			c.search_t = rng.randf_range(4.0, 7.0)
			var a := rng.randf() * TAU
			c.search_off = Vector3(cos(a), 0, sin(a)) * rng.randf_range(3.0, SEARCH_RADIUS)
		var goal: Vector3 = main.crime.last_known + c.search_off
		var to_goal := Vector3(goal.x - c.global_position.x, 0, goal.z - c.global_position.z)
		if to_goal.length() > 1.5:
			dir = to_goal.normalized()
			move = dir
			if c.sidestep_t > 0.0:
				c.sidestep_t -= delta
				move = (dir * 0.35 + Vector3(-dir.z, 0, dir.x) * c.side).normalized()
			speed = RUN_SPEED if to_goal.length() > 30.0 else SEARCH_SPEED
	elif lethal and c.sees and dist < HOLD_DIST:
		pass   # a distancia de tiro: se planta y dispara
	elif dist > 1.25:
		move = dir
		if c.sidestep_t > 0.0:
			c.sidestep_t -= delta
			move = (dir * 0.35 + Vector3(-dir.z, 0, dir.x) * c.side).normalized()
		speed = RUN_SPEED
	c.velocity.x = move.x * speed
	c.velocity.z = move.z * speed
	if c.is_on_floor():
		c.velocity.y = 0.0
	else:
		c.velocity.y -= 9.8 * delta
	c.move_and_slide()
	# Atascado contra una esquina: rodea por un lado durante un momento.
	if speed > 0.0:
		c.stuck_t += delta
		if c.stuck_t > 0.8:
			if c.global_position.distance_to(c.last_pos) < 0.8:
				c.sidestep_t = 1.4
				c.side = -c.side
			c.stuck_t = 0.0
			c.last_pos = c.global_position
	else:
		c.stuck_t = 0.0
		c.last_pos = c.global_position
	var face := move if speed > 0.0 and c.sidestep_t > 0.0 else dir
	c.model.rotation.y = lerp_angle(c.model.rotation.y, atan2(-face.x, -face.z), clampf(delta * 9.0, 0.0, 1.0))
	# Disparo.
	c.aim_t = maxf(0.0, c.aim_t - delta)
	if lethal and c.sees and dist < SHOOT_RANGE and main._gameplay_on and GameState.health > 0.0:
		c.shoot_cd -= delta
		c.aim_t = 0.6
		if c.shoot_cd <= 0.0:
			c.shoot_cd = rng.randf_range(0.9, 1.7) - 0.08 * float(wanted)
			_cop_fire(c, focus, dist, in_car)
	c.model.set_gun(lethal)
	if c.aim_t > 0.0:
		c.model.overlay = {"arm": [null, 1.5], "elbow": [null, 0.08], "arm_out": [null, -0.12]}
	else:
		c.model.overlay = {}
	c.model.animate(delta, speed, true)
	# Detención con una estrella: hay que quedarse al alcance del agente un momento.
	if wanted == 1 and known and not in_car and dist < 1.7 and main._gameplay_on and not main.interiors.busy:
		c.arrest_t += delta
		if c.arrest_t > 1.6:
			c.arrest_t = 0.0
			main.busted()
	else:
		c.arrest_t = maxf(0.0, c.arrest_t - delta * 2.0)


func _cop_fire(c: Cop, focus: Node3D, dist: float, in_car: bool) -> void:
	var from := c.global_position + Vector3.UP * 1.45
	var target := focus.global_position + Vector3.UP * (0.9 if in_car else 1.2)
	var chance := clampf(0.5 - dist * 0.011, 0.12, 0.5)
	var vel := Vector3.ZERO
	if focus is CharacterBody3D:
		vel = (focus as CharacterBody3D).velocity
	elif focus is RigidBody3D:
		vel = (focus as RigidBody3D).linear_velocity
	if vel.length() > 5.0:
		chance *= 0.6
	if in_car:
		chance *= 0.8
	var hit := rng.randf() < chance
	var end := target
	if not hit:
		end += Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(-0.6, 0.9), rng.randf_range(-1.4, 1.4))
		end = from + (end - from).normalized() * (dist + 6.0)
	main.combat.fx_shot(from + (target - from).normalized() * 0.5, end, -3.0)
	if hit:
		if in_car and main.current_vehicle:
			main.current_vehicle.add_damage(4.0)
			main.damage_player(rng.randf_range(2.0, 4.0))
		else:
			main.damage_player(rng.randf_range(7.0, 11.0))


## Daño a un agente (puñetazo o bala del jugador). Si cae, sube la búsqueda.
func hurt(c, damage: float, dir: Vector3) -> void:
	if not (c is Cop) or c.dead:
		return
	c.health -= damage
	c.stagger_t = 0.35
	c.sees = true
	_known_t = 4.0
	main.crime.on_recognised(_focus().global_position)
	if main.wanted < 2:
		main.set_wanted(2)
	else:
		main.refresh_wanted()
	if c.health > 0.0:
		return
	c.dead = true
	c.dead_t = 0.0
	c.collision_layer = 0
	c.collision_mask = 0
	c.model.overlay = {}
	c.model.animate(0.1, 0.0, false)
	var yaw := atan2(-dir.x, -dir.z)
	var tw: Tween = c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c.model, "rotation", Vector3(PI * 0.5, yaw, 0.0), 0.35)
	tw.tween_property(c.model, "position:y", 0.22, 0.35)
	main.set_wanted(maxi(main.wanted + 1, 3))
	GameState.ammo = mini(GameState.ammo + AMMO_DROP, GameState.MAX_AMMO)
	main.hud.toast("+%d BALAS" % AMMO_DROP, "", 1.6)
