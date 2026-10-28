class_name TitleMenu
extends Control
## Menú principal sobre una escena 3D: degradado oscuro a la izquierda y botones.

signal continue_requested
signal new_game_requested
signal load_requested(slot: int)

const VERSION_TEXT := "v0.1 prototipo"

var _safe: Control
var _title_box: VBoxContainer
var _main_box: VBoxContainer
var _load_box: VBoxContainer
var _settings: SettingsPanel
var _continue_btn: Button
var _slot_buttons: Dictionary = {}
var _studio: Label
var _version: Label


func _ready() -> void:
	theme = UITheme.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(_layout)
	_layout()
	refresh()
	_show_main()


func _build() -> void:
	# Degradado lateral para legibilidad
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.02, 0.04, 0.92), Color(0.02, 0.02, 0.04, 0.72), Color(0.02, 0.02, 0.04, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 256
	gt.height = 4
	var shade := TextureRect.new()
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_left = 0.0
	shade.anchor_top = 0.0
	shade.anchor_right = 0.72
	shade.anchor_bottom = 1.0
	add_child(shade)

	_safe = Control.new()
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe)

	# Título
	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", 0)
	_safe.add_child(_title_box)
	var title := Label.new()
	title.text = "WESTSIDE LEGACY"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spaced := FontVariation.new()
	spaced.base_font = UITheme.bold_font()
	spaced.spacing_glyph = 3
	var ls := LabelSettings.new()
	ls.font = spaced
	ls.font_size = 96
	ls.font_color = Color.WHITE
	ls.outline_size = 10
	ls.outline_color = Color(0, 0, 0, 0.95)
	ls.shadow_size = 6
	ls.shadow_color = Color(0, 0, 0, 0.6)
	ls.shadow_offset = Vector2(4, 5)
	title.label_settings = ls
	_title_box.add_child(title)

	var tag := Label.new()
	tag.text = "Respect Is Earned. Legacy Is Taken."
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tls := LabelSettings.new()
	tls.font = UITheme.italic_font()
	tls.font_size = 32
	tls.font_color = UITheme.GOLD
	tls.outline_size = 5
	tls.outline_color = Color(0, 0, 0, 0.9)
	tag.label_settings = tls
	_title_box.add_child(tag)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_box.add_child(gap)

	# Menú principal
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 12)
	_main_box.custom_minimum_size = Vector2(440, 0)
	_main_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_title_box.add_child(_main_box)
	_continue_btn = _menu_button("Continuar", func() -> void: continue_requested.emit())
	_main_box.add_child(_continue_btn)
	_main_box.add_child(_menu_button("Nueva partida", func() -> void: new_game_requested.emit()))
	_main_box.add_child(_menu_button("Cargar partida", _show_load))
	_main_box.add_child(_menu_button("Ajustes", _show_settings))

	# Lista de partidas
	_load_box = VBoxContainer.new()
	_load_box.add_theme_constant_override("separation", 10)
	_load_box.custom_minimum_size = Vector2(700, 0)
	_load_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_title_box.add_child(_load_box)
	var slots: Array = [SaveSystem.AUTOSAVE_SLOT]
	slots.append_array(SaveSystem.MANUAL_SLOTS)
	for slot in slots:
		var s: int = slot
		var b := UITheme.make_button("")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: load_requested.emit(s))
		_load_box.add_child(b)
		_slot_buttons[s] = b
	_load_box.add_child(_menu_button("Volver", _show_main))

	# Ajustes (a la altura de la pantalla, sustituye al título)
	_settings = SettingsPanel.new()
	_settings.back_pressed.connect(_show_main)
	_safe.add_child(_settings)

	# Pie
	_studio = UITheme.label("VANTA STUDIO", 20, UITheme.TEXT_DIM, true)
	_safe.add_child(_studio)
	_version = UITheme.label(VERSION_TEXT, 20, UITheme.TEXT_DIM)
	_safe.add_child(_version)


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
	var pad := 48.0
	_title_box.position = Vector2(pad, 0)
	_title_box.size = Vector2(minf(980.0, r.size.x - pad), 0)
	var h := _title_box.get_combined_minimum_size().y
	_title_box.size.y = h
	_title_box.position.y = maxf(0.0, (r.size.y - h) * 0.4)
	_settings.position = Vector2(pad, 0)
	_settings.size = Vector2(minf(760.0, r.size.x - pad * 2.0), r.size.y)
	_studio.reset_size()
	_studio.position = Vector2(pad, r.size.y - _studio.size.y)
	_version.reset_size()
	_version.position = Vector2(r.size.x - _version.size.x, r.size.y - _version.size.y)


## Vuelve a comprobar las partidas guardadas.
func refresh() -> void:
	if _continue_btn == null:
		return
	_continue_btn.disabled = not SaveSystem.has_slot(SaveSystem.AUTOSAVE_SLOT)
	for s in _slot_buttons:
		var slot: int = int(s)
		var b: Button = _slot_buttons[s]
		b.text = UITheme.slot_text(slot, "Autoguardado" if slot == SaveSystem.AUTOSAVE_SLOT else "")
		b.disabled = not SaveSystem.has_slot(slot)


func _hide_all() -> void:
	_main_box.visible = false
	_load_box.visible = false
	_settings.visible = false
	_title_box.visible = true


func _show_main() -> void:
	_hide_all()
	_main_box.visible = true
	refresh()
	_layout()


func _show_load() -> void:
	_hide_all()
	_load_box.visible = true
	refresh()
	_layout()


func _show_settings() -> void:
	_hide_all()
	_title_box.visible = false
	_settings.visible = true
	_layout()
