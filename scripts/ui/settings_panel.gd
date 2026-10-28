class_name SettingsPanel
extends PanelContainer
## Panel de ajustes. Cada cambio escribe en Settings, aplica y guarda.

signal back_pressed

var _loading: bool = false
var _save_pending: bool = false
var _quality_buttons: Dictionary = {}
var _fps_buttons: Dictionary = {}
var _scale_slider: HSlider
var _opacity_slider: HSlider
var _sens_slider: HSlider
var _scale_value: Label
var _opacity_value: Label
var _sens_value: Label
var _invert_check: CheckButton
var _subs_check: CheckButton
var _fps_check: CheckButton


func _ready() -> void:
	theme = UITheme.make_theme()
	custom_minimum_size = Vector2(620, 0)
	_build()
	refresh()
	visibility_changed.connect(_on_visibility_changed)


func _build() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	add_child(outer)

	outer.add_child(UITheme.label("AJUSTES", 34, UITheme.GOLD, true))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)

	# Calidad gráfica
	var q_row := HBoxContainer.new()
	q_row.add_theme_constant_override("separation", 8)
	var q_group := ButtonGroup.new()
	for q in ["low", "medium", "high"]:
		var b := UITheme.make_button(String(Settings.QUALITY_NAMES[q]), 110)
		b.toggle_mode = true
		b.button_group = q_group
		b.pressed.connect(_on_quality.bind(q))
		q_row.add_child(b)
		_quality_buttons[q] = b
	list.add_child(_row("Calidad gráfica", q_row))

	# Límite FPS
	var f_row := HBoxContainer.new()
	f_row.add_theme_constant_override("separation", 8)
	var f_group := ButtonGroup.new()
	for fps in [30, 60]:
		var fb := UITheme.make_button("%d" % fps, 110)
		fb.toggle_mode = true
		fb.button_group = f_group
		fb.pressed.connect(_on_fps.bind(fps))
		f_row.add_child(fb)
		_fps_buttons[fps] = fb
	list.add_child(_row("Límite FPS", f_row))

	# Deslizadores
	_scale_slider = _make_slider(0.7, 1.4, 0.05)
	_scale_value = UITheme.label("", 22, UITheme.TEXT_DIM)
	_scale_slider.value_changed.connect(_on_scale)
	list.add_child(_row("Tamaño de controles", _slider_box(_scale_slider, _scale_value)))

	_opacity_slider = _make_slider(0.3, 1.0, 0.05)
	_opacity_value = UITheme.label("", 22, UITheme.TEXT_DIM)
	_opacity_slider.value_changed.connect(_on_opacity)
	list.add_child(_row("Opacidad de controles", _slider_box(_opacity_slider, _opacity_value)))

	_sens_slider = _make_slider(0.3, 2.5, 0.05)
	_sens_value = UITheme.label("", 22, UITheme.TEXT_DIM)
	_sens_slider.value_changed.connect(_on_sensitivity)
	list.add_child(_row("Sensibilidad de cámara", _slider_box(_sens_slider, _sens_value)))

	# Interruptores
	_invert_check = _make_check("Invertir eje Y")
	_invert_check.toggled.connect(_on_invert)
	list.add_child(_invert_check)
	_subs_check = _make_check("Subtítulos")
	_subs_check.toggled.connect(_on_subtitles)
	list.add_child(_subs_check)
	_fps_check = _make_check("Mostrar FPS")
	_fps_check.toggled.connect(_on_show_fps)
	list.add_child(_fps_check)

	var back := UITheme.make_button("Volver")
	back.pressed.connect(_on_back)
	outer.add_child(back)


func _row(title: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := UITheme.label(title, 24)
	l.custom_minimum_size = Vector2(250, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


func _make_slider(min_v: float, max_v: float, step_v: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.custom_minimum_size = Vector2(200, 56)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.drag_ended.connect(_on_drag_ended)
	return s


func _slider_box(slider: HSlider, value_label: Label) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.add_child(slider)
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(value_label)
	return h


func _make_check(text: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.custom_minimum_size = Vector2(0, UITheme.BUTTON_MIN_HEIGHT)
	c.focus_mode = Control.FOCUS_NONE
	return c


## Vuelve a leer los valores actuales de Settings.
func refresh() -> void:
	_loading = true
	for q in _quality_buttons:
		(_quality_buttons[q] as Button).set_pressed_no_signal(q == Settings.quality)
	for fps in _fps_buttons:
		(_fps_buttons[fps] as Button).set_pressed_no_signal(fps == Settings.fps_cap)
	_scale_slider.set_value_no_signal(Settings.controls_scale)
	_opacity_slider.set_value_no_signal(Settings.controls_opacity)
	_sens_slider.set_value_no_signal(Settings.camera_sensitivity)
	_scale_value.text = "%.2f" % Settings.controls_scale
	_opacity_value.text = "%d%%" % int(round(Settings.controls_opacity * 100.0))
	_sens_value.text = "%.2f" % Settings.camera_sensitivity
	_invert_check.set_pressed_no_signal(Settings.invert_y)
	_subs_check.set_pressed_no_signal(Settings.subtitles)
	_fps_check.set_pressed_no_signal(Settings.show_fps)
	_loading = false


func _commit() -> void:
	Settings.apply()
	Settings.save_settings()
	_save_pending = false


func _on_quality(q: String) -> void:
	if _loading:
		return
	Settings.set_quality(q)


func _on_fps(fps: int) -> void:
	if _loading:
		return
	Settings.fps_cap = fps
	_commit()


func _on_scale(v: float) -> void:
	_scale_value.text = "%.2f" % v
	if _loading:
		return
	Settings.controls_scale = v
	Settings.apply()
	_save_pending = true


func _on_opacity(v: float) -> void:
	_opacity_value.text = "%d%%" % int(round(v * 100.0))
	if _loading:
		return
	Settings.controls_opacity = v
	Settings.apply()
	_save_pending = true


func _on_sensitivity(v: float) -> void:
	_sens_value.text = "%.2f" % v
	if _loading:
		return
	Settings.camera_sensitivity = v
	Settings.apply()
	_save_pending = true


func _on_drag_ended(_value_changed: bool) -> void:
	if _save_pending:
		Settings.save_settings()
		_save_pending = false


func _on_invert(on: bool) -> void:
	if _loading:
		return
	Settings.invert_y = on
	_commit()


func _on_subtitles(on: bool) -> void:
	if _loading:
		return
	Settings.subtitles = on
	_commit()


func _on_show_fps(on: bool) -> void:
	if _loading:
		return
	Settings.show_fps = on
	_commit()


func _on_back() -> void:
	if _save_pending:
		Settings.save_settings()
		_save_pending = false
	back_pressed.emit()


func _on_visibility_changed() -> void:
	if visible:
		refresh()
	elif _save_pending:
		Settings.save_settings()
		_save_pending = false
