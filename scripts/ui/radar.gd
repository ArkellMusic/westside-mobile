class_name Radar
extends Control
## Radar OVALADO estilo mapa de GTA SA: tierra beige, parques verdes, agua azul, edificios
## blancos y calles negras. El mapa gira para que la dirección de la cámara quede arriba
## y se mueve suavemente. Cubre todo el mundo: Westbrook, playa y muelle, río y puente,
## autopista hasta el desierto y montañas (fuera de lo dibujado = tierra de desierto).
## Convención: yaw 0 mira hacia -Z (norte). Mundo (x, z) -> pantalla = rel.rotated(view_yaw).

const DESERT_COLOR := Color("#B9A27B")
const OCEAN_COLOR := Color("#6F93C2")
const SAND_COLOR := Color("#E2D2A4")
const PARK_COLOR := Color("#5C8B3A")
const PLAZA_COLOR := Color("#CFC7B5")
const ROAD_COLOR := Color("#17171A")
const ROAD_EDGE_COLOR := Color("#6A6256")
const BUILDING_COLOR := Color("#F4F3EE")
const BUILDING_EDGE := Color("#A9A69C")
const PIER_COLOR := Color("#7A5A3A")
const MOUNTAIN_COLOR := Color("#8C7A5E")
const BORDER_COLOR := Color.BLACK
const BORDER_W := 9.0
const ROUTE_W := 4.0
## Crestas de montaña (centro z o x, semiancho): de city_builder._build_mountains().
const MOUNTAIN_RECTS := [
	Rect2(-2200.0, -1920.0, 5000.0, 840.0),
	Rect2(-1600.0, -1310.0, 3000.0, 520.0),
	Rect2(920.0, -900.0, 760.0, 740.0),
	Rect2(920.0, 160.0, 760.0, 740.0),
]

var player_pos: Vector3 = Vector3.ZERO:
	set(v):
		player_pos = v
		if not _has_pos:
			_disp_pos = v
			_has_pos = true
var player_heading: float = 0.0:
	set(v):
		player_heading = v
		queue_redraw()
var view_yaw: float = 0.0:
	set(v):
		view_yaw = v
		if not _has_yaw:
			_disp_yaw = v
			_has_yaw = true
## Elementos de {pos: Vector3, color: Color, label: String}.
var markers: Array = []:
	set(v):
		markers = v
		queue_redraw()
## Huellas de edificios en XZ (Rect2.position = (x, z)).
var footprints: Array = []:
	set(v):
		footprints = v
		queue_redraw()
## Radio horizontal del radar en metros (a pie). En coche se amplía con la velocidad.
var range_m: float = 120.0:
	set(v):
		range_m = maxf(20.0, v)
## Velocidad actual del jugador (m/s) para el zoom dinámico.
var speed_mps: float = 0.0
var gps: GPS = null

var _has_pos: bool = false
var _has_yaw: bool = false
var _disp_pos: Vector3 = Vector3.ZERO
var _disp_yaw: float = 0.0
var _zoom_m: float = -1.0
var _roads: Array = []
var _blocks: Array = []
var _ell_poly: PackedVector2Array = PackedVector2Array()
var _ell_key: Vector2 = Vector2(-1, -1)


func _init() -> void:
	custom_minimum_size = Vector2(350, 230)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_roads = CityLayout.road_segments()
	_blocks = CityLayout.blocks()
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var k := 1.0 - exp(-delta * 14.0)
	_disp_pos = _disp_pos.lerp(player_pos, k)
	_disp_yaw = lerp_angle(_disp_yaw, view_yaw, 1.0 - exp(-delta * 9.0))
	var want := range_m * (1.0 + clampf(speed_mps / 28.0, 0.0, 1.0) * 0.9)
	if _zoom_m < 0.0:
		_zoom_m = want
	_zoom_m = lerpf(_zoom_m, want, 1.0 - exp(-delta * 2.5))
	queue_redraw()


func _radii() -> Vector2:
	return Vector2(size.x * 0.5 - BORDER_W * 0.5 - 2.0, size.y * 0.5 - BORDER_W * 0.5 - 2.0)


func _ellipse(rad: Vector2) -> PackedVector2Array:
	if rad != _ell_key or _ell_poly.is_empty():
		_ell_key = rad
		_ell_poly = PackedVector2Array()
		for i in range(72):
			var a := TAU * float(i) / 72.0
			_ell_poly.append(Vector2(cos(a) * rad.x, sin(a) * rad.y))
	return _ell_poly


## Posición de mundo (x, z) -> posición relativa al centro del radar, en píxeles.
func _to_local(x: float, z: float, ppm: float) -> Vector2:
	return (Vector2(x - _disp_pos.x, z - _disp_pos.z)).rotated(_disp_yaw) * ppm


## Lleva un punto al borde de la elipse (escala radial) si cae fuera de `rad`.
static func clamp_to_ellipse(p: Vector2, rad: Vector2) -> Vector2:
	var q := sqrt((p.x / rad.x) * (p.x / rad.x) + (p.y / rad.y) * (p.y / rad.y))
	if q <= 1.0:
		return p
	return p / q


func _draw() -> void:
	var rad := _radii()
	if rad.x <= 8.0 or rad.y <= 8.0:
		return
	var center := size * 0.5
	var ppm := rad.x / (_zoom_m if _zoom_m > 0.0 else range_m)
	var ell := _ellipse(rad)
	draw_set_transform(center, 0.0, Vector2.ONE)

	# Tierra / desierto (todo lo que no está dibujado)
	draw_colored_polygon(ell, DESERT_COLOR)

	# Montañas
	for mr in MOUNTAIN_RECTS:
		_fill_world_rect(mr, MOUNTAIN_COLOR, ppm, ell)
	# Océano, playa, río
	_fill_world_rect(Rect2(-4000.0, -4000.0, 4000.0 + CityLayout.SHORE_X, 8000.0), OCEAN_COLOR, ppm, ell)
	_fill_world_rect(Rect2(CityLayout.SHORE_X, -4000.0, CityLayout.BEACH_EAST - CityLayout.SHORE_X, 8000.0), SAND_COLOR, ppm, ell)
	_fill_world_rect(Rect2(CityLayout.RIVER_X0, -4000.0, CityLayout.RIVER_X1 - CityLayout.RIVER_X0, 8000.0), OCEAN_COLOR, ppm, ell)

	# Manzanas: parques verdes (residencial), plazas grises (comercial) y paseo de arena
	for blk in _blocks:
		var bd: Dictionary = blk
		var col := PARK_COLOR
		match String(bd.get("kind", "residential")):
			"commercial":
				col = PLAZA_COLOR
			"beach":
				col = SAND_COLOR
		_fill_world_rect(bd["rect"], col, ppm, ell)

	# Muelle
	var pier := Rect2(CityLayout.PIER_TO_X, CityLayout.PIER_Z - CityLayout.PIER_WIDTH * 0.5, CityLayout.PIER_FROM_X - CityLayout.PIER_TO_X, CityLayout.PIER_WIDTH)
	_fill_world_rect(pier, PIER_COLOR, ppm, ell)

	# Calles (borde tenue + negro) y autopista
	for pass_i in range(2):
		for seg in _roads:
			var s: Dictionary = seg
			_road_line(s["a"], s["b"], float(s["width"]), pass_i, ppm, rad)
		_road_line(Vector2(CityLayout.EAST_EDGE, CityLayout.HIGHWAY_Z), Vector2(CityLayout.HIGHWAY_END_X, CityLayout.HIGHWAY_Z), 16.0, pass_i, ppm, rad)

	# Edificios
	var reach := (_zoom_m if _zoom_m > 0.0 else range_m) * 1.5
	for fp in footprints:
		var rect: Rect2 = fp
		var cw := Vector2(rect.position.x + rect.size.x * 0.5 - _disp_pos.x, rect.position.y + rect.size.y * 0.5 - _disp_pos.z)
		if absf(cw.x) > reach or absf(cw.y) > reach:
			continue
		var pts := PackedVector2Array([
			_to_local(rect.position.x, rect.position.y, ppm),
			_to_local(rect.end.x, rect.position.y, ppm),
			_to_local(rect.end.x, rect.end.y, ppm),
			_to_local(rect.position.x, rect.end.y, ppm),
		])
		_draw_clipped(pts, BUILDING_COLOR, ell)

	# Rutas GPS (azul debajo, misión amarilla encima)
	if gps != null and gps.active:
		var me := Vector2(player_pos.x, player_pos.z)
		_draw_route(gps.display_route(gps.waypoint_route, me), GPS.WAYPOINT_COLOR, ppm, rad)
		_draw_route(gps.display_route(gps.mission_route, me), GPS.MISSION_COLOR, ppm, rad)

	var font := UITheme.bold_font()
	# Marcadores (misión, hospital, policía...) y waypoint
	var all_markers: Array = markers.duplicate()
	if gps != null and gps.active and gps.has_waypoint():
		all_markers.append({"pos": gps.waypoint, "color": GPS.WAYPOINT_COLOR, "label": ""})
	for m in all_markers:
		var md: Dictionary = m
		var mp: Vector3 = md.get("pos", Vector3.ZERO)
		var col2: Color = md.get("color", UITheme.GOLD)
		var lbl: String = String(md.get("label", ""))
		var p := _to_local(mp.x, mp.z, ppm)
		var lim := rad - Vector2(13.0, 13.0)
		var on_edge := false
		if clamp_to_ellipse(p, lim) != p:
			p = clamp_to_ellipse(p, lim)
			on_edge = true
		var dot_r := 9.0 if not on_edge else 8.0
		draw_circle(p, dot_r + 2.5, Color(0, 0, 0, 0.9))
		draw_circle(p, dot_r, col2)
		if lbl != "":
			var fs := 14
			var w := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var txt_col := Color(0, 0, 0) if col2.get_luminance() > 0.5 else Color(1, 1, 1)
			draw_string(font, p + Vector2(-w * 0.5, fs * 0.36), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)

	# Jugador: flecha blanca en el centro
	var ang := _disp_yaw - player_heading
	var tri := PackedVector2Array([Vector2(0, -15), Vector2(10, 11), Vector2(0, 5), Vector2(-10, 11)])
	for i in range(tri.size()):
		tri[i] = tri[i].rotated(ang)
	var outline := PackedVector2Array(tri)
	outline.append(tri[0])
	draw_polyline(outline, Color.BLACK, 5.0, true)
	draw_colored_polygon(tri, Color.WHITE)

	# Borde negro grueso y "N"
	var ring := PackedVector2Array(ell)
	ring.append(ell[0])
	draw_polyline(ring, BORDER_COLOR, BORDER_W, true)
	var nd := Vector2(sin(_disp_yaw), -cos(_disp_yaw))
	var north := clamp_to_ellipse(nd * 10000.0, rad)
	draw_circle(north, 13.0, Color.BLACK)
	var nfs := 17
	var nw := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
	draw_string(font, north + Vector2(-nw * 0.5, nfs * 0.36), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _road_line(wa: Vector2, wb: Vector2, width: float, pass_i: int, ppm: float, rad: Vector2) -> void:
	var a := _to_local(wa.x, wa.y, ppm)
	var b := _to_local(wb.x, wb.y, ppm)
	var clipped := _clip_segment_ellipse(a, b, rad)
	if clipped.size() != 2:
		return
	var w := maxf(3.5, width * ppm * 0.9)
	if pass_i == 0:
		draw_line(clipped[0], clipped[1], ROAD_EDGE_COLOR, w + 2.5, true)
	else:
		draw_line(clipped[0], clipped[1], ROAD_COLOR, w, true)


func _draw_route(route: PackedVector2Array, color: Color, ppm: float, rad: Vector2) -> void:
	if route.size() < 2:
		return
	var segs: Array = []
	var prev := Vector2.INF
	for p in route:
		var l := _to_local(p.x, p.y, ppm)
		if prev != Vector2.INF:
			var c := _clip_segment_ellipse(prev, l, rad - Vector2(1.5, 1.5))
			if c.size() == 2:
				segs.append(c)
		prev = l
	for c in segs:
		draw_line(c[0], c[1], Color(0, 0, 0, 0.6), ROUTE_W + 3.0, true)
	for c in segs:
		draw_circle(c[0], (ROUTE_W + 3.0) * 0.5, Color(0, 0, 0, 0.6))
		draw_circle(c[1], (ROUTE_W + 3.0) * 0.5, Color(0, 0, 0, 0.6))
	for c in segs:
		draw_line(c[0], c[1], color, ROUTE_W, true)
		draw_circle(c[0], ROUTE_W * 0.5, color)
		draw_circle(c[1], ROUTE_W * 0.5, color)


func _fill_world_rect(rect: Rect2, color: Color, ppm: float, ell: PackedVector2Array) -> void:
	var pts := PackedVector2Array([
		_to_local(rect.position.x, rect.position.y, ppm),
		_to_local(rect.end.x, rect.position.y, ppm),
		_to_local(rect.end.x, rect.end.y, ppm),
		_to_local(rect.position.x, rect.end.y, ppm),
	])
	_draw_clipped(pts, color, ell)


func _draw_clipped(pts: PackedVector2Array, color: Color, ell: PackedVector2Array) -> void:
	# Rechazo rápido por caja
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	var rad := _ell_key
	if mx.x < -rad.x or mn.x > rad.x or mx.y < -rad.y or mn.y > rad.y:
		return
	var inside := true
	for p in pts:
		if (p.x / rad.x) * (p.x / rad.x) + (p.y / rad.y) * (p.y / rad.y) > 0.97:
			inside = false
			break
	if inside:
		draw_colored_polygon(pts, color)
		return
	var result: Array[PackedVector2Array] = Geometry2D.intersect_polygons(pts, ell)
	for poly in result:
		if poly.size() < 3 or Geometry2D.is_polygon_clockwise(poly):
			continue
		draw_colored_polygon(poly, color)


## Recorta a-b a la elipse de radios `rad` centrada en el origen (escalando y a un círculo).
## Devuelve [p0, p1] o un array vacío si queda fuera.
static func _clip_segment_ellipse(a: Vector2, b: Vector2, rad: Vector2) -> PackedVector2Array:
	var k := rad.x / rad.y
	var c := _clip_segment(Vector2(a.x, a.y * k), Vector2(b.x, b.y * k), rad.x)
	if c.size() != 2:
		return c
	return PackedVector2Array([Vector2(c[0].x, c[0].y / k), Vector2(c[1].x, c[1].y / k)])


## Recorta el segmento a-b al círculo de radio r centrado en el origen.
static func _clip_segment(a: Vector2, b: Vector2, r: float) -> PackedVector2Array:
	var d := b - a
	var qa := d.dot(d)
	if qa < 0.000001:
		return PackedVector2Array()
	var qb := 2.0 * a.dot(d)
	var qc := a.dot(a) - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc <= 0.0:
		return PackedVector2Array()
	var sq := sqrt(disc)
	var t0 := maxf(0.0, (-qb - sq) / (2.0 * qa))
	var t1 := minf(1.0, (-qb + sq) / (2.0 * qa))
	if t0 >= t1:
		return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])
