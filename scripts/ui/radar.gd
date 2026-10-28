class_name Radar
extends Control
## Minimapa circular. El mapa gira para que la dirección de la cámara quede arriba.
## Convención: yaw 0 mira hacia -Z (norte). Mundo (x, z) -> pantalla = rel.rotated(view_yaw).

const OCEAN_COLOR := Color(0.10, 0.27, 0.46)
const SAND_COLOR := Color(0.72, 0.65, 0.46)
const LAND_COLOR := Color(0.16, 0.17, 0.19)
const ROAD_COLOR := Color(0.70, 0.71, 0.74)
const FOOTPRINT_COLOR := Color(0.08, 0.08, 0.10)
const PIER_COLOR := Color(0.45, 0.32, 0.2)

var player_pos: Vector3 = Vector3.ZERO:
	set(v):
		player_pos = v
		queue_redraw()
var player_heading: float = 0.0:
	set(v):
		player_heading = v
		queue_redraw()
var view_yaw: float = 0.0:
	set(v):
		view_yaw = v
		queue_redraw()
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
var range_m: float = 140.0:
	set(v):
		range_m = maxf(20.0, v)
		queue_redraw()

var _roads: Array = []
var _circle_poly: PackedVector2Array = PackedVector2Array()
var _circle_r: float = -1.0


func _init() -> void:
	custom_minimum_size = Vector2(210, 210)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_roads = CityLayout.road_segments()
	resized.connect(queue_redraw)


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - 4.0


func _circle(r: float) -> PackedVector2Array:
	if absf(r - _circle_r) > 0.01 or _circle_poly.is_empty():
		_circle_r = r
		_circle_poly = PackedVector2Array()
		for i in range(48):
			var a := TAU * float(i) / 48.0
			_circle_poly.append(Vector2(cos(a), sin(a)) * r)
	return _circle_poly


## Posición de mundo (x, z) -> posición relativa al centro del radar, en píxeles.
func _to_local(x: float, z: float, ppm: float) -> Vector2:
	return (Vector2(x - player_pos.x, z - player_pos.z)).rotated(view_yaw) * ppm


func _draw() -> void:
	var r := _radius()
	if r <= 4.0:
		return
	var center := size * 0.5
	var ppm := r / range_m
	var circle := _circle(r)
	draw_set_transform(center, 0.0, Vector2.ONE)

	# Fondo
	draw_circle(Vector2.ZERO, r, LAND_COLOR)

	# Océano, arena, río y muelle (rectángulos del mundo recortados al círculo)
	_fill_world_rect(Rect2(-3000.0, -3000.0, 3000.0 + CityLayout.SHORE_X, 6000.0), OCEAN_COLOR, ppm, circle)
	_fill_world_rect(Rect2(CityLayout.SHORE_X, -3000.0, CityLayout.BEACH_EAST - CityLayout.SHORE_X, 6000.0), SAND_COLOR, ppm, circle)
	_fill_world_rect(Rect2(CityLayout.RIVER_X0, -3000.0, CityLayout.RIVER_X1 - CityLayout.RIVER_X0, 6000.0), OCEAN_COLOR, ppm, circle)
	var pier := Rect2(CityLayout.PIER_TO_X, CityLayout.PIER_Z - CityLayout.PIER_WIDTH * 0.5, CityLayout.PIER_FROM_X - CityLayout.PIER_TO_X, CityLayout.PIER_WIDTH)
	_fill_world_rect(pier, PIER_COLOR, ppm, circle)

	# Calles (segmentos recortados matemáticamente)
	for seg in _roads:
		var s: Dictionary = seg
		var a: Vector2 = _to_local((s["a"] as Vector2).x, (s["a"] as Vector2).y, ppm)
		var b: Vector2 = _to_local((s["b"] as Vector2).x, (s["b"] as Vector2).y, ppm)
		var clipped := _clip_segment(a, b, r - 1.0)
		if clipped.size() == 2:
			var w := maxf(2.5, float(s["width"]) * ppm)
			draw_line(clipped[0], clipped[1], ROAD_COLOR, w, true)

	# Edificios
	for fp in footprints:
		var rect: Rect2 = fp
		var c := _to_local(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.5, ppm)
		if c.length() > r:
			continue
		var pts := PackedVector2Array([
			_to_local(rect.position.x, rect.position.y, ppm),
			_to_local(rect.end.x, rect.position.y, ppm),
			_to_local(rect.end.x, rect.end.y, ppm),
			_to_local(rect.position.x, rect.end.y, ppm),
		])
		var inside := true
		for p in pts:
			if p.length() > r - 1.0:
				inside = false
				break
		if inside:
			draw_colored_polygon(pts, FOOTPRINT_COLOR)
		else:
			_draw_clipped(pts, FOOTPRINT_COLOR, circle)

	# Marcadores
	var font := UITheme.bold_font()
	for m in markers:
		var md: Dictionary = m
		var mp: Vector3 = md.get("pos", Vector3.ZERO)
		var col: Color = md.get("color", UITheme.GOLD)
		var lbl: String = String(md.get("label", ""))
		var p := _to_local(mp.x, mp.z, ppm)
		var lim := r - 11.0
		var on_edge := false
		if p.length() > lim:
			p = p.normalized() * lim
			on_edge = true
		var dot_r := 8.0 if not on_edge else 7.0
		draw_circle(p, dot_r + 2.0, Color(0, 0, 0, 0.8))
		draw_circle(p, dot_r, col)
		if lbl != "":
			var fs := 13
			var w := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var txt_col := Color(0, 0, 0) if col.get_luminance() > 0.5 else Color(1, 1, 1)
			draw_string(font, p + Vector2(-w * 0.5, fs * 0.36), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)

	# Jugador: flecha en el centro
	var ang := view_yaw - player_heading
	var tri := PackedVector2Array([Vector2(0, -14), Vector2(10, 11), Vector2(0, 5), Vector2(-10, 11)])
	for i in range(tri.size()):
		tri[i] = tri[i].rotated(ang)
	draw_colored_polygon(tri, Color.WHITE)
	var outline := PackedVector2Array(tri)
	outline.append(tri[0])
	draw_polyline(outline, Color(0, 0, 0, 0.9), 2.0, true)

	# Anillo dorado y "N"
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(0, 0, 0, 0.7), 8.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, UITheme.GOLD, 4.0, true)
	var north := Vector2(sin(view_yaw), -cos(view_yaw)) * (r - 14.0)
	draw_circle(north, 12.0, Color(0.05, 0.05, 0.07, 0.95))
	draw_arc(north, 12.0, 0.0, TAU, 20, UITheme.GOLD, 2.0, true)
	var nfs := 16
	var nw := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
	draw_string(font, north + Vector2(-nw * 0.5, nfs * 0.36), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(1, 0.35, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _fill_world_rect(rect: Rect2, color: Color, ppm: float, circle: PackedVector2Array) -> void:
	var pts := PackedVector2Array([
		_to_local(rect.position.x, rect.position.y, ppm),
		_to_local(rect.end.x, rect.position.y, ppm),
		_to_local(rect.end.x, rect.end.y, ppm),
		_to_local(rect.position.x, rect.end.y, ppm),
	])
	_draw_clipped(pts, color, circle)


func _draw_clipped(pts: PackedVector2Array, color: Color, circle: PackedVector2Array) -> void:
	var result: Array[PackedVector2Array] = Geometry2D.intersect_polygons(pts, circle)
	for poly in result:
		if poly.size() >= 3 and not Geometry2D.is_polygon_clockwise(poly):
			draw_colored_polygon(poly, color)
		elif poly.size() >= 3:
			# Los agujeros no se esperan aquí (polígonos convexos); se dibujan igual.
			var rev := PackedVector2Array(poly)
			rev.reverse()
			draw_colored_polygon(rev, color)


## Recorta el segmento a-b al círculo de radio r centrado en el origen.
## Devuelve [p0, p1] o un array vacío si queda fuera.
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
