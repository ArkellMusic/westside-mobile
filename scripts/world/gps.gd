class_name GPS
extends Node
## Navegación GPS sobre el grafo de calles de Westbrook (CityLayout.road_graph()),
## ampliado con la autopista del este (puente, desierto) y el muelle.
##
## Dos rutas independientes:
##  - Misión (AMARILLA): la fija main.gd desde set_marker() cuando un paso de la misión
##    (goto, drive_to, pickup, talk, enter_vehicle...) tiene destino.
##  - Waypoint manual (AZUL): lo pone el jugador tocando el mapa de pausa.
## Si hay ambas, el radar y el mapa dibujan las dos: primero la azul y encima la amarilla
## (la de misión tiene prioridad visual). El waypoint se borra al llegar (< ARRIVE_M).
##
## La ruta se recalcula cada REROUTE_INTERVAL s o si el jugador se aleja más de
## DEVIATION_M del punto donde se calculó.

signal changed

const REROUTE_INTERVAL := 1.0
const DEVIATION_M := 25.0
const ARRIVE_M := 15.0
const MISSION_COLOR := Color("#F2C230")
const WAYPOINT_COLOR := Color("#3D8BFF")
## Nodos extra de la autopista (conectados a Westbrook Blvd, z = 0, en el extremo este).
const HIGHWAY_XS := [370.0, 1300.0, 2600.0, 4200.0]

var player_pos: Vector3 = Vector3.ZERO
## Vector3.INF = sin destino.
var mission_target: Vector3 = Vector3.INF
var waypoint: Vector3 = Vector3.INF
## Pone a false dentro de interiores: no se muestran rutas.
var active: bool = true
var mission_route: PackedVector2Array = PackedVector2Array()
var waypoint_route: PackedVector2Array = PackedVector2Array()

var _astar: AStar2D = AStar2D.new()
var _pts: Array[Vector2] = []
var _edges: Array = [] # [[a, b], ...] (índices de nodo)
var _timer: float = 0.0
var _origin: Vector2 = Vector2.INF


func _init() -> void:
	_build_graph()


func _build_graph() -> void:
	var g := CityLayout.road_graph()
	var nodes: Array = g["nodes"]
	var links: Array = g["links"]
	_pts.clear()
	_edges.clear()
	_astar.clear()
	for n in nodes:
		_add_point(n)
	for i in range(links.size()):
		for j in links[i]:
			if int(j) > i:
				_connect(i, int(j))
	# Autopista: Westbrook Blvd (z = 0) en Eastline Ave -> puente -> desierto.
	var prev := _find(Vector2(CityLayout.EAST_EDGE, CityLayout.HIGHWAY_Z))
	for x in HIGHWAY_XS:
		var k := _add_point(Vector2(float(x), CityLayout.HIGHWAY_Z))
		_connect(prev, k)
		prev = k
	# Muelle: se engancha a la avenida de la playa.
	var ave_x: float = CityLayout.WEST_EDGE
	var a := _find(Vector2(ave_x, CityLayout.STREETS[2][0]))
	var b := _find(Vector2(ave_x, CityLayout.STREETS[3][0]))
	var mid := _split_edge(a, b, Vector2(ave_x, CityLayout.PIER_Z))
	var root := _add_point(Vector2(CityLayout.PIER_FROM_X, CityLayout.PIER_Z))
	_connect(mid, root)
	var tip := _add_point(Vector2(CityLayout.PIER_TO_X + 12.0, CityLayout.PIER_Z))
	_connect(root, tip)


func _add_point(p: Vector2) -> int:
	_pts.append(p)
	var id := _pts.size() - 1
	_astar.add_point(id, p)
	return id


func _connect(a: int, b: int) -> void:
	if not _astar.are_points_connected(a, b):
		_astar.connect_points(a, b, true)
		_edges.append([a, b])


func _find(p: Vector2) -> int:
	for i in range(_pts.size()):
		if _pts[i].distance_to(p) < 0.5:
			return i
	return 0


func _split_edge(a: int, b: int, p: Vector2) -> int:
	_astar.disconnect_points(a, b)
	for i in range(_edges.size()):
		var e: Array = _edges[i]
		if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
			_edges.remove_at(i)
			break
	var m := _add_point(p)
	_connect(a, m)
	_connect(m, b)
	return m


# ------------------------------------------------------------------ Pathfinding

## Ruta por calles de `from` a `to` (plano XZ). Incluye ambos extremos.
## Devuelve un array vacío si no hay ruta.
func find_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var s_snap := _snap(from)
	var t_snap := _snap(to)
	var s := _add_point(s_snap["q"])
	var t := _add_point(t_snap["q"])
	var sa: Array = s_snap["e"]
	var ta: Array = t_snap["e"]
	_astar.connect_points(s, sa[0], true)
	_astar.connect_points(s, sa[1], true)
	_astar.connect_points(t, ta[0], true)
	_astar.connect_points(t, ta[1], true)
	if (sa[0] == ta[0] and sa[1] == ta[1]) or (sa[0] == ta[1] and sa[1] == ta[0]):
		_astar.connect_points(s, t, true)
	var path := _astar.get_point_path(s, t)
	_astar.remove_point(s)
	_astar.remove_point(t)
	_pts.resize(_pts.size() - 2)
	if path.is_empty():
		return PackedVector2Array()
	var out := PackedVector2Array([from])
	for p in path:
		if p.distance_to(out[out.size() - 1]) > 0.05:
			out.append(p)
	if to.distance_to(out[out.size() - 1]) > 0.05:
		out.append(to)
	return out


## Arista del grafo más cercana a p: {q: punto proyectado, e: [a, b]}.
func _snap(p: Vector2) -> Dictionary:
	var best := INF
	var bq := p
	var be: Array = _edges[0]
	for e in _edges:
		var q := Geometry2D.get_closest_point_to_segment(p, _pts[e[0]], _pts[e[1]])
		var d := q.distance_squared_to(p)
		if d < best:
			best = d
			bq = q
			be = e
	return {"q": bq, "e": be}


static func route_length(route: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(route.size() - 1):
		l += route[i].distance_to(route[i + 1])
	return l


# -------------------------------------------------------------------- Destinos

func set_mission_target(pos: Vector3) -> void:
	mission_target = pos
	_origin = Vector2.INF
	_recompute()


func set_waypoint(pos: Vector3) -> void:
	waypoint = Vector3(pos.x, 0.0, pos.z)
	_recompute()


func clear_waypoint() -> void:
	waypoint = Vector3.INF
	waypoint_route = PackedVector2Array()
	changed.emit()


func has_waypoint() -> bool:
	return waypoint != Vector3.INF


## Un toque en el mapa: pone el waypoint, o lo quita si se toca sobre él (radius en metros).
func toggle_waypoint(pos: Vector3, radius: float = 14.0) -> void:
	if has_waypoint() and Vector2(pos.x - waypoint.x, pos.z - waypoint.z).length() <= radius:
		clear_waypoint()
	else:
		set_waypoint(pos)


# --------------------------------------------------------------------- Proceso

func _process(delta: float) -> void:
	update(delta)


func update(delta: float) -> void:
	var p := Vector2(player_pos.x, player_pos.z)
	if has_waypoint() and active and p.distance_to(Vector2(waypoint.x, waypoint.z)) < ARRIVE_M:
		clear_waypoint()
	_timer -= delta
	var deviated := _origin != Vector2.INF and p.distance_to(_origin) > DEVIATION_M
	if _timer <= 0.0 or deviated:
		_recompute()


func _recompute() -> void:
	_timer = REROUTE_INTERVAL
	var p := Vector2(player_pos.x, player_pos.z)
	_origin = p
	mission_route = PackedVector2Array()
	waypoint_route = PackedVector2Array()
	if mission_target != Vector3.INF:
		mission_route = find_route(p, Vector2(mission_target.x, mission_target.z))
	if waypoint != Vector3.INF:
		waypoint_route = find_route(p, Vector2(waypoint.x, waypoint.z))
	changed.emit()


## Ruta lista para dibujar: empieza en la posición actual del jugador y descarta los
## puntos ya recorridos desde el último recálculo.
func display_route(route: PackedVector2Array, from: Vector2) -> PackedVector2Array:
	if not active or route.size() < 2:
		return PackedVector2Array()
	var best := 0
	var bd := INF
	for i in range(mini(route.size() - 1, 6)):
		var d := Geometry2D.get_closest_point_to_segment(from, route[i], route[i + 1]).distance_squared_to(from)
		if d < bd:
			bd = d
			best = i
	var out := PackedVector2Array([from])
	for i in range(best + 1, route.size()):
		if route[i].distance_to(out[out.size() - 1]) > 0.05:
			out.append(route[i])
	return out
