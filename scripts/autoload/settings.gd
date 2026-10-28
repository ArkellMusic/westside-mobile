extends Node
## Ajustes del jugador: calidad gráfica, FPS, controles y accesibilidad.
## Se guardan en user://settings.cfg y se aplican al instante.

const PATH := "user://settings.cfg"
const QUALITY_NAMES := {"low": "Baja", "medium": "Media", "high": "Alta"}

var quality: String = "medium"
var fps_cap: int = 60
var controls_scale: float = 1.0
var controls_opacity: float = 0.75
var camera_sensitivity: float = 1.0
var invert_y: bool = false
var subtitles: bool = true
var show_fps: bool = false


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	quality = String(cfg.get_value("graphics", "quality", quality))
	if not QUALITY_NAMES.has(quality):
		quality = "medium"
	fps_cap = int(cfg.get_value("graphics", "fps_cap", fps_cap))
	show_fps = bool(cfg.get_value("graphics", "show_fps", show_fps))
	controls_scale = clampf(float(cfg.get_value("controls", "scale", controls_scale)), 0.7, 1.4)
	controls_opacity = clampf(float(cfg.get_value("controls", "opacity", controls_opacity)), 0.3, 1.0)
	camera_sensitivity = clampf(float(cfg.get_value("controls", "sensitivity", camera_sensitivity)), 0.3, 2.5)
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	subtitles = bool(cfg.get_value("accessibility", "subtitles", subtitles))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "fps_cap", fps_cap)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.set_value("controls", "scale", controls_scale)
	cfg.set_value("controls", "opacity", controls_opacity)
	cfg.set_value("controls", "sensitivity", camera_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("accessibility", "subtitles", subtitles)
	cfg.save(PATH)


func apply() -> void:
	Engine.max_fps = fps_cap
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = render_scale()
		vp.msaa_3d = Viewport.MSAA_2X if quality == "high" else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(shadow_atlas_size(), true)
	EventBus.settings_changed.emit()


func set_quality(q: String) -> void:
	if QUALITY_NAMES.has(q):
		quality = q
		apply()
		save_settings()


func cycle_quality() -> void:
	var order := ["low", "medium", "high"]
	set_quality(order[(order.find(quality) + 1) % order.size()])


func render_scale() -> float:
	match quality:
		"low":
			return 0.67
		"high":
			return 1.0
	return 0.85


func shadow_atlas_size() -> int:
	match quality:
		"low":
			return 1024
		"high":
			return 4096
	return 2048


func shadow_distance() -> float:
	match quality:
		"low":
			return 50.0
		"high":
			return 140.0
	return 90.0


func shadows_enabled() -> bool:
	return quality != "low"


func view_distance() -> float:
	match quality:
		"low":
			return 600.0
		"high":
			return 2400.0
	return 1500.0


func traffic_count() -> int:
	match quality:
		"low":
			return 6
		"high":
			return 16
	return 10


func pedestrian_count() -> int:
	match quality:
		"low":
			return 8
		"high":
			return 24
	return 14
