class_name HUD
extends Control
## HUD de juego: radar, dinero, salud, objetivo, subtítulos, avisos y utilidades de cinemática.

signal pause_requested
signal map_requested

const LETTERBOX_FRACTION := 0.12

## Radar (arriba a la izquierda). Se actualiza desde el jugador.
var radar: Radar

var _safe: Control
var _gameplay: Control
var _money_label: Label
var _health_bar: ProgressBar
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
	_health_bar.value = GameState.health
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

	# Radar
	radar = Radar.new()
	radar.position = Vector2.ZERO
	radar.size = Vector2(210, 210)
	_gameplay.add_child(radar)

	# Columna superior derecha: botones, dinero, salud
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 6)
	right.alignment = BoxContainer.ALIGNMENT_BEGIN
	_gameplay.add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var btn_row := HBoxContainer.new()
	btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(btn_row)
	var map_btn := UITheme.make_button("MAPA", 110)
	map_btn.add_theme_font_size_override("font_size", 22)
	map_btn.pressed.connect(func() -> void: map_requested.emit())
	btn_row.add_child(map_btn)
	var pause_btn := UITheme.make_button("II", 72)
	pause_btn.add_theme_font_override("font", UITheme.bold_font())
	pause_btn.pressed.connect(func() -> void: pause_requested.emit())
	btn_row.add_child(pause_btn)

	_money_label = UITheme.label("$0", 38, UITheme.GOLD, true)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_money_label)

	_health_bar = ProgressBar.new()
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.show_percentage = false
	_health_bar.min_value = 0.0
	_health_bar.max_value = GameState.MAX_HEALTH
	_health_bar.value = GameState.health
	_health_bar.custom_minimum_size = Vector2(250, 12)
	_health_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(_health_bar)

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
	var obj_box := VBoxContainer.new()
	obj_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_box.add_theme_constant_override("separation", 0)
	_objective_panel.add_child(obj_box)
	obj_box.add_child(UITheme.label("OBJETIVO", 16, UITheme.GOLD, true))
	_objective_label = UITheme.label("", 24, Color.WHITE, true)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.custom_minimum_size = Vector2(440, 0)
	obj_box.add_child(_objective_label)
	top_center.add_child(_objective_panel)

	_hint_panel = PanelContainer.new()
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.04, 0.06, 0.7), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.5), 1, 8, Vector4(14, 8, 14, 8)))
	_hint_label = UITheme.label("", 20, Color(1, 1, 1, 0.92))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(420, 0)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_panel.add_child(_hint_label)
	top_center.add_child(_hint_panel)

	# Lugar (abajo a la izquierda, sobre la zona del joystick)
	_location_label = UITheme.label("", 34, Color.WHITE, true)
	_location_label.modulate.a = 0.0
	_gameplay.add_child(_location_label)
	_location_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	_location_label.offset_top = -270.0
	_location_label.offset_bottom = -225.0
	_location_label.offset_right = 520.0

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
	_fps_label.position = Vector2(0, 218)

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
	_money_label.text = UITheme.format_money(value)


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


## Oculta radar, dinero, botones, objetivo, etc. (no subtítulos, barras ni fundido).
func set_gameplay_visible(on: bool) -> void:
	_gameplay.visible = on
