extends Node
## Punto único de entrada de controles. Junta controles táctiles y teclado/ratón
## para que el jugador, el coche y la cámara no dependan del dispositivo.

## Movimiento: x = derecha, y = adelante. Longitud máxima 1.
var move: Vector2 = Vector2.ZERO
var touch_move: Vector2 = Vector2.ZERO

var _look: Vector2 = Vector2.ZERO
var _held: Dictionary = {}
var _just: Dictionary = {}
var enabled: bool = true

const KEYS := {
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"interact": [KEY_F, KEY_ENTER],
	"gas": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"handbrake": [KEY_SPACE],
	"pause": [KEY_ESCAPE, KEY_P],
	"map": [KEY_M],
	"radio": [KEY_R],
}


func _process(_delta: float) -> void:
	var kb := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		kb.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		kb.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		kb.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		kb.x -= 1.0
	move = (touch_move + kb).limit_length(1.0) if enabled else Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		for action in KEYS:
			if (KEYS[action] as Array).has(event.physical_keycode):
				_just[action] = Engine.get_process_frames()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		add_look(event.relative)


## Llamado por los botones táctiles.
func press(action: String, down: bool) -> void:
	if down and not _held.get(action, false):
		_just[action] = Engine.get_process_frames()
	_held[action] = down


func release_all() -> void:
	_held.clear()
	_just.clear()
	touch_move = Vector2.ZERO


func is_down(action: String) -> bool:
	if not enabled:
		return false
	if _held.get(action, false):
		return true
	for k in KEYS.get(action, []):
		if Input.is_physical_key_pressed(k):
			return true
	return false


## Devuelve true una sola vez por pulsación (válida durante unos pocos fotogramas).
func just_pressed(action: String) -> bool:
	if not _just.has(action):
		return false
	var frame: int = _just[action]
	_just.erase(action)
	return enabled and Engine.get_process_frames() - frame <= 3


func add_look(delta: Vector2) -> void:
	_look += delta


func consume_look() -> Vector2:
	var l := _look
	_look = Vector2.ZERO
	return l
