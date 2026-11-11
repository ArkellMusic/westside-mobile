class_name Activities
extends Node
## Actividades del mundo abierto (fuera de las misiones de historia). Cada una tiene un punto
## de inicio marcado en el radar; se empieza con el botón de acción y paga dinero y respeto.
## - Contrarreloj callejera: recorrer los puntos de control en coche antes de que acabe el tiempo.
## - Reparto: llevar paquetes del Veyra Mart a cuatro casas con el reloj en marcha.
## - Taxi: recoger pasajeros y dejarlos en su destino; se cobra por distancia.
## - Guerra de bandas: limpiar una esquina de los Redline Kings en tres oleadas.

const DEFS := [
	{"id": "race", "name": "Contrarreloj callejera", "mark": "C", "color": Color(0.95, 0.5, 0.1), "node": [200.0, 0.0]},
	{"id": "delivery", "name": "Reparto", "mark": "E", "color": Color(0.3, 0.75, 0.9), "node": [-20.0, -34.0]},
	{"id": "taxi", "name": "Taxi", "mark": "X", "color": Color(0.95, 0.85, 0.15), "node": [128.0, -12.0]},
	{"id": "turf", "name": "Guerra de bandas", "mark": "G", "color": Color(0.8, 0.2, 0.25), "node": [100.0, -200.0]},
]

## Nodo principal (main.gd).
var main
var active: String = ""
var rng := RandomNumberGenerator.new()
var _abort: bool = false
var best_race: float = 0.0


func _ready() -> void:
	rng.randomize()


func start_pos(d: Dictionary) -> Vector3:
	return main.mission_point(d["node"], true)


func radar_markers(from: Vector3) -> Array:
	var out: Array = []
	if active != "" or main.runner.running:
		return out
	for d in DEFS:
		var p := start_pos(d)
		if Vector2(p.x - from.x, p.z - from.z).length() < 170.0:
			out.append({"pos": p, "color": d["color"], "label": d["mark"]})
	return out


## {label, action} si el jugador está en el inicio de una actividad (vacío si no).
func interaction(pos: Vector3) -> Dictionary:
	if active != "" or main.runner.running:
		return {}
	for d in DEFS:
		var p := start_pos(d)
		if Vector2(pos.x - p.x, pos.z - p.z).length() < 4.0:
			var def: Dictionary = d
			return {"label": String(d["name"]), "action": func() -> void: start(String(def["id"]))}
	return {}


func start(id: String) -> void:
	if active != "" or main.runner.running:
		return
	active = id
	_abort = false
	match id:
		"race":
			await _race()
		"delivery":
			await _delivery()
		"taxi":
			await _taxi()
		"turf":
			await _turf()
	active = ""
	main.hostiles.clear("activity")
	main.hud.set_hint("")
	main.set_marker(Vector3.INF)
	main._offer_next_mission()
	if main._next_mission.is_empty():
		main.hud.set_objective("Explora Westbrook")


func stop() -> void:
	_abort = true


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _focus() -> Vector3:
	var n: Node3D = main.current_vehicle if main.current_vehicle else main.player
	return n.global_position


func _gone() -> bool:
	return _abort or main.state != main.State.PLAYING or main.runner.running


## Espera hasta llegar a `pos` (en coche si need_car) o hasta que el tiempo llegue a cero.
## `clock` es [segundos restantes]; devuelve true si se llegó.
func _reach(pos: Vector3, radius: float, need_car: bool, clock: Array, hint: String) -> bool:
	main.set_marker(pos)
	while not _gone():
		await get_tree().process_frame
		clock[0] = float(clock[0]) - get_process_delta_time()
		main.hud.set_hint("%s · %d s" % [hint, maxi(0, int(float(clock[0])))])
		if float(clock[0]) <= 0.0:
			return false
		if _flat(_focus(), pos) < radius and (not need_car or main.current_vehicle != null):
			return true
	return false


# --------------------------------------------------------------- contrarreloj

func _race() -> void:
	var hud: HUD = main.hud
	hud.set_objective("Contrarreloj callejera: consigue un coche")
	while main.current_vehicle == null and not _gone():
		hud.set_hint("Sube a cualquier coche para empezar.")
		await get_tree().process_frame
	if _gone():
		return
	# Circuito por los cruces del barrio (se ajustan solos a la calzada).
	var route := [[200.0, 100.0], [100.0, 100.0], [0.0, 100.0], [-100.0, 100.0], [-200.0, 100.0], [-200.0, 0.0], [-200.0, -100.0],
		[-100.0, -100.0], [0.0, -100.0], [100.0, -100.0], [200.0, -100.0], [200.0, 0.0]]
	var total := 0.0
	var prev := _focus()
	var pts: Array = []
	for r in route:
		var p: Vector3 = main.mission_point(r, false)
		pts.append(p)
		total += _flat(prev, p)
		prev = p
	var par := total / 17.0 + 12.0
	var clock := [par]
	hud.set_objective("Contrarreloj: %d puntos de control en %d s" % [pts.size(), int(par)])
	hud.toast("¡YA!", "Sigue las marcas", 1.5)
	var t0 := Time.get_ticks_msec()
	for i in pts.size():
		var ok: bool = await _reach(pts[i], 13.0, true, clock, "Control %d / %d" % [i + 1, pts.size()])
		if not ok:
			if not _gone():
				hud.toast("SIN TIEMPO", "Te quedaste en el control %d" % (i + 1), 3.0)
			return
		clock[0] = float(clock[0]) + 3.0
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	var prize := 300 + int(maxf(0.0, float(clock[0])) * 12.0)
	GameState.add_money(prize)
	var record := best_race <= 0.0 or took < best_race
	if record:
		best_race = took
	hud.toast("CONTRARRELOJ SUPERADA  +$%d" % prize, "%.1f s%s" % [took, " · nuevo récord" if record else ""], 4.0)


# --------------------------------------------------------------------- reparto

func _delivery() -> void:
	var hud: HUD = main.hud
	hud.set_objective("Reparto: lleva 4 paquetes antes de que se acabe el tiempo")
	var clock := [150.0]
	var earned := 0
	var blocks: Array = []
	for b in CityLayout.blocks():
		if b["kind"] == "residential":
			blocks.append(b)
	for i in 4:
		var blk: Dictionary = blocks[rng.randi() % blocks.size()]
		var r: Rect2 = blk["rect"]
		var dest: Vector3 = main.mission_point([r.get_center().x + rng.randf_range(-40.0, 40.0), r.get_center().y + rng.randf_range(-40.0, 40.0)], true)
		var ok: bool = await _reach(dest, 4.0, false, clock, "Paquete %d / 4" % (i + 1))
		if not ok:
			if not _gone():
				hud.toast("REPARTO FALLIDO", "Entregaste %d de 4 · +$%d" % [i, earned], 3.0)
			return
		earned += 60
		GameState.add_money(60)
		clock[0] = float(clock[0]) + 20.0
		hud.toast("ENTREGADO  +$60", "", 1.2)
	var bonus := int(maxf(0.0, float(clock[0])) * 2.0)
	GameState.add_money(bonus)
	hud.toast("REPARTO COMPLETO", "+$%d con propina" % (earned + bonus), 4.0)


# ------------------------------------------------------------------------ taxi

func _taxi() -> void:
	var hud: HUD = main.hud
	hud.set_objective("Taxi: consigue un coche")
	while main.current_vehicle == null and not _gone():
		hud.set_hint("Sube a cualquier coche. Bájate cuando quieras dejarlo.")
		await get_tree().process_frame
	var fares := 0
	var earned := 0
	var nodes: Array = main.traffic.graph["nodes"]
	while not _gone() and main.current_vehicle != null:
		var a: Vector2 = nodes[rng.randi() % nodes.size()]
		var pick: Vector3 = main.mission_point([a.x + 6.0, a.y + 6.0], true)
		hud.set_objective("Taxi: recoge al pasajero")
		var clock := [120.0]
		var ok: bool = await _reach(pick, 9.0, true, clock, "Pasajero esperando")
		if not ok or main.current_vehicle == null:
			break
		var car: Car = main.current_vehicle
		while car.linear_velocity.length() > 2.0 and not _gone():
			hud.set_hint("Frena para que suba.")
			await get_tree().process_frame
		var b: Vector2 = nodes[rng.randi() % nodes.size()]
		var guard := 0
		while b.distance_to(a) < 150.0 and guard < 20:
			b = nodes[rng.randi() % nodes.size()]
			guard += 1
		var dest: Vector3 = main.mission_point([b.x, b.y], false)
		var dist := _flat(pick, dest)
		clock = [dist / 11.0 + 20.0]
		hud.set_objective("Taxi: lleva al pasajero a su destino")
		ok = await _reach(dest, 10.0, true, clock, "Carrera en curso")
		if not ok:
			if not _gone() and main.current_vehicle != null:
				hud.toast("EL PASAJERO SE HA BAJADO", "Tardaste demasiado", 2.5)
			continue
		var fare := 40 + int(dist * 0.35) + int(maxf(0.0, float(clock[0])) * 1.5)
		fares += 1
		earned += fare
		GameState.add_money(fare)
		hud.toast("CARRERA COBRADA  +$%d" % fare, "%d carreras · $%d en total" % [fares, earned], 2.5)
	if fares > 0 and not _gone():
		hud.toast("FIN DEL TURNO DE TAXI", "%d carreras · $%d" % [fares, earned], 3.5)


# ------------------------------------------------------------ guerra de bandas

func _turf() -> void:
	var hud: HUD = main.hud
	var at: Vector3 = main.mission_point([150.0, -200.0], true)
	hud.set_objective("Guerra de bandas: echa a los Redline Kings de su esquina")
	main.set_marker(at)
	while _flat(_focus(), at) > 45.0 and not _gone():
		await get_tree().process_frame
	GameState.ammo = mini(GameState.ammo + 36, GameState.MAX_AMMO)
	for w in 3:
		if _gone():
			return
		hud.toast("OLEADA %d / 3" % (w + 1), "", 1.8)
		for i in 3 + w:
			var along := rng.randf_range(5.0, 16.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			var pos := at + (Vector3(along, 0, 0) if i % 2 == 0 else Vector3(0, 0, along))
			main.hostiles.spawn(pos, "activity", i % 3 != 2, true, false, 2, 60.0)
		while main.hostiles.alive("activity") > 0 and not _gone():
			hud.set_hint("Enemigos: %d" % main.hostiles.alive("activity"))
			await get_tree().process_frame
			if GameState.health <= 0.0:
				hud.toast("TE HAN ECHADO", "Los Redline Kings conservan su esquina", 3.0)
				return
	if _gone():
		return
	GameState.add_money(700)
	GameState.change_reputation("westbrook_saints", 5)
	GameState.change_reputation("redline_kings", -6)
	hud.toast("ESQUINA TOMADA  +$700", "+5 de respeto con los Saints", 4.0)
