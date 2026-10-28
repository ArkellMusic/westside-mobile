class_name PauseMenu
extends Control
## Menú de pausa: Continuar, Mapa, Guardar partida, Ajustes, Menú principal.

signal resume_requested
signal map_requested
signal quit_to_title_requested

var _safe: Control
var _main_col: VBoxContainer
var _save_col: VBoxContainer
var _settings: SettingsPanel
var _slot_buttons: Dictionary = {}
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_layout)
	_layout()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_safe = Control.new()
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe)

	# Columna principal
	_main_col = VBoxContainer.new()
	_main_col.add_theme_constant_override("separation", 12)
	_main_col.custom_minimum_size = Vector2(440, 0)
	_safe.add_child(_main_col)
	_main_col.add_child(UITheme.label("PAUSA", 56, UITheme.GOLD, true))
	_main_col.add_child(_spacer(8))
	_main_col.add_child(_menu_button("Continuar", func() -> void: resume_requested.emit()))
	_main_col.add_child(_menu_button("Mapa", func() -> void: map_requested.emit()))
	_main_col.add_child(_menu_button("Guardar partida", _show_save))
	_main_col.add_child(_menu_button("Ajustes", _show_settings))
	_main_col.add_child(_menu_button("Menú principal", func() -> void: quit_to_title_requested.emit()))

	# Columna de guardado
	_save_col = VBoxContainer.new()
	_save_col.add_theme_constant_override("separation", 12)
	_save_col.custom_minimum_size = Vector2(700, 0)
	_safe.add_child(_save_col)
	_save_col.add_child(UITheme.label("GUARDAR PARTIDA", 44, UITheme.GOLD, true))
	_save_col.add_child(_spacer(4))
	for slot in SaveSystem.MANUAL_SLOTS:
		var s: int = slot
		var b := UITheme.make_button("")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_slot_pressed.bind(s))
		_save_col.add_child(b)
		_slot_buttons[s] = b
	_status = UITheme.label("", 28, UITheme.GOLD, true)
	_status.custom_minimum_size = Vector2(0, 40)
	_save_col.add_child(_status)
	_save_col.add_child(_menu_button("Volver", _show_main))

	# Ajustes
	_settings = SettingsPanel.new()
	_settings.back_pressed.connect(_show_main)
	_safe.add_child(_settings)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _menu_button(text: String, cb: Callable) -> Button:
	var b := UITheme.make_button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	return b


func _layout() -> void:
	if _safe == null:
		return
	var r := UITheme.safe_rect(self, 24.0)
	_safe.position = r.position
	_safe.size = r.size
	var pad := 32.0
	_main_col.position = Vector2(pad, 0)
	_main_col.size = Vector2(440, r.size.y)
	_save_col.position = Vector2(pad, 0)
	_save_col.size = Vector2(700, r.size.y)
	_settings.position = Vector2(pad, 0)
	_settings.size = Vector2(minf(760.0, r.size.x - pad * 2.0), r.size.y)
	# Centrado vertical de las columnas cortas
	for col in [_main_col, _save_col]:
		var c: Control = col
		var h := c.get_combined_minimum_size().y
		c.position.y = maxf(0.0, (r.size.y - h) * 0.5)
		c.size.y = h


func open() -> void:
	visible = true
	_show_main()


func close() -> void:
	visible = false


func _hide_all() -> void:
	_main_col.visible = false
	_save_col.visible = false
	_settings.visible = false


func _show_main() -> void:
	_hide_all()
	_main_col.visible = true
	_layout()


func _show_save() -> void:
	_hide_all()
	_status.text = ""
	_refresh_slots()
	_save_col.visible = true
	_layout()


func _show_settings() -> void:
	_hide_all()
	_settings.visible = true
	_layout()


func _refresh_slots() -> void:
	for s in _slot_buttons:
		(_slot_buttons[s] as Button).text = UITheme.slot_text(int(s))


func _on_slot_pressed(slot: int) -> void:
	if SaveSystem.save_slot(slot):
		_status.text = "Partida guardada"
	else:
		_status.text = "No se pudo guardar"
	_refresh_slots()
