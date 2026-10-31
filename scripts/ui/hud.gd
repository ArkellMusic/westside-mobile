class_name HUD
extends Control
## HUD de juego: radar, dinero, salud, objetivo, subtítulos, avisos y utilidades de cinemática.

signal pause_requested
signal map_requested

const LETTERBOX_FRACTION := 0.12
## El bloque superior derecho se dibuja en coordenadas de la referencia (360 x 300)
## y se escala con CLUSTER_SCALE.
const REF_W := 360.0
const REF_H := 300.0
const CLUSTER_SCALE := 0.86
const CLUSTER_W := REF_W * CLUSTER_SCALE
const CLUSTER_H := REF_H * CLUSTER_SCALE
const MONEY_GREEN := Color("#2F6B2F")
const STAR_BROWN := Color("#8A5A14")
const STAR_GLOW := Color("#E8A92A")
const HEALTH_FG := Color("#C0202A")
const HEALTH_BG := Color("#3C0A0C")
const ARMOR_FG := Color("#E2E2E2")
const RADAR_W := 350.0
const RADAR_H := 230.0
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
	_update_letterbox(delta)
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
	radar.custom_minimum_size = Vector2(RADAR_W, RADAR_H)
	_gameplay.add_child(radar)
	radar.anchor_left = 0.0
	radar.anchor_right = 0.0
	radar.anchor_top = 1.0
	radar.anchor_bottom = 1.0
	radar.offset_left = 0.0
	radar.offset_right = RADAR_W
	radar.offset_top = -RADAR_H - 4.0
	radar.offset_bottom = -4.0

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
	_fps_label.offset_top = -RADAR_H - 34.0
	_fps_label.offset_bottom = -RADAR_H - 8.0

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
	# Velocímetro desactivado a petición (estilo GTA SA, sin indicador de velocidad).
	if true or v < 0.0:
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
var _letter_target: float = 0.0


func set_letterbox(on: bool) -> void:
	_letter_target = 1.0 if on else 0.0


func _update_letterbox(delta: float) -> void:
	if is_equal_approx(_letter_amount, _letter_target):
		return
	_set_letter_amount(move_toward(_letter_amount, _letter_target, delta * 2.2))


func _set_letter_amount(v: float) -> void:
	_letter_amount = v
	_apply_letterbox(v)


func _apply_letterbox(v: float) -> void:
	if _letter_top == null:
		return
	var h := size.y * LETTERBOX_FRACTION * v
	CameraRig.letterbox_cover = LETTERBOX_FRACTION * v
	_letter_top.position = Vector2.ZERO
	_letter_top.size = Vector2(size.x, h)
	_letter_bottom.position = Vector2(0.0, size.y - h)
	_letter_bottom.size = Vector2(size.x, h)
	_letter_top.visible = v > 0.001
	# Subtítulos por encima de la franja inferior (si no, quedan tapados).
	if _subtitle_panel:
		var safe_bottom := get_global_rect().end.y - _safe.get_global_rect().end.y
		_subtitle_panel.offset_bottom = -maxf(h - safe_bottom + 14.0, 24.0)
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
## Todo se dibuja en coordenadas de referencia (REF_W x REF_H) con una transformación de escala.

const GLYPH_SEGS := {
	"0": "abcdef", "1": "", "2": "abged", "3": "abgcd", "4": "fgbc",
	"5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg",
}
static var _sb_round: StyleBoxFlat


## Glifos bloque (estilo rotulación gruesa) dibujados con rectángulos redondeados.
## Devuelve el ancho total. Con draw=false solo mide.
func _glyph_text(text: String, right: float, top: float, h: float, wratio: float, fill: Color, ol: float, gap: float, draw: bool = true) -> float:
	var gw := h * wratio
	var t := h * 0.26
	var total := 0.0
	for ch in text:
		total += (gw * 0.34 if ch == ":" else gw) + gap
	total -= gap
	if not draw:
		return total
	var x := right - total
	var rects: Array[Rect2] = []
	for ch in text:
		if ch == ":":
			var cw := gw * 0.34
			var sq := t * 0.95
			rects.append(Rect2(x + (cw - sq) * 0.5, top + h * 0.28, sq, sq))
			rects.append(Rect2(x + (cw - sq) * 0.5, top + h * 0.62, sq, sq))
			x += cw + gap
			continue
		var segs := ""
		if ch == "$":
			segs = "afgcd"
		else:
			segs = String(GLYPH_SEGS.get(ch, ""))
		var half := h * 0.5 + t * 0.5
		var map := {
			"a": Rect2(x, top, gw, t),
			"d": Rect2(x, top + h - t, gw, t),
			"g": Rect2(x, top + (h - t) * 0.5, gw, t),
			"f": Rect2(x, top, t, half),
			"b": Rect2(x + gw - t, top, t, half),
			"e": Rect2(x, top + h * 0.5 - t * 0.5, t, half),
			"c": Rect2(x + gw - t, top + h * 0.5 - t * 0.5, t, half),
		}
		for sc in segs:
			rects.append(map[String(sc)])
		if ch == "1":
			rects.append(Rect2(x + gw * 0.5 - t * 0.5, top, t, h))
			rects.append(Rect2(x + gw * 0.14, top + t * 0.2, gw * 0.4, t * 0.8))
			rects.append(Rect2(x + gw * 0.14, top + h - t * 0.8, gw * 0.72, t * 0.8))
		if ch == "$":
			rects.append(Rect2(x + gw * 0.5 - t * 0.4, top - h * 0.1, t * 0.8, h * 1.2))
		x += gw + gap
	if _sb_round == null:
		_sb_round = StyleBoxFlat.new()
		_sb_round.anti_aliasing = true
	_sb_round.bg_color = Color.BLACK
	_sb_round.set_corner_radius_all(int(ol + 2.0))
	for r in rects:
		_cluster.draw_style_box(_sb_round, r.grow(ol))
	_sb_round.bg_color = fill
	_sb_round.set_corner_radius_all(2)
	for r in rects:
		_cluster.draw_style_box(_sb_round, r)
	return total


func _draw_cluster() -> void:
	var S := CLUSTER_SCALE
	_cluster.draw_set_transform(Vector2.ZERO, 0.0, Vector2(S, S))
	var right := REF_W - 8.0
	# Arma (caja redondeada con borde negro grueso)
	_draw_weapon_box(Rect2(10.0, 8.0, 124.0, 128.0))
	# Reloj
	_glyph_text(_clock_text, right, 6.0, 42.0, 0.84, Color(0.96, 0.96, 0.96), 3.5, 7.0)
	# Armadura (barra fina blanca/gris)
	_draw_bar(Rect2(158.0, 66.0, right - 158.0, 17.0), _armor / 100.0 if _armor > 0.0 else 0.0, ARMOR_FG, Color(0.45, 0.45, 0.47, 0.0 if _armor <= 0.0 else 0.9), _armor > 0.0)
	# Vida
	var hp_max := maxf(1.0, float(GameState.MAX_HEALTH))
	var hp := clampf(_health_value / hp_max, 0.0, 1.0) if _health_value >= 0.0 else 1.0
	_draw_bar(Rect2(10.0, 142.0, right - 10.0, 18.0), hp, HEALTH_FG, HEALTH_BG, true)
	# Dinero (8 dígitos con ceros)
	_glyph_text(_money_text, right, 178.0, 38.0, 0.62, MONEY_GREEN, 3.5, 5.0)
	# Estrellas de búsqueda
	var blink_on := true
	if _wanted_blink > 0.0:
		blink_on = fmod(_wanted_blink, 0.6) > 0.25
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	for i in range(6):
		var cx := 36.0 + float(i) * 58.0
		var active := i < _wanted
		var col := Color(STAR_BROWN.r, STAR_BROWN.g, STAR_BROWN.b, 0.16)
		var olc := Color(0, 0, 0, 0.22)
		if active:
			col = STAR_BROWN.lerp(STAR_GLOW, pulse * 0.75)
			olc = Color.BLACK
			if not blink_on:
				col = Color(col.r, col.g, col.b, 0.2)
				olc = Color(0, 0, 0, 0.3)
		_draw_star(Vector2(cx, 262.0), 28.0, col, olc)
	_cluster.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_bar(r: Rect2, frac: float, fg: Color, bg: Color, show_track: bool = true) -> void:
	if not show_track:
		return
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = true
	sb.bg_color = Color.BLACK
	sb.set_corner_radius_all(2)
	_cluster.draw_style_box(sb, r.grow(3.0))
	_cluster.draw_rect(r, bg, true)
	if frac > 0.0:
		_cluster.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), fg, true)


func _draw_star(c: Vector2, r: float, col: Color, outline: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var rad := r if i % 2 == 0 else r * 0.46
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	var ol := PackedVector2Array(pts)
	ol.append(pts[0])
	_cluster.draw_polyline(ol, outline, 6.0, true)
	_cluster.draw_colored_polygon(pts, col)


func _draw_weapon_box(r: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = true
	sb.bg_color = Color(0.9, 0.9, 0.9)
	sb.set_corner_radius_all(26)
	sb.set_border_width_all(7)
	sb.border_color = Color.BLACK
	_cluster.draw_style_box(sb, r)
	var inner := r.grow(-9.0)
	var sb2 := StyleBoxFlat.new()
	sb2.anti_aliasing = true
	sb2.bg_color = Color(0, 0, 0, 0)
	sb2.set_corner_radius_all(18)
	sb2.set_border_width_all(2)
	sb2.border_color = Color(1, 1, 1, 0.95)
	_cluster.draw_style_box(sb2, inner)
	if _weapon_kind == "fist":
		_draw_fist(r.get_center(), 2.15)


## Puño original (dibujado por código): palma redondeada, cuatro nudillos y pulgar cruzado.
func _draw_fist(c: Vector2, k: float) -> void:
	var skin := Color(0.97, 0.97, 0.97)
	var shade := Color(0.78, 0.78, 0.8)
	var line := Color(0.12, 0.12, 0.14)
	var palm := Rect2(c + Vector2(-23, -4) * k, Vector2(46, 34) * k)
	var thumb := Rect2(c + Vector2(-25, 9) * k, Vector2(38, 14) * k)
	var knuckles: Array[Vector2] = []
	for i in range(4):
		knuckles.append(c + Vector2(-17.5 + float(i) * 11.7, -9.0) * k)
	var kr := 7.2 * k
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = true
	# Contorno negro
	sb.bg_color = Color.BLACK
	sb.set_corner_radius_all(int(9 * k))
	_cluster.draw_style_box(sb, palm.grow(2.5))
	for kp in knuckles:
		_cluster.draw_circle(kp, kr + 2.5, Color.BLACK)
	sb.set_corner_radius_all(int(7 * k))
	_cluster.draw_style_box(sb, thumb.grow(2.5))
	# Relleno
	sb.bg_color = skin
	sb.set_corner_radius_all(int(9 * k))
	_cluster.draw_style_box(sb, palm)
	for kp in knuckles:
		_cluster.draw_circle(kp, kr, skin)
	# Sombra de la parte baja de la palma y separaciones de los dedos
	sb.bg_color = shade
	sb.set_corner_radius_all(int(8 * k))
	_cluster.draw_style_box(sb, Rect2(palm.position + Vector2(2, 20) * k, Vector2(palm.size.x - 4.0 * k, 10 * k)))
	for i in range(1, 4):
		var kx := c.x + (-17.5 + (float(i) - 0.5) * 11.7) * k
		_cluster.draw_line(Vector2(kx, c.y - 8.0 * k), Vector2(kx, c.y + 6.0 * k), line, 2.0)
	sb.bg_color = skin
	sb.set_corner_radius_all(int(7 * k))
	_cluster.draw_style_box(sb, thumb)
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_color = line
	_cluster.draw_style_box(sb, thumb)


## Oculta radar, dinero, botones, objetivo, etc. (no subtítulos, barras ni fundido).
func set_gameplay_visible(on: bool) -> void:
	_gameplay.visible = on
