class_name TouchControls
extends Control
## Controles táctiles: joystick flotante a la izquierda, botones circulares y
## arrastre de cámara a la derecha. Multitáctil manual en _input().

const JOY_ZONE := 0.45
const JOY_RADIUS := 90.0
const DEADZONE := 0.08

var _mode: String = "hidden"
var _interact_label: String = ""
var _buttons: Array[Dictionary] = []

var _joy_index: int = -1
var _joy_origin: Vector2 = Vector2.ZERO
var _joy_pos: Vector2 = Vector2.ZERO
var _look_index: int = -1

var _scale: float = 1.0
var _opacity: float = 0.75


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	EventBus.settings_changed.connect(_on_settings_changed)
	_read_settings()
	_layout()


func set_mode(mode: String) -> void:
	if not ["foot", "car", "hidden"].has(mode):
		push_warning("TouchControls: modo desconocido '%s'" % mode)
		return
	_mode = mode
	_release_all()
	_layout()


func get_mode() -> String:
	return _mode


func set_interact_label(text: String) -> void:
	if text == _interact_label:
		return
	_interact_label = text
	# Si el botón desaparece mientras está pulsado, se suelta.
	_layout()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_release_all()


func _on_settings_changed() -> void:
	_read_settings()
	_layout()


func _read_settings() -> void:
	_scale = clampf(Settings.controls_scale, 0.7, 1.4)
	_opacity = clampf(Settings.controls_opacity, 0.3, 1.0)


# ---------------------------------------------------------------- Disposición

func _layout() -> void:
	var held: Dictionary = {}
	for b in _buttons:
		if int(b["touch"]) != -1:
			held[String(b["action"])] = int(b["touch"])
	var old_actions: Array = []
	for b in _buttons:
		old_actions.append(String(b["action"]))
	_buttons.clear()
	if _mode != "hidden":
		var safe := UITheme.safe_rect(self)
		var s := _scale
		var r_main: float = 66.0 if _mode == "foot" else 72.0
		var pivot := Vector2(safe.end.x - (r_main + 10.0) * s, safe.end.y - (r_main + 10.0) * s)
		if _mode == "foot":
			_add_button("jump", "Saltar", pivot, 0.0, 0.0, 66.0, false)
			_add_button("sprint", "Correr", pivot, 140.0, 8.0, 54.0, true)
			if _interact_label != "":
				_add_button("interact", _interact_label, pivot, 142.0, 78.0, 54.0, false)
		else:
			_add_button("gas", "Gas", pivot, 0.0, 0.0, 72.0, true)
			_add_button("brake", "Freno", pivot, 152.0, 2.0, 58.0, true)
			_add_button("handbrake", "Freno mano", pivot, 168.0, 50.0, 46.0, true)
			_add_button("interact", "Salir", pivot, 158.0, 90.0, 46.0, false)
	# Suelta los botones que ya no existen o cambiaron de sitio sin dueño.
	for a in old_actions:
		var still := false
		for b in _buttons:
			if String(b["action"]) == a:
				still = true
		if not still:
			Controls.press(a, false)
	for b in _buttons:
		var a := String(b["action"])
		if held.has(a):
			b["touch"] = int(held[a])
	queue_redraw()


## `dist` y `angle_deg` son relativos al pivote: 0 grados = a la izquierda, 90 = arriba.
func _add_button(action: String, text: String, pivot: Vector2, dist: float, angle_deg: float, radius: float, hold: bool) -> void:
	var a := deg_to_rad(angle_deg)
	var off := Vector2(-cos(a), -sin(a)) * dist * _scale
	_buttons.append({
		"action": action,
		"label": text,
		"center": pivot + off,
		"radius": radius * _scale,
		"hold": hold,
		"touch": -1,
	})


# --------------------------------------------------------------------- Entrada

func _input(event: InputEvent) -> void:
	if _mode == "hidden" or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var pos := make_canvas_position_local(t.position)
		if t.pressed:
			_touch_down(t.index, pos)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		var pos2 := make_canvas_position_local(d.position)
		if d.index == _joy_index:
			_update_joystick(pos2)
		elif d.index == _look_index:
			Controls.add_look(d.relative)


func _touch_down(index: int, pos: Vector2) -> void:
	# ¿Cae sobre un botón? (radio algo mayor para dedos gordos)
	for b in _buttons:
		var center: Vector2 = b["center"]
		var radius: float = b["radius"]
		if pos.distance_to(center) <= radius * 1.15 and int(b["touch"]) == -1:
			b["touch"] = index
			Controls.press(String(b["action"]), true)
			queue_redraw()
			return
	if pos.x < size.x * JOY_ZONE:
		if _joy_index == -1:
			_joy_index = index
			_joy_origin = pos
			_joy_pos = pos
			Controls.touch_move = Vector2.ZERO
			queue_redraw()
	elif _look_index == -1:
		_look_index = index


func _touch_up(index: int) -> void:
	if index == _joy_index:
		_joy_index = -1
		Controls.touch_move = Vector2.ZERO
		queue_redraw()
	if index == _look_index:
		_look_index = -1
	for b in _buttons:
		if int(b["touch"]) == index:
			b["touch"] = -1
			Controls.press(String(b["action"]), false)
			queue_redraw()


func _update_joystick(pos: Vector2) -> void:
	var radius := JOY_RADIUS * _scale
	var v := pos - _joy_origin
	if v.length() > radius:
		v = v.normalized() * radius
	_joy_pos = _joy_origin + v
	var n := v / radius
	if n.length() < DEADZONE:
		n = Vector2.ZERO
	# Arrastrar hacia arriba (y de pantalla negativa) = avanzar (y positivo).
	Controls.touch_move = Vector2(n.x, -n.y).limit_length(1.0)
	queue_redraw()


func _release_all() -> void:
	_joy_index = -1
	_look_index = -1
	for b in _buttons:
		if int(b["touch"]) != -1:
			b["touch"] = -1
			Controls.press(String(b["action"]), false)
	Controls.release_all()
	queue_redraw()


func _exit_tree() -> void:
	if Controls != null:
		Controls.release_all()


# -------------------------------------------------------------------- Dibujo

func _draw() -> void:
	if _mode == "hidden":
		return
	var font := UITheme.bold_font()
	var gold := UITheme.GOLD

	# Joystick
	var radius := JOY_RADIUS * _scale
	if _joy_index != -1:
		var base := Color(0.05, 0.05, 0.07, 0.45 * _opacity)
		draw_circle(_joy_origin, radius, base)
		draw_arc(_joy_origin, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.55 * _opacity), 3.0, true)
		draw_circle(_joy_pos, radius * 0.45, Color(gold.r, gold.g, gold.b, 0.85 * _opacity))
		draw_arc(_joy_pos, radius * 0.45, 0.0, TAU, 32, Color(0, 0, 0, 0.6 * _opacity), 2.0, true)
	else:
		var safe := UITheme.safe_rect(self)
		var hint := Vector2(safe.position.x + radius + 30.0, safe.end.y - radius - 30.0)
		draw_arc(hint, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.16 * _opacity), 3.0, true)
		draw_circle(hint, radius * 0.4, Color(1, 1, 1, 0.07 * _opacity))

	# Botones
	for b in _buttons:
		var center: Vector2 = b["center"]
		var r: float = b["radius"]
		var pressed: bool = int(b["touch"]) != -1
		var fill := Color(0.05, 0.05, 0.07, 0.55 * _opacity)
		var ring := Color(gold.r, gold.g, gold.b, 0.95 * _opacity)
		if pressed:
			fill = Color(gold.r, gold.g, gold.b, 0.85 * _opacity)
		draw_circle(center, r, fill)
		draw_arc(center, r, 0.0, TAU, 40, ring, 4.0, true)
		var txt_col := Color(0.05, 0.04, 0.02, _opacity) if pressed else Color(1, 1, 1, minf(1.0, _opacity + 0.15))
		_draw_label(font, String(b["label"]), center, r, txt_col)


func _draw_label(font: Font, text: String, center: Vector2, r: float, color: Color) -> void:
	var lines: PackedStringArray = text.split(" ")
	if text.length() <= 6:
		lines = PackedStringArray([text])
	var fs := int(clampf(r * 0.38, 15.0, 30.0))
	# Reduce la fuente si la palabra más larga no cabe en el círculo.
	var widest := 0.0
	for l in lines:
		widest = maxf(widest, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	while widest > r * 1.65 and fs > 11:
		fs -= 1
		widest = 0.0
		for l in lines:
			widest = maxf(widest, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var line_h := font.get_height(fs)
	var total := line_h * lines.size()
	var y := center.y - total * 0.5 + font.get_ascent(fs)
	for l in lines:
		var w := font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(center.x - w * 0.5, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		y += line_h
