class_name UITheme
extends RefCounted
## Tema visual común: paneles oscuros translúcidos, acento dorado, fuente del sistema.
## Todo el UI se construye por código; cada pantalla raíz hace `theme = UITheme.make_theme()`.

const GOLD := Color("#D4A72C")
const GOLD_DARK := Color("#9C7A18")
const PANEL_BG := Color(0.04, 0.04, 0.06, 0.82)
const TEXT := Color(1, 1, 1, 1)
const TEXT_DIM := Color(0.75, 0.76, 0.8, 1)
const BUTTON_MIN_HEIGHT := 64.0
const FONT_NAMES := ["Avenir Next", "Helvetica Neue", "Arial", "DejaVu Sans", "sans-serif"]

static var _font: SystemFont
static var _bold: SystemFont
static var _italic: SystemFont
static var _theme: Theme
static var _grabber: ImageTexture


static func font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(FONT_NAMES)
		_font.font_weight = 400
		_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _font


static func bold_font() -> Font:
	if _bold == null:
		_bold = SystemFont.new()
		_bold.font_names = PackedStringArray(FONT_NAMES)
		_bold.font_weight = 700
		_bold.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _bold


static func italic_font() -> Font:
	if _italic == null:
		_italic = SystemFont.new()
		_italic.font_names = PackedStringArray(FONT_NAMES)
		_italic.font_weight = 400
		_italic.font_italic = true
		_italic.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _italic


## Caja plana con esquinas redondeadas.
static func box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = 10, margin: Vector4 = Vector4(24, 18, 24, 18)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.content_margin_left = margin.x
	sb.content_margin_top = margin.y
	sb.content_margin_right = margin.z
	sb.content_margin_bottom = margin.w
	sb.anti_aliasing = true
	return sb


static func _circle_texture(diameter: int, fill: Color, ring: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c := Vector2(diameter, diameter) * 0.5 - Vector2(0.5, 0.5)
	var r := float(diameter) * 0.5 - 1.0
	for y in range(diameter):
		for x in range(diameter):
			var d := Vector2(x, y).distance_to(c)
			var col := Color(0, 0, 0, 0)
			if d <= r - 4.0:
				col = fill
			elif d <= r:
				col = ring
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func make_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var f := font()
	t.default_font = f
	t.default_font_size = 22

	# Etiquetas
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_font_size("font_size", "Label", 22)

	# Paneles
	var panel := box(PANEL_BG, Color(1, 1, 1, 0.06), 1, 10, Vector4(20, 16, 20, 16))
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	# Botones (la altura mínima de 64 px sale de los márgenes + fuente de 24)
	var btn_normal := box(Color(0.10, 0.10, 0.13, 0.9), Color(1, 1, 1, 0.14), 2)
	var btn_hover := box(Color(0.16, 0.15, 0.12, 0.95), GOLD_DARK, 2)
	var btn_pressed := box(GOLD, GOLD_DARK, 2)
	var btn_disabled := box(Color(0.08, 0.08, 0.1, 0.6), Color(1, 1, 1, 0.05), 2)
	var btn_focus := box(Color(0, 0, 0, 0), GOLD, 2)
	for type_name in ["Button", "CheckButton", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type_name, btn_normal)
		t.set_stylebox("hover", type_name, btn_hover)
		t.set_stylebox("pressed", type_name, btn_pressed)
		t.set_stylebox("hover_pressed", type_name, btn_pressed)
		t.set_stylebox("disabled", type_name, btn_disabled)
		t.set_stylebox("focus", type_name, btn_focus)
		t.set_font_size("font_size", type_name, 24)
		t.set_color("font_color", type_name, TEXT)
		t.set_color("font_hover_color", type_name, TEXT)
		t.set_color("font_focus_color", type_name, TEXT)
		t.set_color("font_pressed_color", type_name, Color(0.06, 0.05, 0.02))
		t.set_color("font_hover_pressed_color", type_name, Color(0.06, 0.05, 0.02))
		t.set_color("font_disabled_color", type_name, Color(1, 1, 1, 0.3))
		t.set_color("font_outline_color", type_name, Color(0, 0, 0, 0))
		t.set_constant("h_separation", type_name, 14)

	# Casillas (CheckButton): estilos de la caja con texto dorado al activarse
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_color("font_hover_pressed_color", "CheckButton", TEXT)
	var chk_on := box(Color(0.10, 0.10, 0.13, 0.9), GOLD, 2)
	t.set_stylebox("pressed", "CheckButton", chk_on)
	t.set_stylebox("hover_pressed", "CheckButton", chk_on)

	# Lista desplegable
	var popup := box(Color(0.05, 0.05, 0.07, 0.97), GOLD_DARK, 2, 10, Vector4(8, 8, 8, 8))
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(Color(GOLD.r, GOLD.g, GOLD.b, 0.35), Color(0, 0, 0, 0), 0, 8, Vector4(8, 8, 8, 8)))
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_constant("v_separation", "PopupMenu", 22)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", TEXT)

	# Deslizadores con agarradera grande para el dedo
	if _grabber == null:
		_grabber = _circle_texture(44, GOLD, Color(0.1, 0.08, 0.02, 1))
	var track := box(Color(1, 1, 1, 0.18), Color(0, 0, 0, 0), 0, 4, Vector4(0, 4, 0, 4))
	var filled := box(GOLD, Color(0, 0, 0, 0), 0, 4, Vector4(0, 4, 0, 4))
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	t.set_icon("grabber", "HSlider", _grabber)
	t.set_icon("grabber_highlight", "HSlider", _grabber)
	t.set_icon("grabber_disabled", "HSlider", _grabber)

	# Barras
	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.5), 1, 4, Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", box(Color(0.86, 0.14, 0.14), Color(0, 0, 0, 0), 0, 4, Vector4(0, 0, 0, 0)))

	# Scroll
	t.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 6, Vector4(6, 0, 6, 0)))
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.35), Color(0, 0, 0, 0), 0, 6, Vector4(6, 0, 6, 0)))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(GOLD, Color(0, 0, 0, 0), 0, 6, Vector4(6, 0, 6, 0)))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(GOLD, Color(0, 0, 0, 0), 0, 6, Vector4(6, 0, 6, 0)))

	_theme = t
	return t


## Etiqueta con contorno, lista para añadir al árbol.
static func label(text: String, size: int = 22, color: Color = Color.WHITE, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", maxi(2, int(size / 8.0)))
	if bold:
		l.add_theme_font_override("font", bold_font())
	return l


## Botón táctil de al menos 64 px de alto.
static func make_button(text: String, min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, BUTTON_MIN_HEIGHT)
	b.focus_mode = Control.FOCUS_NONE
	return b


## 1250 -> "$1.250"
static func format_money(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return ("-$" if value < 0 else "$") + out


## "2026-10-28 14:03:00" -> "28/10 14:03"
static func format_saved_at(saved_at: String) -> String:
	var parts := saved_at.split(" ")
	if parts.size() < 2:
		return saved_at
	var d := parts[0].split("-")
	if d.size() < 3:
		return saved_at
	return "%s/%s %s" % [d[2], d[1], parts[1].substr(0, 5)]


## Texto de una ranura: "Ranura 1 · 28/10 14:03 · $1.250 · 1 misión" o "Ranura 2 · Vacía".
static func slot_text(slot: int, name_override: String = "") -> String:
	var title := name_override if name_override != "" else "Ranura %d" % slot
	var sm: Dictionary = SaveSystem.slot_summary(slot)
	if not bool(sm.get("exists", false)):
		return "%s · Vacía" % title
	var n: int = int(sm.get("missions", 0))
	var missions := "1 misión" if n == 1 else "%d misiones" % n
	return "%s · %s · %s · %s" % [title, format_saved_at(String(sm.get("saved_at", ""))), format_money(int(sm.get("money", 0))), missions]


## Área segura (notch / barra inferior de iOS) en coordenadas locales de `c`.
## Siempre deja al menos `min_margin` px por lado.
static func safe_rect(c: Control, min_margin: float = 24.0) -> Rect2:
	var full := Rect2(Vector2.ZERO, c.size)
	var inner := Rect2(full.position + Vector2(min_margin, min_margin), full.size - Vector2(min_margin, min_margin) * 2.0)
	if not OS.has_feature("mobile") or not c.is_inside_tree():
		return inner
	var area := Rect2(DisplayServer.get_display_safe_area())
	if area.size.x < 100.0 or area.size.y < 100.0:
		return inner
	var inv := c.get_viewport().get_screen_transform().affine_inverse()
	var tl: Vector2 = inv * area.position
	var br: Vector2 = inv * area.end
	var r := Rect2(tl, br - tl).intersection(full)
	if r.size.x < 200.0 or r.size.y < 200.0:
		return inner
	var left := maxf(r.position.x, min_margin)
	var top := maxf(r.position.y, min_margin)
	var right := minf(r.end.x, full.size.x - min_margin)
	var bottom := minf(r.end.y, full.size.y - min_margin)
	return Rect2(left, top, right - left, bottom - top)
