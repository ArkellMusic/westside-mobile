class_name Pedestrians
extends Node3D
## Peatones que dan la vuelta a las manzanas por la acera. Se apartan si un coche
## se les echa encima. Sin física para que sean baratos en móvil.

signal pedestrian_hit(position: Vector3, speed: float)
## Un testigo ha terminado de llamar a la policía (payload de CrimeSystem.commit).
signal witness_report(payload: Dictionary)

var peds: Array = []
var downed: Array = []   # peatones atropellados (volando / tumbados)
var vehicle: Node3D = null   # coche del jugador cuando conduce
var danger: Array = []  # nodos peligrosos (coche del jugador)
var rng := RandomNumberGenerator.new()
var _use_mixamo: bool = false


func setup(count: int) -> void:
	rng.seed = 404
	_use_mixamo = MixamoPerson.available()
	var blocks := CityLayout.blocks()
	for i in count:
		var blk: Dictionary = blocks[rng.randi() % blocks.size()]
		var r: Rect2 = (blk["rect"] as Rect2).grow(-CityLayout.SIDEWALK * 0.5)
		var h: Node3D = _make_person()
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		if rng.randf() < 0.5:
			corners.reverse()
		var start := rng.randi() % 4
		var t := rng.randf()
		var a: Vector2 = corners[start]
		var b: Vector2 = corners[(start + 1) % 4]
		var p := a.lerp(b, t)
		h.position = Vector3(p.x, 0.12, p.y)
		peds.append({"node": h, "corners": corners, "next": (start + 1) % 4, "speed": rng.randf_range(1.1, 1.6), "dodge": 0.0, "dodger": rng.randf() < 0.5})


## Peatón realista de Mixamo; Humanoid (procedural) como respaldo si falta el asset.
func _make_person() -> Node3D:
	if _use_mixamo:
		var m := MixamoPerson.new()
		add_child(m)
		m.setup(MixamoPerson.random_look(rng))
		return m
	var h := Humanoid.new()
	add_child(h)
	h.setup(Humanoid.random_look(rng))
	return h


## Escala propia del peatón (variación de MixamoPerson); 1 para Humanoid.
func _bs(h: Node3D) -> float:
	var b = h.get("base_scale")
	return float(b) if b != null else 1.0


func _physics_process(delta: float) -> void:
	_check_hits()
	_update_downed(delta)
	for ped in peds:
		var h = ped["node"]
		var target: Vector2 = ped["corners"][ped["next"]]
		var p := Vector2(h.position.x, h.position.z)
		var d := target - p
		if d.length() < 0.3:
			ped["next"] = (int(ped["next"]) + 1) % 4
			continue
		var dir := d.normalized()
		var speed: float = ped["speed"]
		if float(ped.get("calling", 0.0)) > 0.0:
			# Testigo: se queda quieto hablando por teléfono hasta dar el aviso.
			ped["calling"] = float(ped["calling"]) - delta
			h.animate(delta, 0.0, true)
			if float(ped["calling"]) <= 0.0:
				_end_call(ped)
				witness_report.emit(ped.get("report", {}))
				ped["panic"] = 6.0
			continue
		if float(ped.get("panic", 0.0)) > 0.0:
			ped["panic"] = float(ped["panic"]) - delta
			speed = 5.4
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


func _active_car() -> Car:
	if vehicle is Car and vehicle.is_visible_in_tree():
		return vehicle as Car
	for n in danger:
		if n is Car:
			return n as Car
	return null


func _check_hits() -> void:
	var car := _active_car()
	if car == null:
		return
	var vel := car.linear_velocity
	var spd := vel.length()
	if spd < 3.0:
		return
	var ext := car.body_half_extents()
	var inv := car.global_transform.affine_inverse()
	var cp := car.global_position
	for i in range(peds.size() - 1, -1, -1):
		var h: Node3D = peds[i]["node"]
		var dx := h.global_position.x - cp.x
		var dz := h.global_position.z - cp.z
		if dx * dx + dz * dz > 36.0:
			continue
		var l := inv * h.global_position
		if absf(l.x) < ext.x + 0.3 and absf(l.z) < ext.y + 0.3 and l.y > -1.0 and l.y < 2.0:
			_knock_down(i, vel, spd)


func _knock_down(i: int, car_vel: Vector3, spd: float, lift: float = 3.0) -> void:
	var ped: Dictionary = peds[i]
	peds.remove_at(i)
	if float(ped.get("calling", 0.0)) > 0.0:
		_end_call(ped)   # testigo silenciado: no llega a dar el aviso
	var h = ped["node"]
	var v := car_vel * 0.8 + Vector3.UP * lift
	downed.append({"node": h, "ped": ped, "vel": v, "state": 0, "t": 0.0,
		"spin": Vector3(rng.randf_range(4.0, 8.0), rng.randf_range(-3.0, 3.0), 0.0)})
	h.animate(0.1, 0.0, false)
	pedestrian_hit.emit(h.global_position, spd)


## Golpe o disparo del jugador: el peatón `i` cae en la dirección `dir`.
func strike(i: int, dir: Vector3, force: float, lift: float) -> void:
	if i < 0 or i >= peds.size():
		return
	var d := Vector3(dir.x, 0, dir.z).normalized()
	_knock_down(i, d * force / 0.8, force, lift)


## Índice del peatón más cercano dentro de un cono (dir plano, cos del semiángulo); -1 si no hay.
func nearest_in_cone(origin: Vector3, dir: Vector3, max_range: float, cos_half: float) -> int:
	var best := -1
	var best_score := INF
	for i in peds.size():
		var h: Node3D = peds[i]["node"]
		var to := h.global_position - origin
		to.y = 0.0
		var dist := to.length()
		if dist > max_range or dist < 0.05:
			continue
		var dot := to.normalized().dot(dir)
		if dot < cos_half:
			continue
		var score := dist * (2.0 - dot)
		if score < best_score:
			best_score = score
			best = i
	return best


## Pánico (disparos, pelea): los peatones cercanos corren por su acera alejándose de `center`.
func panic(center: Vector3, radius: float, time: float = 7.0) -> void:
	var c2 := Vector2(center.x, center.z)
	for ped in peds:
		var h: Node3D = ped["node"]
		if Vector2(h.position.x, h.position.z).distance_to(c2) > radius:
			continue
		if float(ped.get("panic", 0.0)) <= 0.0:
			var corners: Array = ped["corners"]
			var nxt := int(ped["next"])
			var prv := (nxt + 3) % 4
			if (corners[prv] as Vector2).distance_to(c2) > (corners[nxt] as Vector2).distance_to(c2):
				var rev := corners.duplicate()
				rev.reverse()
				ped["corners"] = rev
				ped["next"] = 3 - prv
		ped["panic"] = time


## Hasta `count` peatones a menos de `radius` de `pos` sacan el móvil y llaman durante `time` s.
## Al terminar se emite witness_report(payload). Devuelve cuántos han empezado a llamar.
func call_witnesses(pos: Vector3, radius: float, count: int, time: float, payload: Dictionary) -> int:
	var c2 := Vector2(pos.x, pos.z)
	var cands: Array = []
	for ped in peds:
		if float(ped.get("calling", 0.0)) > 0.0:
			continue
		var h: Node3D = ped["node"]
		var d := Vector2(h.position.x, h.position.z).distance_to(c2)
		if d <= radius and d > 2.5:
			cands.append([d, ped])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var n := 0
	for c in cands:
		if n >= count:
			break
		var ped: Dictionary = c[1]
		ped["calling"] = time + 0.8 * n
		ped["report"] = payload
		ped["panic"] = 0.0
		var h: Node3D = ped["node"]
		if h.has_method("pose_idle_stance"):
			h.call("pose_idle_stance", "phone")
		var mark := Label3D.new()
		mark.name = "Testigo"
		mark.text = "LLAMANDO AL 911"
		mark.font_size = 40
		mark.pixel_size = 0.004
		mark.outline_size = 10
		mark.modulate = Color(1.0, 0.85, 0.25)
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.no_depth_test = true
		mark.position = Vector3(0, 2.15, 0)
		h.add_child(mark)
		n += 1
	return n


func _end_call(ped: Dictionary) -> void:
	ped["calling"] = 0.0
	var h: Node3D = ped["node"]
	var mark := h.get_node_or_null("Testigo")
	if mark:
		mark.queue_free()
	if h.has_method("set_seated"):
		h.call("set_seated", false)


## Persona que sale corriendo desde `pos` (conductor al que le roban el coche).
func add_runner(pos: Vector3, threat: Vector3) -> void:
	var best: Dictionary = {}
	var best_d := INF
	var p2 := Vector2(pos.x, pos.z)
	for blk in CityLayout.blocks():
		var r: Rect2 = (blk["rect"] as Rect2).grow(-CityLayout.SIDEWALK * 0.5)
		var q := Vector2(clampf(p2.x, r.position.x, r.end.x), clampf(p2.y, r.position.y, r.end.y))
		var dd := q.distance_to(p2)
		if dd < best_d:
			best_d = dd
			best = {"r": r}
	if best.is_empty():
		return
	var r2: Rect2 = best["r"]
	var h: Node3D = _make_person()
	h.position = Vector3(pos.x, 0.12, pos.z)
	var corners := [r2.position, Vector2(r2.end.x, r2.position.y), r2.end, Vector2(r2.position.x, r2.end.y)]
	var far := 0
	var t2 := Vector2(threat.x, threat.z)
	for i in 4:
		if (corners[i] as Vector2).distance_to(t2) > (corners[far] as Vector2).distance_to(t2):
			far = i
	peds.append({"node": h, "corners": corners, "next": far, "speed": rng.randf_range(1.1, 1.6), "dodge": 0.0, "dodger": false, "panic": 9.0})


func _update_downed(delta: float) -> void:
	for i in range(downed.size() - 1, -1, -1):
		var d: Dictionary = downed[i]
		var h = d["node"]
		d["t"] = float(d["t"]) + delta
		match int(d["state"]):
			0:
				var v: Vector3 = d["vel"]
				v.y -= 12.0 * delta
				d["vel"] = v
				h.position += v * delta
				var sp: Vector3 = d["spin"]
				h.rotation.x += sp.x * delta
				h.rotation.y += sp.y * delta
				h.animate(delta, 6.0, false)
				if h.position.y <= 0.12 and float(d["t"]) > 0.15:
					var ly = h.get("lie_y")
					h.position.y = float(ly) if ly != null else 0.2
					h.rotation = Vector3(PI * 0.5, h.rotation.y, 0.0)
					d["state"] = 1
					d["t"] = 0.0
			1:
				if float(d["t"]) > 8.0:
					d["state"] = 2
					d["t"] = 0.0
			2:
				var k := clampf(1.0 - float(d["t"]) / 0.6, 0.0, 1.0)
				h.scale = Vector3.ONE * _bs(h) * maxf(k, 0.01)
				if float(d["t"]) >= 0.6:
					_respawn(d["ped"])
					downed.remove_at(i)


func _player_pos() -> Vector3:
	var car := _active_car()
	if car:
		return car.global_position
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam else Vector3.ZERO


func _respawn(ped: Dictionary) -> void:
	var h = ped["node"]
	var blocks := CityLayout.blocks()
	var pp := _player_pos()
	var p := Vector2.ZERO
	var corners: Array = []
	var start := 0
	for attempt in 8:
		var blk: Dictionary = blocks[rng.randi() % blocks.size()]
		var r: Rect2 = (blk["rect"] as Rect2).grow(-CityLayout.SIDEWALK * 0.5)
		corners = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		start = rng.randi() % 4
		p = (corners[start] as Vector2).lerp(corners[(start + 1) % 4], rng.randf())
		if Vector2(pp.x, pp.z).distance_to(p) > 60.0:
			break
	h.scale = Vector3.ONE * _bs(h)
	h.rotation = Vector3.ZERO
	h.position = Vector3(p.x, 0.12, p.y)
	ped["corners"] = corners
	ped["next"] = (start + 1) % 4
	ped["dodge"] = 0.0
	ped["panic"] = 0.0
	ped["dodger"] = rng.randf() < 0.5
	peds.append(ped)
