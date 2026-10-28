class_name HUD
extends Control
## HUD de juego: radar, dinero, salud, objetivo, subtítulos, avisos y utilidades de cinemática.

signal pause_requested
signal map_requested

const LETTERBOX_FRACTION := 0.12
const CLUSTER_W := 330.0
const CLUSTER_H := 200.0
const BAR_W := 210.0
const BAR_H := 16.0
const MONEY_GREEN := Color("#2F8A3A")
const HEALTH_FG := Color("#B4191E")
const HEALTH_BG := Color("#3C0A0C")
const OUTLINE_PX := 6

## Radar (abajo a la izquierda). Se actualiza desde el jugador.
var radar: Radar

var _safe: Control
var _gameplay: Control
var _cluster: Control
var _money_text: String = "$00000000"
var _clock_text: String = "12:00"
var _wanted: int = 0
var _wanted_blink: float = 0.0
var _armor: float = 0.0
var _weapon_kind: String = "fist"
var _health_value: float = -1.0
var _loc_font: SystemFont
var _objective_panel: PanelContainer
var _objective_label: Label
var _objective_text: String = ""
var _hint_panel: PanelContainer
var _hint_label: Label
var _location_label: Label
var _speed_label: Label
var _subtitle_panel: PanelContainer
var _subtitle_label: RichTextLabel
var _toast_panel: PanelContainer
var _toast_title: Label
var _toast_sub: Label
var _fps_label: Label
var _letter_top: ColorRect
var _letter_bottom: ColorRect
var _letter_amount: float = 0.0
var _fade: ColorRect
var _title_card: Control
var _card_title: Label
var _card_sub: Label

var _obj_tween: Tween
var _loc_tween: Tween
var _sub_tween: Tween
var _toast_tween: Tween
var _letter_tween: Tween
var _fade_tween: Tween
var _card_tween: Tween
var _fps_accum: float = 0.0


func _ready() -> void:
	theme = UITheme.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(_on_resized)
	_on_resized()
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.settings_changed.connect(_on_settings_changed)
	_on_money_changed(GameState.money)
	_on_settings_changed()
	set_objective("")
	set_hint("")
	set_speed_kmh(-1.0)


func _process(delta: float) -> void:
	if _wanted_blink > 0.0:
		_wanted_blink = maxf(0.0, _wanted_blink - delta)
	_health_value = GameState.health
	if _gameplay.visible:
		_cluster.queue_redraw()
	if _fps_label.visible:
		_fps_accum += delta
		if _fps_accum >= 0.5:
			_fps_accum = 0.0
			_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


# --------------------------------------------------------------- Construcción

func _build() -> void:
	_safe = Control.new()
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe)

	_gameplay = Control.new()
	_gameplay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameplay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe.add_child(_gameplay)

	# Radar (abajo a la izquierda, elevado para no tapar el borde)
	radar = Radar.new()
	radar.custom_minimum_size = Vector2(200, 200)
	_gameplay.add_child(radar)
	radar.anchor_left = 0.0
	radar.anchor_right = 0.0
	radar.anchor_top = 1.0
	radar.anchor_bottom = 1.0
	radar.offset_left = 0.0
	radar.offset_right = 200.0
	radar.offset_top = -224.0
	radar.offset_bottom = -24.0

	# Esquina superior izquierda: botones + caja de ayuda
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 10)
	_gameplay.add_child(left)
	left.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)

	var btn_row := HBoxContainer.new()
	btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_row.add_theme_constant_override("separation", 10)
	left.add_child(btn_row)
	var pause_btn := UITheme.make_button("II", 72)
	pause_btn.add_theme_font_override("font", UITheme.bold_font())
	pause_btn.pressed.connect(func() -> void: pause_requested.emit())
	btn_row.add_child(pause_btn)
	var map_btn := UITheme.make_button("MAPA", 110)
	map_btn.add_theme_font_size_override("font_size", 22)
	map_btn.pressed.connect(func() -> void: map_requested.emit())
	btn_row.add_child(map_btn)

	_hint_panel = PanelContainer.new()
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hint_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.04, 0.06, 0.7), Color(0, 0, 0, 0.9), 2, 8, Vector4(12, 8, 12, 8)))
	_hint_label = UITheme.label("", 20, Color(1, 1, 1, 0.95))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(420, 0)
	_hint_panel.add_child(_hint_label)
	left.add_child(_hint_panel)

	# Cluster superior derecha: arma, reloj, barras, dinero y estrellas (todo dibujado)
	_cluster = Control.new()
	_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cluster.custom_minimum_size = Vector2(CLUSTER_W, CLUSTER_H)
	_gameplay.add_child(_cluster)
	_cluster.anchor_left = 1.0
	_cluster.anchor_right = 1.0
	_cluster.anchor_top = 0.0
	_cluster.anchor_bottom = 0.0
	_cluster.offset_left = -CLUSTER_W
	_cluster.offset_right = 0.0
	_cluster.offset_top = 0.0
	_cluster.offset_bottom = CLUSTER_H
	_cluster.draw.connect(_draw_cluster)

	# Centro superior: objetivo + pista
	var top_center := VBoxContainer.new()
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_theme_constant_override("separation", 8)
	_gameplay.add_child(top_center)
	top_center.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	top_center.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_objective_panel = PanelContainer.new()
	_objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_objective_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var obj_box := VBoxContainer.new()
	obj_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_box.add_theme_constant_override("separation", 0)
	_objective_panel.add_child(obj_box)
	var obj_title := UITheme.label("OBJETIVO", 16, UITheme.GOLD, true)
	obj_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	obj_title.add_theme_constant_override("outline_size", 5)
	obj_box.add_child(obj_title)
	_objective_label = UITheme.label("", 24, Color.WHITE, true)
	_objective_label.add_theme_constant_override("outline_size", OUTLINE_PX)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.custom_minimum_size = Vector2(440, 0)
	obj_box.add_child(_objective_label)
	top_center.add_child(_objective_panel)

	# Lugar (abajo a la derecha, sobre la zona de botones táctiles)
	_loc_font = SystemFont.new()
	_loc_font.font_names = PackedStringArray(UITheme.FONT_NAMES)
	_loc_font.font_weight = 700
	_loc_font.font_italic = true
	_loc_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_location_label = UITheme.label("", 34, Color("#F3D77A"), true)
	_location_label.add_theme_font_override("font", _loc_font)
	_location_label.add_theme_constant_override("outline_size", OUTLINE_PX)
	_location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_location_label.modulate.a = 0.0
	_gameplay.add_child(_location_label)
	_location_label.anchor_left = 1.0
	_location_label.anchor_right = 1.0
	_location_label.anchor_top = 1.0
	_location_label.anchor_bottom = 1.0
	_location_label.offset_left = -620.0
	_location_label.offset_right = 0.0
	_location_label.offset_top = -270.0
	_location_label.offset_bottom = -225.0

	# Velocidad
	_speed_label = UITheme.label("", 48, Color.WHITE, true)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gameplay.add_child(_speed_label)
	_speed_label.anchor_left = 0.68
	_speed_label.anchor_right = 0.68
	_speed_label.anchor_top = 1.0
	_speed_label.anchor_bottom = 1.0
	_speed_label.offset_left = -220.0
	_speed_label.offset_right = 0.0
	_speed_label.offset_top = -170.0
	_speed_label.offset_bottom = -105.0

	# Subtítulos
	_subtitle_panel = PanelContainer.new()
	_subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.02, 0.02, 0.03, 0.78), Color(0, 0, 0, 0), 0, 10, Vector4(22, 12, 22, 12)))
	_subtitle_label = RichTextLabel.new()
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_label.bbcode_enabled = true
	_subtitle_label.fit_content = true
	_subtitle_label.scroll_active = false
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.custom_minimum_size = Vector2(720, 0)
	_subtitle_label.add_theme_font_size_override("normal_font_size", 26)
	_subtitle_label.add_theme_font_size_override("bold_font_size", 26)
	_subtitle_label.add_theme_font_override("bold_font", UITheme.bold_font())
	_subtitle_label.add_theme_color_override("default_color", Color.WHITE)
	_subtitle_panel.add_child(_subtitle_label)
	_subtitle_panel.visible = false
	_safe.add_child(_subtitle_panel)
	_subtitle_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_subtitle_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitle_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# FPS
	_fps_label = UITheme.label("", 20, Color(0.7, 1, 0.7))
	_fps_label.visible = false
	_safe.add_child(_fps_label)
	_fps_label.anchor_top = 1.0
	_fps_label.anchor_bottom = 1.0
	_fps_label.offset_top = -256.0
	_fps_label.offset_bottom = -230.0

	# Aviso grande
	_toast_panel = PanelContainer.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.02, 0.02, 0.03, 0.7), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.8), 2, 12, Vector4(70, 18, 70, 18)))
	var tbox := VBoxContainer.new()
	tbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tbox.add_theme_constant_override("separation", 2)
	_toast_panel.add_child(tbox)
	_toast_title = UITheme.label("", 64, UITheme.GOLD, true)
	_toast_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tbox.add_child(_toast_title)
	_toast_sub = UITheme.label("", 34, Color.WHITE)
	_toast_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tbox.add_child(_toast_sub)
	_toast_panel.visible = false
	add_child(_toast_panel)

	# Barras de cine
	_letter_top = ColorRect.new()
	_letter_top.color = Color.BLACK
	_letter_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letter_top)
	_letter_bottom = ColorRect.new()
	_letter_bottom.color = Color.BLACK
	_letter_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letter_bottom)

	# Fundido a negro
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.visible = false
	add_child(_fade)

	# Tarjeta de título (por encima del fundido para poder verse sobre negro)
	_title_card = Control.new()
	_title_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_card.modulate.a = 0.0
	_title_card.visible = false
	add_child(_title_card)
	var card_box := VBoxContainer.new()
	card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	card_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_card.add_child(card_box)
	_card_title = UITheme.label("", 110, Color.WHITE, true)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_title.add_theme_constant_override("outline_size", 12)
	card_box.add_child(_card_title)
	_card_sub = UITheme.label("", 36, UITheme.GOLD)
	_card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(_card_sub)


func _on_resized() -> void:
	if _safe == null:
		return
	var r := UITheme.safe_rect(self, 24.0)
	_safe.position = r.position
	_safe.size = r.size
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_toast_panel.position.y = size.y * 0.30
	_apply_letterbox(_letter_amount)


# ------------------------------------------------------------------- Señales

func _on_money_changed(value: int) -> void:
	_money_text = "$%08d" % clampi(value, 0, 99999999)
	if _cluster:
		_cluster.queue_redraw()


func _on_settings_changed() -> void:
	_fps_label.visible = Settings.show_fps
	if not Settings.subtitles:
		_hide_subtitle()


# ---------------------------------------------------------------- API pública

func set_objective(text: String) -> void:
	var changed := text != _objective_text
	_objective_text = text
	_objective_label.text = text
	_objective_panel.visible = text != ""
	if text == "" or not changed:
		return
	_objective_panel.reset_size()
	if _obj_tween:
		_obj_tween.kill()
	_objective_panel.modulate = Color(2.0, 1.7, 0.8, 1.0)
	_obj_tween = create_tween()
	_obj_tween.tween_property(_objective_panel, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func set_hint(text: String) -> void:
	_hint_label.text = text
	_hint_panel.visible = text != ""
	if text != "":
		var tw := UITheme.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 8.0
		_hint_label.custom_minimum_size = Vector2(clampf(tw, 120.0, 420.0), 0)
		_hint_label.reset_size()
		_hint_panel.reset_size()


## Nombre del lugar: aparece, se mantiene unos segundos y se desvanece.
func show_location(place: String) -> void:
	if _loc_tween:
		_loc_tween.kill()
	_location_label.text = place.to_upper()
	_location_label.modulate.a = 0.0
	_loc_tween = create_tween()
	_loc_tween.tween_property(_location_label, "modulate:a", 1.0, 0.45)
	_loc_tween.tween_interval(3.2)
	_loc_tween.tween_property(_location_label, "modulate:a", 0.0, 0.9)


## Negativo oculta el indicador.
func set_speed_kmh(v: float) -> void:
	if v < 0.0:
		_speed_label.visible = false
		return
	_speed_label.visible = true
	_speed_label.text = "%d km/h" % int(round(v))


func show_subtitle(speaker: String, text: String, duration: float = 4.0) -> void:
	if not Settings.subtitles or text == "":
		_hide_subtitle()
		return
	var body := text.replace("[", "[lb]")
	if speaker != "":
		var who := speaker.to_upper().replace("[", "[lb]")
		_subtitle_label.text = "[color=#D4A72C][b]%s[/b][/color]  %s" % [who, body]
	else:
		_subtitle_label.text = body
	_subtitle_panel.visible = true
	_subtitle_panel.reset_size()
	if _sub_tween:
		_sub_tween.kill()
	_subtitle_panel.modulate.a = 0.0
	_sub_tween = create_tween()
	_sub_tween.tween_property(_subtitle_panel, "modulate:a", 1.0, 0.15)
	_sub_tween.tween_interval(maxf(0.1, duration))
	_sub_tween.tween_property(_subtitle_panel, "modulate:a", 0.0, 0.25)
	_sub_tween.tween_callback(_hide_subtitle)


func _hide_subtitle() -> void:
	if _sub_tween:
		_sub_tween.kill()
	_subtitle_panel.visible = false


## Banner grande centrado, p. ej. toast("MISIÓN SUPERADA", "+$200", 3.0).
func toast(title: String, subtitle: String = "", duration: float = 3.0) -> void:
	_toast_title.text = title
	_toast_sub.text = subtitle
	_toast_sub.visible = subtitle != ""
	_toast_panel.visible = true
	_toast_panel.reset_size()
	_toast_panel.position.y = size.y * 0.30
	_toast_panel.pivot_offset = _toast_panel.size * 0.5
	if _toast_tween:
		_toast_tween.kill()
	_toast_panel.modulate.a = 0.0
	_toast_panel.scale = Vector2(0.85, 0.85)
	_toast_tween = create_tween()
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.25)
	_toast_tween.tween_property(_toast_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.set_parallel(false)
	_toast_tween.tween_interval(maxf(0.2, duration))
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func() -> void: _toast_panel.visible = false)


## Barras negras de cine arriba y abajo (12 % de la altura).
func set_letterbox(on: bool) -> void:
	if _letter_tween:
		_letter_tween.kill()
	_letter_tween = create_tween()
	_letter_tween.tween_method(_set_letter_amount, _letter_amount, 1.0 if on else 0.0, 0.6).set_trans(Tween.TRANS_SINE)


func _set_letter_amount(v: float) -> void:
	_letter_amount = v
	_apply_letterbox(v)


func _apply_letterbox(v: float) -> void:
	if _letter_top == null:
		return
	var h := size.y * LETTERBOX_FRACTION * v
	_letter_top.position = Vector2.ZERO
	_letter_top.size = Vector2(size.x, h)
	_letter_bottom.position = Vector2(0.0, size.y - h)
	_letter_bottom.size = Vector2(size.x, h)
	_letter_top.visible = v > 0.001
	_letter_bottom.visible = v > 0.001


## Fundido a negro: alpha 0 = transparente, 1 = negro total.
func fade_to(alpha: float, duration: float = 0.5) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade.visible = true
	if duration <= 0.0:
		_fade.color.a = alpha
		_fade.visible = alpha > 0.001
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", alpha, duration)
	if alpha <= 0.001:
		_fade_tween.tween_callback(func() -> void: _fade.visible = false)


## Título enorme que aparece y se desvanece.
func title_card(title: String, subtitle: String = "", duration: float = 3.0) -> void:
	_card_title.text = title
	_card_sub.text = subtitle
	_card_sub.visible = subtitle != ""
	_title_card.visible = true
	if _card_tween:
		_card_tween.kill()
	_title_card.modulate.a = 0.0
	_card_tween = create_tween()
	_card_tween.tween_property(_title_card, "modulate:a", 1.0, 0.8)
	_card_tween.tween_interval(maxf(0.1, duration))
	_card_tween.tween_property(_title_card, "modulate:a", 0.0, 0.8)
	_card_tween.tween_callback(func() -> void: _title_card.visible = false)


func set_clock(hours: int, minutes: int) -> void:
	_clock_text = "%02d:%02d" % [posmod(hours, 24), clampi(minutes, 0, 59)]
	if _cluster:
		_cluster.queue_redraw()


## Nivel de búsqueda 0..6. Al cambiar, las estrellas activas parpadean ~2,5 s.
func set_wanted(level: int) -> void:
	var l := clampi(level, 0, 6)
	if l != _wanted:
		_wanted = l
		_wanted_blink = 2.5 if l > 0 else 0.0
		if _cluster:
			_cluster.queue_redraw()


## Armadura 0..100; la barra se oculta con 0.
func set_armor(value: float) -> void:
	_armor = clampf(value, 0.0, 100.0)
	if _cluster:
		_cluster.queue_redraw()


func set_weapon_icon(kind: String) -> void:
	_weapon_kind = kind
	if _cluster:
		_cluster.queue_redraw()


# ------------------------------------------------------------ Dibujo del cluster

func _text_outlined(font: Font, pos: Vector2, text: String, width: float, fs: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_RIGHT) -> void:
	_cluster.draw_string_outline(font, pos, text, align, width, fs, OUTLINE_PX, Color.BLACK)
	_cluster.draw_string(font, pos, text, align, width, fs, col)


func _draw_cluster() -> void:
	var bold := UITheme.bold_font()
	var right := CLUSTER_W
	# Barras (derecha de la fila) y arma (izquierda)
	var bx := right - BAR_W - 4.0
	var wx := bx - 14.0 - 92.0
	_draw_weapon_box(Rect2(wx, 4.0, 92.0, 92.0))
	_text_outlined(bold, Vector2(bx, 46.0), _clock_text, BAR_W, 46, Color.WHITE)
	var hp_max := maxf(1.0, float(GameState.MAX_HEALTH))
	var hp := clampf(_health_value / hp_max, 0.0, 1.0) if _health_value >= 0.0 else 1.0
	var ay := 56.0
	if _armor > 0.0:
		_draw_bar(Rect2(bx, ay, BAR_W, BAR_H), _armor / 100.0, Color(0.9, 0.9, 0.92), Color(0.25, 0.25, 0.27))
	_draw_bar(Rect2(bx, ay + BAR_H + 6.0, BAR_W, BAR_H), hp, HEALTH_FG, HEALTH_BG)
	# Dinero
	_text_outlined(bold, Vector2(right - 4.0, 140.0), _money_text, right - 4.0, 42, MONEY_GREEN)
	# Estrellas de búsqueda
	var blink_on := true
	if _wanted_blink > 0.0:
		blink_on = fmod(_wanted_blink, 0.6) > 0.25
	var sr := 15.0
	var step := 36.0
	for i in range(6):
		var cx := right - 4.0 - sr - float(5 - i) * step
		var active := i < _wanted
		var col := Color(0.24, 0.24, 0.26) if not active else (Color.WHITE if blink_on else Color(1, 1, 1, 0.25))
		_draw_star(Vector2(cx, 172.0), sr, col)


func _draw_bar(r: Rect2, frac: float, fg: Color, bg: Color) -> void:
	_cluster.draw_rect(r, bg, true)
	if frac > 0.0:
		_cluster.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), fg, true)
	_cluster.draw_rect(r, Color.BLACK, false, 2.0)


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var rad := r if i % 2 == 0 else r * 0.42
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	_cluster.draw_colored_polygon(pts, col)
	var ol := PackedVector2Array(pts)
	ol.append(pts[0])
	_cluster.draw_polyline(ol, Color.BLACK, 2.5, true)


func _draw_weapon_box(r: Rect2) -> void:
	var c := r.get_center()
	_cluster.draw_circle(c, r.size.x * 0.5, Color(1, 1, 1, 0.18))
	_cluster.draw_arc(c, r.size.x * 0.5 - 1.0, 0.0, TAU, 40, Color(0, 0, 0, 0.85), 3.0, true)
	if _weapon_kind == "fist":
		_draw_fist(c)


## Puño original: palma, cuatro nudillos y pulgar, con contorno negro.
func _draw_fist(c: Vector2) -> void:
	var skin := Color(0.96, 0.96, 0.96)
	var polys: Array[PackedVector2Array] = []
	# Palma
	polys.append(PackedVector2Array([c + Vector2(-20, -2), c + Vector2(22, -2), c + Vector2(22, 26), c + Vector2(-14, 28), c + Vector2(-22, 14)]))
	# Cuatro dedos doblados (nudillos)
	for i in range(4):
		var x := -20.0 + float(i) * 11.0
		polys.append(PackedVector2Array([c + Vector2(x, -22), c + Vector2(x + 10, -22), c + Vector2(x + 10.5, 0), c + Vector2(x, 0)]))
	# Pulgar cruzado
	polys.append(PackedVector2Array([c + Vector2(-22, 6), c + Vector2(10, 4), c + Vector2(12, 14), c + Vector2(-18, 18)]))
	for p in polys:
		var ol := PackedVector2Array(p)
		ol.append(p[0])
		_cluster.draw_polyline(ol, Color.BLACK, 4.0, true)
	for p in polys:
		_cluster.draw_colored_polygon(p, skin)
		var ol2 := PackedVector2Array(p)
		ol2.append(p[0])
		_cluster.draw_polyline(ol2, Color(0.1, 0.1, 0.1), 1.5, true)


## Oculta radar, dinero, botones, objetivo, etc. (no subtítulos, barras ni fundido).
func set_gameplay_visible(on: bool) -> void:
	_gameplay.visible = on
