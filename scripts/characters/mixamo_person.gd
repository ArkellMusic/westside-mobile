class_name MixamoPerson
extends Node3D
## Peatón realista con modelo y animaciones de Mixamo (Adobe, uso libre en juegos).
## Misma interfaz que Humanoid para pedestrians.gd: setup(look), animate(delta, speed, on_floor),
## pose_idle_stance(kind), set_seated(on) y la propiedad look. Mira hacia -Z.
##
## - Los 6 modelos (assets/characters/mixamo/*.scn) comparten una AnimationLibrary
##   (assets/animations/mixamo/lib.res): idle / walk / run / sit_talk / phone, sin root motion.
## - Mezcla por velocidad: idle -> andar -> correr con fundido de 0,25 s; la velocidad de la
##   animación se ajusta a la del peatón para que los pies no patinen.
## - Atropello: en el aire/suelo (on_floor = false) la animación se congela en una pose de
##   zancada abierta (cuerpo "flácido"); vuelve a animarse con animate(..., true).
## - Rendimiento: las mallas se ocultan a VIS_END m; solo se animan los MAX_ANIMATED peatones
##   más cercanos y a menos de ANIM_RANGE m; el resto queda congelado en su última pose.

const MODELS := [
	"res://assets/characters/mixamo/ch07.scn",
	"res://assets/characters/mixamo/ch12.scn",
	"res://assets/characters/mixamo/ch28.scn",
	"res://assets/characters/mixamo/ch06.scn",
	"res://assets/characters/mixamo/ch22.scn",
	"res://assets/characters/mixamo/remy.scn",
]
## Elevación (m) por modelo medida con el vértice más bajo de la malla en las poses de andar e idle:
## sin ella los pies se hunden 1-4 cm bajo el suelo.
const FOOT_LIFT := [0.037, 0.032, 0.023, 0.027, 0.030, 0.012]
const LIB_PATH := "res://assets/animations/mixamo/lib.res"
const ANIM_RANGE := 40.0
const MAX_ANIMATED := 25
const VIS_END := 110.0
const RANK_EVERY := 8   # fotogramas de física entre reordenaciones
## Tintes suaves para la ropa (multiplican la textura). El primero es el original.
const TINTS := [
	Color(1, 1, 1), Color(0.72, 0.82, 1.0), Color(1.0, 0.78, 0.74), Color(0.76, 0.98, 0.82),
	Color(0.62, 0.62, 0.68), Color(1.0, 0.93, 0.66), Color(0.88, 0.72, 1.0),
]

static var _lib: AnimationLibrary = null
static var _scenes: Dictionary = {}
static var _tint_mats: Dictionary = {}
static var _all: Array = []
static var _rank_frame: int = -1000

var look: Dictionary = {}
var base_scale: float = 1.0
var lie_y: float = 0.3   # altura del origen cuando está tumbado sobre la acera (pedestrians.gd)

var _built: bool = false
var _pivot: Node3D
var _model: Node3D
var _skel: Skeleton3D
var _player: AnimationPlayer
var _meshes: Array = []
var _state: String = ""
var _speed_blend: float = 0.0
var _active: bool = true
var _downed: bool = false
var _seated: bool = false
var _forced: String = ""   # animación fija (phone, sit_talk)
var _walk_speed: float = 1.0
var _run_speed: float = 5.9


## ¿Están los recursos? Si no, pedestrians.gd usa Humanoid como respaldo.
static func available() -> bool:
	if not ResourceLoader.exists(LIB_PATH) or _library() == null:
		return false
	for p in MODELS:
		if not ResourceLoader.exists(p):
			return false
		if not _scenes.has(p):
			_scenes[p] = load(p)
		if _scenes[p] == null:
			return false
	return true


static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"model": rng.randi() % MODELS.size(),
		"tint": rng.randi() % TINTS.size(),
		"scale": rng.randf_range(0.95, 1.05),
		"phase": rng.randf(),
	}


static func _library() -> AnimationLibrary:
	if _lib == null:
		_lib = load(LIB_PATH) as AnimationLibrary
	return _lib


func _enter_tree() -> void:
	if not _all.has(self):
		_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)


func setup(appearance: Dictionary) -> void:
	look = appearance
	for c in get_children():
		remove_child(c)
		c.free()
	_built = false
	_meshes.clear()
	var lib := _library()
	var mi := int(look.get("model", 0)) % MODELS.size()
	var path: String = MODELS[mi]
	if not _scenes.has(path):
		_scenes[path] = load(path)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.rotation.y = PI   # los modelos de Mixamo miran a +Z
	_pivot.position.y = float(FOOT_LIFT[mi])
	add_child(_pivot)
	_model = (_scenes[path] as PackedScene).instantiate()
	_pivot.add_child(_model)
	_skel = _model.get_node("Skeleton3D") as Skeleton3D
	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	_pivot.add_child(_player)
	_player.root_node = _player.get_path_to(_model)
	_player.add_animation_library("", lib)
	_player.playback_default_blend_time = 0.25
	_walk_speed = float(lib.get_animation("walk").get_meta("speed", 1.0))
	_run_speed = float(lib.get_animation("run").get_meta("speed", 5.9))
	base_scale = float(look.get("scale", 1.0))
	scale = Vector3.ONE * base_scale
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		m.visibility_range_end = VIS_END
		m.visibility_range_end_margin = 8.0
		_meshes.append(m)
		_apply_tint(m, int(look.get("tint", 0)), mi)
	_built = true
	_state = ""
	_play("idle", 1.0)
	_player.seek(float(look.get("phase", 0.0)) * _player.current_animation_length, true)


## Tinte suave de la ropa con un máximo de TINTS.size() materiales por modelo y superficie.
func _apply_tint(m: MeshInstance3D, tint: int, model_idx: int) -> void:
	if tint <= 0 or tint >= TINTS.size() or not m.has_meta("cloth_surfaces"):
		return
	for s in m.get_meta("cloth_surfaces"):
		var key := "%d_%d_%d" % [model_idx, int(s), tint]
		if not _tint_mats.has(key):
			var base := m.mesh.surface_get_material(int(s)) as StandardMaterial3D
			var t := base.duplicate() as StandardMaterial3D
			t.albedo_color = TINTS[tint]
			_tint_mats[key] = t
		m.set_surface_override_material(int(s), _tint_mats[key])


func _play(anim: String, speed: float) -> void:
	if _state != anim:
		_state = anim
		_player.play(anim)
	_player.speed_scale = speed


## Reordena qué peatones se animan: los MAX_ANIMATED más cercanos a la cámara y a < ANIM_RANGE m.
static func _rank() -> void:
	var frame := Engine.get_physics_frames()
	if frame - _rank_frame < RANK_EVERY:
		return
	_rank_frame = frame
	var cam: Camera3D = null
	if not _all.is_empty() and (_all[0] as Node).is_inside_tree():
		cam = (_all[0] as Node).get_viewport().get_camera_3d()
	var pos := cam.global_position if cam else Vector3.ZERO
	var list: Array = []
	for p in _all:
		var mp := p as MixamoPerson
		if not mp.is_inside_tree():
			continue
		var d := (mp.global_position - pos).length() if cam else 0.0
		list.append([d, mp])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for i in list.size():
		(list[i][1] as MixamoPerson)._active = i < MAX_ANIMATED and float(list[i][0]) < ANIM_RANGE


## speed en m/s; on_floor = false -> atropellado / en el aire (pose congelada).
func animate(_delta: float, speed: float, on_floor: bool) -> void:
	if not _built:
		return
	_rank()
	if not on_floor:
		if not _downed:
			_downed = true
			_forced = ""
			_state = "downed"
			_player.play("run")
			_player.speed_scale = 0.0
			_player.seek(_player.current_animation_length * 0.22, true)
			_player.pause()
		return
	if _downed:
		_downed = false
		_state = ""
	if not _active:
		if _player.is_playing():
			_player.pause()
		return
	if _forced != "":
		_play(_forced, 1.0)
		if not _player.is_playing():
			_player.play(_forced)
		return
	_speed_blend = lerpf(_speed_blend, speed, clampf(_delta * 6.0, 0.0, 1.0))
	var s := _speed_blend
	if s < 0.25:
		_play("idle", 1.0)
	elif s < 3.2:
		_play("walk", clampf(s / _walk_speed, 0.6, 2.2))
	else:
		_play("run", clampf(s / _run_speed, 0.7, 1.6))
	if not _player.is_playing():
		_player.play(_state)


## Posturas de espera para personajes quietos (compatibilidad con Humanoid).
func pose_idle_stance(kind: String) -> void:
	if not _built:
		return
	_forced = "phone" if kind == "phone" else "idle"
	_state = ""
	_play(_forced, 1.0)


func set_seated(on: bool) -> void:
	_seated = on
	if not _built:
		return
	_forced = "sit_talk" if on else ""
	_state = ""
	if on:
		_play("sit_talk", 1.0)


## Número de peatones que se están animando ahora (para tests).
static func animated_count() -> int:
	var n := 0
	for p in _all:
		if (p as MixamoPerson)._active:
			n += 1
	return n
