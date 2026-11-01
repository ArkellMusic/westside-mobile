class_name MapScreen
extends Control
## Mapa a pantalla completa: pestaña WESTBROOK (plano vectorial con zoom y arrastre)
## y pestaña ESTADO: relieve generado desde StateLayout (mismas coordenadas que el
## mundo 3D) con autopistas, ciudades, zonas bloqueadas (niebla + candado), jugador,
## waypoint y rutas GPS. Tocar el mapa ESTADO también pone el waypoint azul.

signal closed

const MIN_ZOOM := 0.45
const MAX_ZOOM := 7.0
const TAP_SLOP := 14.0

const OCEAN := Color(0.10, 0.27, 0.46)
const SAND := Color(0.72, 0.65, 0.46)
const LAND := Color(0.11, 0.12, 0.13)
const ROAD := Color(0.66, 0.67, 0.70)
const ROAD_EDGE := Color(0.05, 0.05, 0.06)
const FOOTPRINT := Color(0.07, 0.07, 0.09)
const PIER := Color(0.45, 0.32, 0.2)
const BLOCK_COLORS := {
	"residential": Color(0.20, 0.31, 0.20),
	"commercial": Color(0.31, 0.31, 0.35),
	"beach": Color(0.80, 0.74, 0.56),
}
const LANDMARK_NAMES := {
	"terminal": "Terminal",
	"veyra_mart": "Veyra Mart",
	"mack_house": "Casa de Mack",
	"vargas_garage": "Vargas Auto Works",
}

var player_pos: Vector3 = Vector3.ZERO:
	set(v):
		player_pos = v
		queue_redraw()
var player_heading: float = 0.0:
	set(v):
		player_heading = v
		queue_redraw()
## Vector3.INF si no hay misión activa.
var mission_marker: Vector3 = Vector3.INF:
	set(v):
		mission_marker = v
		queue_redraw()
var gps: GPS = null
var footprints: Array = []:
	set(v):
		footprints = v
		queue_redraw()

var _tab: int = 0
var _center: Vector2 = Vector2.ZERO
var _zoom: float = 1.8
var _roads: Array = []
var _blocks: Array = []
var _touches: Dictionary = {}
## Para distinguir toque de arrastre: {index: {pos, moved, t}} y si hubo multitáctil.
var _taps: Dictionary = {}
var _multi: bool = false
var _mouse_tap: Dictionary = {}
var _state_tex: Texture2D = null
var _bar: PanelContainer
var _tab_buttons: Array[Button] = []
var _recenter: Button
var _hint: Label
var _pulse: float = 0.0


func _ready() -> void:
	theme = UITheme.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_roads = CityLayout.road_segments()
	_blocks = CityLayout.blocks()
	_build_ui()
	resized.connect(_on_resized)
	visibility_changed.connect(_on_visibility_changed)
	_on_resized()
	open_tab(0)
	_center = Vector2(player_pos.x, player_pos.z)


func _build_ui() -> void:
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.03, 0.05, 0.96), Color(0, 0, 0, 0), 0, 0, Vector4(24, 8, 24, 8)))
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_bar.add_child(row)
	var title := UITheme.label("MAPA", 30, UITheme.GOLD, true)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16, 0)
	row.add_child(gap)
	var group := ButtonGroup.new()
	var names := ["WESTBROOK", "ESTADO"]
	for i in range(names.size()):
		var b := UITheme.make_button(names[i], 190)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = (i == 0)
		b.pressed.connect(open_tab.bind(i))
		row.add_child(b)
		_tab_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var close_btn := UITheme.make_button("Cerrar", 160)
	close_btn.pressed.connect(func() -> void: closed.emit())
	row.add_child(close_btn)

	_recenter = UITheme.make_button("Centrar", 160)
	_recenter.pressed.connect(center_on_player)
	add_child(_recenter)

	_hint = UITheme.label("Arrastra para mover · pellizca para ampliar · toca para marcar destino", 18, UITheme.TEXT_DIM)
	add_child(_hint)


## Muestra el mapa centrado en el jugador, en la pestaña WESTBROOK.
func open() -> void:
	visible = true
	open_tab(0)
	center_on_player()
	_touches.clear()
	_taps.clear()
	_multi = false


func close() -> void:
	visible = false
	_touches.clear()
	_taps.clear()
	_multi = false


func open_tab(index: int) -> void:
	_tab = clampi(index, 0, 1)
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	if _recenter != null:
		_recenter.visible = _tab == 0
		_hint.visible = _tab == 0
	queue_redraw()


func center_on_player() -> void:
	_center = Vector2(player_pos.x, player_pos.z)
	queue_redraw()


func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())
	_touches.clear()


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 3.0, TAU)
	queue_redraw()


func _on_resized() -> void:
	if _bar == null:
		return
	var safe := UITheme.safe_rect(self, 12.0)
	var st: StyleBoxFlat = _bar.get_theme_stylebox("panel") as StyleBoxFlat
	if st != null:
		st = st.duplicate()
		st.content_margin_left = safe.position.x + 12.0
		st.content_margin_right = size.x - safe.end.x + 12.0
		st.content_margin_top = safe.position.y * 0.5 + 6.0
		_bar.add_theme_stylebox_override("panel", st)
	_bar.position = Vector2.ZERO
	_bar.size = Vector2(size.x, 0.0)
	_recenter.reset_size()
	_recenter.position = Vector2(safe.end.x - _recenter.size.x, safe.end.y - _recenter.size.y)
	_hint.reset_size()
	_hint.position = Vector2(safe.position.x + 8.0, safe.end.y - _hint.size.y - 8.0)
	queue_redraw()


func _map_rect() -> Rect2:
	var top := _bar.size.y if _bar != null else 80.0
	return Rect2(0.0, top, size.x, maxf(10.0, size.y - top))


func _w2s(p: Vector2) -> Vector2:
	return _map_rect().get_center() + (p - _center) * _zoom


func _s2w(p: Vector2) -> Vector2:
	return _center + (p - _map_rect().get_center()) / _zoom


# ------------------------------------------------------------------- Entrada

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _tab == 1:
		_input_state(event)
		return
	var rect := _map_rect()
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var pos := make_canvas_position_local(t.position)
		if t.pressed:
			if rect.has_point(pos) and not _recenter.get_global_rect().has_point(t.position):
				_touches[t.index] = pos
				_taps[t.index] = {"pos": pos, "moved": 0.0, "t": Time.get_ticks_msec()}
				if _touches.size() >= 2:
					_multi = true
				get_viewport().set_input_as_handled()
		elif _touches.has(t.index):
			_touches.erase(t.index)
			var tap: Dictionary = _taps.get(t.index, {})
			_taps.erase(t.index)
			if _touches.is_empty():
				var was_multi := _multi
				_multi = false
				if not was_multi and not tap.is_empty() and float(tap["moved"]) < TAP_SLOP and Time.get_ticks_msec() - int(tap["t"]) < 600:
					tap_at(pos)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if not _touches.has(d.index):
			return
		var pos2 := make_canvas_position_local(d.position)
		if _taps.has(d.index):
			_taps[d.index]["moved"] = float(_taps[d.index]["moved"]) + d.relative.length()
		if _touches.size() >= 2:
			var keys: Array = _touches.keys()
			var other_key: int = int(keys[0]) if int(keys[0]) != d.index else int(keys[1])
			var other: Vector2 = _touches[other_key]
			var old_pos: Vector2 = _touches[d.index]
			var old_dist := old_pos.distance_to(other)
			var new_dist := pos2.distance_to(other)
			var old_mid := (old_pos + other) * 0.5
			var new_mid := (pos2 + other) * 0.5
			_touches[d.index] = pos2
			if old_dist > 4.0:
				_zoom_at(new_mid, new_dist / old_dist)
			_center -= (new_mid - old_mid) / _zoom
		else:
			_touches[d.index] = pos2
			_center -= d.relative / _zoom
		_clamp_center()
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var mpos := make_canvas_position_local(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT and not bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)):
			if mb.pressed and rect.has_point(mpos) and not _recenter.get_global_rect().has_point(mb.position):
				_mouse_tap = {"pos": mpos, "moved": 0.0}
			elif not mb.pressed and not _mouse_tap.is_empty():
				if float(_mouse_tap["moved"]) < TAP_SLOP and rect.has_point(mpos):
					tap_at(mpos)
				_mouse_tap = {}
		if mb.pressed and rect.has_point(mpos):
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(mpos, 1.15)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mpos, 1.0 / 1.15)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		var gpos := make_canvas_position_local(mg.position)
		if rect.has_point(gpos):
			_zoom_at(gpos, mg.factor)
	elif event is InputEventMouseMotion:
		# Con emulate_touch_from_mouse el arrastre ya llega como pantalla táctil.
		if bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)):
			return
		var mm := event as InputEventMouseMotion
		if not _mouse_tap.is_empty():
			_mouse_tap["moved"] = float(_mouse_tap["moved"]) + mm.relative.length()
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and rect.has_point(make_canvas_position_local(mm.position)):
			_center -= mm.relative / _zoom
			_clamp_center()
			queue_redraw()


## Pestaña ESTADO: un toque (sin arrastre) pone o quita el waypoint.
func _input_state(event: InputEvent) -> void:
	var pos := Vector2.INF
	var pressed := false
	if event is InputEventScreenTouch:
		pos = make_canvas_position_local((event as InputEventScreenTouch).position)
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)):
			return
		pos = make_canvas_position_local((event as InputEventMouseButton).position)
		pressed = (event as InputEventMouseButton).pressed
	else:
		return
	if not _state_rect().has_point(pos):
		return
	if pressed:
		_mouse_tap = {"pos": pos, "t": Time.get_ticks_msec()}
	elif not _mouse_tap.is_empty():
		if pos.distance_to(_mouse_tap["pos"]) < TAP_SLOP and Time.get_ticks_msec() - int(_mouse_tap["t"]) < 600:
			tap_at(pos)
		_mouse_tap = {}
	get_viewport().set_input_as_handled()


## Toque (sin arrastre) sobre el mapa: pone el waypoint, o lo quita si se toca sobre él.
func tap_at(screen_pos: Vector2) -> void:
	if gps == null:
		return
	if _tab == 1:
		var r := _state_rect()
		var w2 := StateLayout.uv_to_world((screen_pos - r.position) / r.size)
		gps.toggle_waypoint(Vector3(w2.x, 0.0, w2.y), 20.0 * StateLayout.RECT.size.x / r.size.x)
		queue_redraw()
		return
	var w := _s2w(screen_pos)
	var radius_m := 26.0 / _zoom
	gps.toggle_waypoint(Vector3(w.x, 0.0, w.y), maxf(radius_m, 8.0))
	queue_redraw()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := _s2w(screen_pos)
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var after := _s2w(screen_pos)
	_center += before - after
	_clamp_center()
	queue_redraw()


func _clamp_center() -> void:
	_center.x = clampf(_center.x, CityLayout.PLAY_MIN.x - 60.0, CityLayout.PLAY_MAX.x + 60.0)
	_center.y = clampf(_center.y, CityLayout.PLAY_MIN.y - 60.0, CityLayout.PLAY_MAX.y + 60.0)


# -------------------------------------------------------------------- Dibujo

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 1.0))
	if _tab == 0:
		_draw_westbrook()
	else:
		_draw_state()


func _world_rect(r: Rect2, color: Color) -> void:
	var a := _w2s(r.position)
	var b := _w2s(r.end)
	draw_rect(Rect2(a, b - a), color)


func _draw_westbrook() -> void:
	var rect := _map_rect()
	draw_rect(rect, LAND)
	# Océano, arena, río
	_world_rect(Rect2(-4000.0, -4000.0, 4000.0 + CityLayout.SHORE_X, 8000.0), OCEAN)
	_world_rect(Rect2(CityLayout.SHORE_X, -4000.0, CityLayout.BEACH_EAST - CityLayout.SHORE_X, 8000.0), SAND)
	_world_rect(Rect2(CityLayout.RIVER_X0, -4000.0, CityLayout.RIVER_X1 - CityLayout.RIVER_X0, 8000.0), OCEAN)
	# Manzanas
	for blk in _blocks:
		var bd: Dictionary = blk
		var kind := String(bd.get("kind", "residential"))
		_world_rect(bd["rect"], BLOCK_COLORS.get(kind, BLOCK_COLORS["residential"]))
	# Calles
	for seg in _roads:
		var s: Dictionary = seg
		var a := _w2s(s["a"])
		var b := _w2s(s["b"])
		var w := maxf(2.0, float(s["width"]) * _zoom)
		draw_line(a, b, ROAD_EDGE, w + 3.0)
		draw_line(a, b, ROAD, w)
	# Autopista este (hasta el borde de lo visible)
	var hw_a := _w2s(Vector2(CityLayout.EAST_EDGE, CityLayout.HIGHWAY_Z))
	var hw_b := _w2s(Vector2(CityLayout.HIGHWAY_END_X, CityLayout.HIGHWAY_Z))
	draw_line(hw_a, hw_b, ROAD_EDGE, 16.0 * _zoom + 3.0)
	draw_line(hw_a, hw_b, ROAD, 16.0 * _zoom)
	# Muelle
	var pier := Rect2(CityLayout.PIER_TO_X, CityLayout.PIER_Z - CityLayout.PIER_WIDTH * 0.5, CityLayout.PIER_FROM_X - CityLayout.PIER_TO_X, CityLayout.PIER_WIDTH)
	_world_rect(pier, PIER)
	# Edificios
	for fp in footprints:
		var fr: Rect2 = fp
		var p0 := _w2s(fr.position)
		var p1 := _w2s(fr.end)
		if p1.x < rect.position.x or p0.x > rect.end.x or p1.y < rect.position.y or p0.y > rect.end.y:
			continue
		draw_rect(Rect2(p0, p1 - p0), FOOTPRINT)

	# Rutas GPS (azul debajo, misión amarilla encima)
	if gps != null:
		var me := Vector2(player_pos.x, player_pos.z)
		_draw_route(gps.display_route(gps.waypoint_route, me), GPS.WAYPOINT_COLOR)
		_draw_route(gps.display_route(gps.mission_route, me), GPS.MISSION_COLOR)

	var font := UITheme.bold_font()
	# Etiquetas de zonas de playa/río/muelle
	_map_text(font, "OCÉANO", _w2s(Vector2(-385.0, -120.0)), 22, Color(1, 1, 1, 0.5))
	_map_text(font, "Muelle", _w2s(Vector2(-346.0, CityLayout.PIER_Z - 10.0)), 16, Color(1, 1, 1, 0.8))
	_map_text(font, "RÍO", _w2s(Vector2((CityLayout.RIVER_X0 + CityLayout.RIVER_X1) * 0.5, -120.0)), 22, Color(1, 1, 1, 0.5))

	# Puntos de interés
	for id in LANDMARK_NAMES:
		var lp: Vector3 = CityLayout.landmark(String(id))
		var sp := _w2s(Vector2(lp.x, lp.z))
		draw_circle(sp, 9.0, Color(0, 0, 0, 0.85))
		draw_circle(sp, 6.0, UITheme.GOLD)
		_map_text(font, String(LANDMARK_NAMES[id]), sp + Vector2(0, -16.0), 22, Color.WHITE)

	# Misión
	if mission_marker != Vector3.INF:
		var mp := _w2s(Vector2(mission_marker.x, mission_marker.z))
		var inner := rect.grow(-34.0)
		var clamped := mp
		clamped.x = clampf(mp.x, inner.position.x, inner.end.x)
		clamped.y = clampf(mp.y, inner.position.y, inner.end.y)
		var pr := 13.0 + sin(_pulse) * 3.0
		draw_circle(clamped, pr + 4.0, Color(0, 0, 0, 0.8))
		draw_circle(clamped, pr, Color(0.95, 0.25, 0.2))
		_map_text(font, "!", clamped + Vector2(0, 6.0), 22, Color.WHITE)
		if clamped != mp:
			_map_text(font, "Misión", clamped + Vector2(0, -22.0), 18, Color(1, 0.8, 0.75))

	# Waypoint manual
	if gps != null and gps.has_waypoint():
		var wp := _w2s(Vector2(gps.waypoint.x, gps.waypoint.z))
		draw_circle(wp + Vector2(0, -22.0), 14.0, Color(0, 0, 0, 0.85))
		draw_circle(wp + Vector2(0, -22.0), 10.0, GPS.WAYPOINT_COLOR)
		draw_colored_polygon(PackedVector2Array([wp + Vector2(-9, -16), wp + Vector2(9, -16), wp]), Color(0, 0, 0, 0.85))
		draw_colored_polygon(PackedVector2Array([wp + Vector2(-6.5, -15), wp + Vector2(6.5, -15), wp + Vector2(0, -3)]), GPS.WAYPOINT_COLOR)
		draw_circle(wp + Vector2(0, -22.0), 3.5, Color.WHITE)

	# Jugador (norte arriba: yaw 0 apunta a -Z, giro positivo hacia el oeste)
	var pp := _w2s(Vector2(player_pos.x, player_pos.z))
	var ang := -player_heading
	var tri := PackedVector2Array([Vector2(0, -17), Vector2(12, 13), Vector2(0, 6), Vector2(-12, 13)])
	for i in range(tri.size()):
		tri[i] = pp + tri[i].rotated(ang)
	draw_circle(pp, 20.0, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.25))
	draw_colored_polygon(tri, Color.WHITE)
	var outline := PackedVector2Array(tri)
	outline.append(tri[0])
	draw_polyline(outline, Color(0, 0, 0, 0.9), 2.5, true)

	# Brújula
	var nc := Vector2(rect.end.x - 54.0, rect.position.y + 54.0)
	draw_circle(nc, 26.0, Color(0.05, 0.05, 0.07, 0.85))
	draw_arc(nc, 26.0, 0.0, TAU, 32, UITheme.GOLD, 3.0, true)
	_map_text(font, "N", nc + Vector2(0, 8.0), 24, Color(1, 0.4, 0.35))


func _draw_route(route: PackedVector2Array, color: Color) -> void:
	if route.size() < 2:
		return
	var pts := PackedVector2Array()
	for p in route:
		pts.append(_w2s(p))
	draw_polyline(pts, Color(0, 0, 0, 0.75), 9.0, true)
	draw_polyline(pts, color, 5.5, true)
	for q in pts:
		draw_circle(q, 2.75, color)


func _map_text(font: Font, text: String, center_pos: Vector2, fs: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := center_pos + Vector2(-w * 0.5, 0.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Rectángulo de pantalla que ocupa el mapa del estado (mismo aspecto que StateLayout.RECT).
func _state_rect() -> Rect2:
	var rect := _map_rect().grow(-16.0)
	var ms := StateLayout.RECT.size
	var k := minf(rect.size.x / ms.x, rect.size.y / ms.y)
	var sz := ms * k
	return Rect2(rect.get_center() - sz * 0.5, sz)


func _st(p: Vector2) -> Vector2:
	var r := _state_rect()
	return r.position + StateLayout.world_to_uv(p) * r.size


func _draw_state() -> void:
	if _state_tex == null:
		_state_tex = ImageTexture.create_from_image(StateLayout.make_map_image(4))
	var img_rect := _state_rect()
	draw_texture_rect(_state_tex, img_rect, false)
	# Autopistas y carreteras
	for pass_i in 2:
		for rd in StateLayout.roads():
			var pts := PackedVector2Array()
			for p in (rd["pts"] as PackedVector2Array):
				pts.append(_st(p))
			var main_road: bool = rd["main"]
			if pass_i == 0:
				draw_polyline(pts, Color(0.1, 0.1, 0.1, 0.8), 6.0 if main_road else 4.5, true)
			else:
				draw_polyline(pts, Color(0.98, 0.84, 0.35) if main_road else Color(0.93, 0.93, 0.9), 3.2 if main_road else 2.2, true)
	# Westbrook: calles
	for seg in _roads:
		draw_line(_st(seg["a"]), _st(seg["b"]), Color(0.93, 0.93, 0.9, 0.8), 1.2)
	# Zonas bloqueadas: niebla + candado
	var font := UITheme.bold_font()
	for id in StateLayout.ZONE_ORDER:
		var zid := String(id)
		if GameState.is_zone_unlocked(zid):
			continue
		var poly := PackedVector2Array()
		for p in StateLayout.zone_polygon(zid):
			poly.append(_st(p))
		var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(poly, PackedVector2Array([img_rect.position, Vector2(img_rect.end.x, img_rect.position.y), img_rect.end, Vector2(img_rect.position.x, img_rect.end.y)]))
		for cp in clipped:
			if cp.size() >= 3 and not Geometry2D.is_polygon_clockwise(cp):
				draw_colored_polygon(cp, Color(0.03, 0.03, 0.06, 0.45))
		var closed := PackedVector2Array(poly)
		closed.append(poly[0])
		draw_polyline(closed, Color(1, 1, 1, 0.25), 1.5, true)
	for id in StateLayout.ZONE_ORDER:
		var zid := String(id)
		var p := _st(StateLayout.zone_center(zid))
		var z: Dictionary = GameData.zone(zid)
		var name := String(z.get("name", zid))
		if GameState.is_zone_unlocked(zid):
			_map_text(font, name.to_upper(), p + Vector2(0, -12.0), 20, Color.WHITE)
		else:
			var m := int(z.get("unlock_after_mission", 0))
			_draw_lock(p + Vector2(0, -30.0))
			_map_text(font, name.to_upper(), p + Vector2(0, 10.0), 18, Color(1, 1, 1, 0.9))
			_draw_pill(font, "Misión %d" % m if m > 0 else "Bloqueada", p + Vector2(0, 34.0), 15, Color(0.04, 0.04, 0.06, 0.9), Color(1, 1, 1))
	draw_rect(img_rect, UITheme.GOLD_DARK, false, 2.0)
	# Rutas GPS (azul debajo, misión amarilla encima)
	if gps != null:
		var me := Vector2(player_pos.x, player_pos.z)
		for pair in [[gps.waypoint_route, GPS.WAYPOINT_COLOR], [gps.mission_route, GPS.MISSION_COLOR]]:
			var route: PackedVector2Array = gps.display_route(pair[0], me)
			if route.size() >= 2:
				var pts := PackedVector2Array()
				for q in route:
					pts.append(_st(q))
				draw_polyline(pts, Color(0, 0, 0, 0.75), 7.0, true)
				draw_polyline(pts, pair[1], 4.0, true)
		if gps.has_waypoint():
			var wp := _st(Vector2(gps.waypoint.x, gps.waypoint.z))
			draw_circle(wp + Vector2(0, -16.0), 11.0, Color(0, 0, 0, 0.85))
			draw_circle(wp + Vector2(0, -16.0), 8.0, GPS.WAYPOINT_COLOR)
			draw_colored_polygon(PackedVector2Array([wp + Vector2(-6, -11), wp + Vector2(6, -11), wp]), GPS.WAYPOINT_COLOR)
	if mission_marker != Vector3.INF:
		var mp := _st(Vector2(mission_marker.x, mission_marker.z))
		draw_circle(mp, 10.0, Color(0, 0, 0, 0.8))
		draw_circle(mp, 7.0, Color(0.95, 0.25, 0.2))
	# Jugador
	var pp := _st(Vector2(player_pos.x, player_pos.z))
	var tri := PackedVector2Array([Vector2(0, -13), Vector2(9, 10), Vector2(0, 5), Vector2(-9, 10)])
	for i in range(tri.size()):
		tri[i] = pp + tri[i].rotated(-player_heading)
	draw_circle(pp, 16.0 + sin(_pulse) * 2.0, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.3))
	draw_colored_polygon(tri, Color.WHITE)
	var outline := PackedVector2Array(tri)
	outline.append(tri[0])
	draw_polyline(outline, Color(0, 0, 0, 0.9), 2.0, true)
	_map_text(font, "Toca el mapa para marcar destino", Vector2(img_rect.get_center().x, img_rect.end.y - 10.0), 16, Color(1, 1, 1, 0.75))


func _draw_pill(font: Font, text: String, center_pos: Vector2, fs: int, bg: Color, fg: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var h := font.get_height(fs)
	var box := Rect2(center_pos - Vector2(w * 0.5 + 10.0, h * 0.5 + 3.0), Vector2(w + 20.0, h + 6.0))
	var sb := UITheme.box(bg, UITheme.GOLD, 2, int(box.size.y * 0.5), Vector4(0, 0, 0, 0))
	draw_style_box(sb, box)
	draw_string(font, Vector2(box.position.x + 10.0, box.position.y + 3.0 + font.get_ascent(fs)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


## Candado: cuerpo dorado, arco y ojo de la cerradura.
func _draw_lock(c: Vector2) -> void:
	draw_circle(c + Vector2(0, 2), 25.0, Color(0, 0, 0, 0.55))
	draw_arc(c + Vector2(0, -3), 8.0, PI, TAU, 16, Color(0.85, 0.86, 0.9), 4.0, true)
	draw_line(c + Vector2(-8, -3), c + Vector2(-8, 1), Color(0.85, 0.86, 0.9), 4.0)
	draw_line(c + Vector2(8, -3), c + Vector2(8, 1), Color(0.85, 0.86, 0.9), 4.0)
	var body := UITheme.box(UITheme.GOLD, Color(0.1, 0.08, 0.02), 2, 4, Vector4(0, 0, 0, 0))
	draw_style_box(body, Rect2(c + Vector2(-13, 0), Vector2(26, 19)))
	draw_circle(c + Vector2(0, 8), 3.0, Color(0.1, 0.08, 0.02))
	draw_line(c + Vector2(0, 8), c + Vector2(0, 14), Color(0.1, 0.08, 0.02), 3.0)
