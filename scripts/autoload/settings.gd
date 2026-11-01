extends Node
## Ajustes del jugador: calidad gráfica, FPS, controles y accesibilidad.
## Se guardan en user://settings.cfg y se aplican al instante.
##
## Niveles gráficos (render Forward+ en Metal):
##  - Alta: SDFGI, niebla volumétrica, SSAO, SSIL, SSR, sombras PCSS en 4 cortes,
##    FSR2 al 80 % (con su TAA), reflejos dinámicos, hierba 3D y postproceso completo.
##  - Media: igual pero sin SDFGI ni niebla volumétrica, efectos a media resolución.
##  - Baja: lo de antes (render "mobile" tras reiniciar, sin efectos de pantalla).

const PATH := "user://settings.cfg"
## Fichero que Godot lee al arrancar (application/config/project_settings_override)
## para elegir el renderizador: la calidad baja usa "mobile" tras reiniciar.
const RENDER_OVERRIDE := "user://render_override.cfg"
const QUALITY_NAMES := {"low": "Baja", "medium": "Media", "high": "Alta"}
## Versión del autoajuste de calidad: al subirla se vuelve a detectar el dispositivo una vez.
const AUTO_DETECT_VERSION := 2

var quality: String = "high"
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
		quality = detect_quality()
		return
	quality = String(cfg.get_value("graphics", "quality", quality))
	if int(cfg.get_value("graphics", "auto_detect", 0)) < AUTO_DETECT_VERSION:
		# Ajustes de una versión anterior (que usaba "media" por defecto): se detecta de nuevo.
		quality = detect_quality()
	if not QUALITY_NAMES.has(quality):
		quality = detect_quality()
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
	cfg.set_value("graphics", "auto_detect", AUTO_DETECT_VERSION)
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
		if forward_plus():
			# FSR2 reconstruye a resolución completa y hace de TAA (sin MSAA ni FXAA).
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if quality != "low" else Viewport.SCALING_3D_MODE_BILINEAR
			vp.fsr_sharpness = 0.35
			vp.use_taa = false
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if quality != "low" else Viewport.SCREEN_SPACE_AA_FXAA
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		vp.mesh_lod_threshold = 1.0 if quality == "high" else (2.0 if quality == "medium" else 4.0)
		vp.positional_shadow_atlas_size = 2048 if quality == "high" else 1024
	RenderingServer.directional_shadow_atlas_set_size(shadow_atlas_size(), true)
	_apply_render_quality()
	EventBus.settings_changed.emit()


## Calidad interna de los efectos de pantalla (la escena los activa en SkyEnv).
func _apply_render_quality() -> void:
	var rs := RenderingServer
	if quality == "high":
		rs.directional_soft_shadow_filter_set_quality(rs.SHADOW_QUALITY_SOFT_MEDIUM)
		rs.positional_soft_shadow_filter_set_quality(rs.SHADOW_QUALITY_SOFT_LOW)
		rs.environment_set_ssao_quality(rs.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
		rs.environment_set_ssil_quality(rs.ENV_SSIL_QUALITY_LOW, true, 0.5, 2, 50.0, 300.0)
		rs.environment_set_ssr_roughness_quality(rs.ENV_SSR_ROUGHNESS_QUALITY_LOW)
		rs.environment_set_ssr_half_size(true)
		rs.environment_set_sdfgi_ray_count(rs.ENV_SDFGI_RAY_COUNT_8)
		rs.environment_set_sdfgi_frames_to_converge(rs.ENV_SDFGI_CONVERGE_IN_20_FRAMES)
		rs.environment_set_sdfgi_frames_to_update_light(rs.ENV_SDFGI_UPDATE_LIGHT_IN_8_FRAMES)
		rs.environment_set_volumetric_fog_volume_size(64, 48)
		rs.environment_set_volumetric_fog_filter_active(true)
		rs.camera_attributes_set_dof_blur_quality(rs.DOF_BLUR_QUALITY_MEDIUM, true)
	else:
		rs.directional_soft_shadow_filter_set_quality(rs.SHADOW_QUALITY_SOFT_LOW if quality == "medium" else rs.SHADOW_QUALITY_HARD)
		rs.positional_soft_shadow_filter_set_quality(rs.SHADOW_QUALITY_HARD)
		rs.environment_set_ssao_quality(rs.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 50.0, 300.0)
		rs.environment_set_ssil_quality(rs.ENV_SSIL_QUALITY_VERY_LOW, true, 0.5, 1, 50.0, 300.0)
		rs.environment_set_ssr_roughness_quality(rs.ENV_SSR_ROUGHNESS_QUALITY_DISABLED)
		rs.environment_set_ssr_half_size(true)
		rs.camera_attributes_set_dof_blur_quality(rs.DOF_BLUR_QUALITY_LOW, true)
	rs.camera_attributes_set_dof_blur_bokeh_shape(rs.DOF_BOKEH_CIRCLE)


func set_quality(q: String) -> void:
	if QUALITY_NAMES.has(q):
		quality = q
		apply()
		save_settings()
		_write_render_override()


# ---------------------------------------------------------------- dispositivo y renderizador

## Elige el nivel según el dispositivo: Alta en iPhone 16 / 16e o superior (A18,
## identificador iPhone17,x) y en ordenadores; Media en iPhone 15 Pro (A17 Pro, 8 GB);
## Baja en el resto o con poca memoria.
func detect_quality() -> String:
	var model := OS.get_model_name()
	var mem_gb := float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	if model.begins_with("iPhone") or model.begins_with("iPad"):
		var digits := model.trim_prefix("iPhone").trim_prefix("iPad").get_slice(",", 0)
		var major := int(digits) if digits.is_valid_int() else 0
		if model.begins_with("iPhone"):
			if major >= 17:
				return "high"
			if major == 16:
				return "medium"
			return "low"
		# iPad: M1 o superior (iPad13,x en adelante) aguanta Alta.
		return "high" if major >= 13 else ("medium" if mem_gb >= 3.5 else "low")
	if OS.has_feature("mobile"):
		if mem_gb >= 7.5:
			return "high"
		return "medium" if mem_gb >= 5.5 else "low"
	return "high"


## true si el juego corre en Forward+ (los efectos avanzados solo existen ahí).
func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## true si al reiniciar cambiaría el renderizador (calidad baja <-> resto).
func needs_restart() -> bool:
	if not OS.has_feature("mobile"):
		return false
	var wanted := "mobile" if quality == "low" else "forward_plus"
	return RenderingServer.get_current_rendering_method() != wanted


## En móvil, la calidad baja arranca con el renderizador "mobile" (más ligero).
## Se escribe un override que Godot lee al iniciar; en escritorio no se toca.
func _write_render_override() -> void:
	if not OS.has_feature("mobile"):
		return
	if quality == "low":
		var f := FileAccess.open(RENDER_OVERRIDE, FileAccess.WRITE)
		if f:
			f.store_string("[rendering]\n\nrenderer/rendering_method=\"mobile\"\nrenderer/rendering_method.mobile=\"mobile\"\n")
			f.close()
	elif FileAccess.file_exists(RENDER_OVERRIDE):
		DirAccess.remove_absolute(RENDER_OVERRIDE)


func cycle_quality() -> void:
	var order := ["low", "medium", "high"]
	set_quality(order[(order.find(quality) + 1) % order.size()])


func render_scale() -> float:
	match quality:
		"low":
			return 0.67
		"high":
			return 0.8
	return 0.7


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
			return 120.0
	return 80.0


## Efectos de pantalla y de iluminación por nivel (los lee SkyEnv).
func use_screen_effects() -> bool:
	return quality != "low" and forward_plus()


func use_sdfgi() -> bool:
	return quality == "high" and forward_plus()


func use_volumetric_fog() -> bool:
	return quality == "high" and forward_plus()


func shadow_splits() -> int:
	return 4 if quality != "low" else 2


## Hierba 3D: radio en celdas alrededor de la cámara (0 = sin hierba).
func grass_cells() -> int:
	match quality:
		"high":
			return 2
		"medium":
			return 1
	return 0


## Postproceso propio (motion blur, viñeta y grano).
func use_post_fx() -> bool:
	return quality != "low"


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
