class_name CityLayout
extends RefCounted
## Trazado de Westbrook (South Veyra): calles, manzanas, playa y puntos clave.
## Es la fuente única de verdad para el constructor de la ciudad, el radar, el mapa
## y el tráfico. Coordenadas en metros: X = este, -Z = norte.
##
## Referencia: docs/mapa_concepto.jpg — South Veyra está al suroeste del estado,
## con la playa al oeste y el centro (rascacielos) hacia el noreste.

const AVENUE_WIDTH := 14.0
const BLVD_WIDTH := 16.0
const STREET_WIDTH := 12.0
const SIDEWALK := 4.0

## Avenidas norte-sur: [x, ancho, nombre]
const AVENUES := [
	[-235.0, BLVD_WIDTH, "Veyra Beach Blvd"],
	[-150.0, AVENUE_WIDTH, "Crenwood Ave"],
	[-50.0, AVENUE_WIDTH, "Westbrook Ave"],
	[50.0, AVENUE_WIDTH, "Hollister Ave"],
	[150.0, AVENUE_WIDTH, "Larchmont Ave"],
	[250.0, AVENUE_WIDTH, "Eastline Ave"],
]
## Calles este-oeste: [z, ancho, nombre]
const STREETS := [
	[-200.0, STREET_WIDTH, "Ninth St"],
	[-100.0, STREET_WIDTH, "Kingsley St"],
	[0.0, STREET_WIDTH, "Westbrook Blvd"],
	[100.0, STREET_WIDTH, "Coral St"],
	[200.0, STREET_WIDTH, "Harbor St"],
]

const NORTH_EDGE := -270.0
const SOUTH_EDGE := 270.0
const WEST_EDGE := -235.0
const EAST_EDGE := 250.0

## Playa y océano (al oeste del bulevar).
const BEACH_EAST := -243.0
const SHORE_X := -330.0
const WATER_LEVEL := -0.45

## Muelle que sale de la playa hacia el oeste.
const PIER_Z := 60.0
const PIER_FROM_X := -262.0
const PIER_TO_X := -430.0
const PIER_WIDTH := 9.0
const PIER_HEIGHT := 1.2

## Límites jugables (paredes invisibles).
const PLAY_MIN := Vector2(-440.0, -285.0)
const PLAY_MAX := Vector2(265.0, 285.0)

## Río de Veyra (canal de hormigón al este) y puente de entrada a Westbrook.
const RIVER_X0 := 330.0
const RIVER_X1 := 410.0
const HIGHWAY_Z := 0.0
const HIGHWAY_END_X := 4200.0

## Puntos clave del barrio (misión 01 "Back to Westbrook" y personajes).
const LANDMARKS := {
	"terminal": Vector3(100.0, 0.0, -24.0),
	"bus_bay": Vector3(100.0, 0.0, -3.0),
	"bag": Vector3(104.0, 0.0, -8.6),
	"player_spawn": Vector3(98.0, 0.0, -8.2),
	"big_ray": Vector3(76.0, 0.0, -9.5),
	"ray_car": Vector3(70.0, 0.0, -4.9),
	"veyra_mart": Vector3(-20.0, 0.0, -20.0),
	"mart_stop": Vector3(-20.0, 0.0, -4.9),
	"neighbor": Vector3(-14.0, 0.0, -9.0),
	"coral_checkpoint": Vector3(-150.0, 0.0, 100.0),
	"mack_house": Vector3(-100.0, 0.0, 22.5),
	"mack_house_curb": Vector3(-100.0, 0.0, 4.9),
	"mack_door": Vector3(-100.0, 0.0, 15.0),
	"vargas_garage": Vector3(100.0, 0.0, -122.0),
	"vargas_front": Vector3(100.0, 0.0, -103.0),
	"loco": Vector3(108.0, 0.0, -110.0),
	"dre_corner": Vector3(-59.0, 0.0, 108.0),
	"keisha": Vector3(-41.0, 0.0, -108.0),
	"ghost": Vector3(-62.5, 0.0, 109.5),
	"viper": Vector3(159.0, 0.0, -192.0),
	"beach": Vector3(-290.0, 0.0, 30.0),
	"pier": Vector3(-380.0, 0.0, PIER_Z),
	"bridge": Vector3(370.0, 0.0, 0.0),
	"desert_road": Vector3(2600.0, 0.0, 0.0),
}

## Nombre de zona por manzana (para mapa y ambiente).
const BLOCK_ZONES := {
	"beach": "Frente de playa",
	"commercial": "Distrito comercial",
	"residential": "Westbrook residencial",
}


static func landmark(id: String) -> Vector3:
	return LANDMARKS.get(id, Vector3.ZERO)


static func avenue_xs() -> Array:
	var r: Array = []
	for a in AVENUES:
		r.append(a[0])
	return r


static func street_zs() -> Array:
	var r: Array = []
	for s in STREETS:
		r.append(s[0])
	return r


## Segmentos de calle como diccionarios {a, b, width, name} en el plano XZ.
static func road_segments() -> Array:
	var segs: Array = []
	for a in AVENUES:
		segs.append({"a": Vector2(a[0], NORTH_EDGE), "b": Vector2(a[0], SOUTH_EDGE), "width": a[1], "name": a[2], "axis": "z"})
	for s in STREETS:
		segs.append({"a": Vector2(WEST_EDGE, s[0]), "b": Vector2(EAST_EDGE, s[0]), "width": s[1], "name": s[2], "axis": "x"})
	return segs


## Manzanas: rectángulos entre calles con su tipo de zona.
static func blocks() -> Array:
	var xs := avenue_xs()
	var zs: Array = [NORTH_EDGE]
	zs.append_array(street_zs())
	zs.append(SOUTH_EDGE)
	var widths_x := {}
	for a in AVENUES:
		widths_x[a[0]] = a[1]
	var widths_z := {}
	for s in STREETS:
		widths_z[s[0]] = s[1]
	var result: Array = []
	for i in range(xs.size() - 1):
		for j in range(zs.size() - 1):
			var x0: float = xs[i] + widths_x[xs[i]] * 0.5
			var x1: float = xs[i + 1] - widths_x[xs[i + 1]] * 0.5
			var z0: float = zs[j] + float(widths_z.get(zs[j], 0.0)) * 0.5
			var z1: float = zs[j + 1] - float(widths_z.get(zs[j + 1], 0.0)) * 0.5
			var kind := "residential"
			if i == 0:
				kind = "beach"
			elif zs[j] < -99.0:
				kind = "commercial"
			elif zs[j] < 0.0 and zs[j + 1] <= 0.0:
				kind = "commercial" if i >= 3 else "residential"
			result.append({
				"rect": Rect2(x0, z0, x1 - x0, z1 - z0),
				"kind": kind,
				"col": i,
				"row": j,
				"edge_north": j == 0,
				"edge_south": j == zs.size() - 2,
			})
	return result


## Grafo de intersecciones para el tráfico: {nodes: Array[Vector2], links: Array[Array[int]]}
static func road_graph() -> Dictionary:
	var xs := avenue_xs()
	var zs := street_zs()
	var nodes: Array = []
	var index := {}
	var all_z: Array = [NORTH_EDGE + 8.0]
	all_z.append_array(zs)
	all_z.append(SOUTH_EDGE - 8.0)
	for x in xs:
		for z in all_z:
			index[Vector2(x, z)] = nodes.size()
			nodes.append(Vector2(x, z))
	var links: Array = []
	for n in nodes:
		links.append([])
	# Avenidas: unir nodos consecutivos en z.
	for x in xs:
		for k in range(all_z.size() - 1):
			_link(links, index[Vector2(x, all_z[k])], index[Vector2(x, all_z[k + 1])])
	# Calles: unir nodos consecutivos en x.
	for z in zs:
		for k in range(xs.size() - 1):
			_link(links, index[Vector2(xs[k], z)], index[Vector2(xs[k + 1], z)])
	return {"nodes": nodes, "links": links}


static func _link(links: Array, a: int, b: int) -> void:
	if not (links[a] as Array).has(b):
		(links[a] as Array).append(b)
	if not (links[b] as Array).has(a):
		(links[b] as Array).append(a)


## Ancho de la calle que pasa por un punto del grafo en una dirección dada.
static func road_width_at(dir: Vector2) -> float:
	return STREET_WIDTH if absf(dir.x) > absf(dir.y) else AVENUE_WIDTH


## Nombre de la calle más cercana a una posición (para el HUD).
static func nearest_street_name(p: Vector3) -> String:
	var best := ""
	var best_d := INF
	for s in road_segments():
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b)
		var d := q.distance_to(Vector2(p.x, p.z))
		if d < best_d:
			best_d = d
			best = s["name"]
	if p.x < BEACH_EAST - 4.0:
		return "Playa de South Veyra"
	return best
