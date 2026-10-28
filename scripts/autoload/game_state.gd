extends Node
## Estado de la partida en curso: dinero, salud, reputación, misiones y posición.
## Se serializa entero con to_dict()/from_dict() para el guardado.

const MAX_HEALTH := 100.0
const START_MONEY := 250

var money: int = 0
var health: float = MAX_HEALTH
var reputation: Dictionary = {}
var completed_missions: Array = []
var player_position: Vector3 = Vector3.ZERO
var player_yaw: float = 0.0
var has_position: bool = false
var play_time: float = 0.0
var in_game: bool = false
var active_mission: String = ""
var mission_step: int = 0
## Hora del juego en minutos desde medianoche (1 minuto de juego = 1 segundo real).
var world_minutes: float = 7.0 * 60.0 + 30.0


func _process(delta: float) -> void:
	if in_game and not get_tree().paused:
		play_time += delta
		world_minutes = fposmod(world_minutes + delta, 24.0 * 60.0)


func new_game() -> void:
	money = START_MONEY
	health = MAX_HEALTH
	completed_missions = []
	has_position = false
	player_position = Vector3.ZERO
	player_yaw = 0.0
	play_time = 0.0
	active_mission = ""
	mission_step = 0
	world_minutes = 7.0 * 60.0 + 30.0
	reputation = {}
	for f in GameData.factions:
		reputation[String(f["id"])] = int(f.get("start_reputation", 0))
	EventBus.money_changed.emit(money)


func add_money(amount: int) -> void:
	money = max(0, money + amount)
	EventBus.money_changed.emit(money)


func change_reputation(faction_id: String, delta: int) -> void:
	var value: int = clampi(int(reputation.get(faction_id, 0)) + delta, -100, 100)
	reputation[faction_id] = value
	EventBus.reputation_changed.emit(faction_id, value)


func set_health(value: float) -> void:
	health = clampf(value, 0.0, MAX_HEALTH)


func is_mission_completed(mission_number: int) -> bool:
	return completed_missions.has(mission_number)


func next_mission_number() -> int:
	var n := 1
	while completed_missions.has(n):
		n += 1
	return n


func complete_mission(mission_number: int) -> void:
	if completed_missions.has(mission_number):
		return
	completed_missions.append(mission_number)
	completed_missions.sort()
	EventBus.mission_completed.emit(mission_number)
	for zone_id in GameData.zones_unlocked_by(mission_number):
		EventBus.zone_unlocked.emit(zone_id)


func is_zone_unlocked(zone_id: String) -> bool:
	var z := GameData.zone(zone_id)
	if z.is_empty():
		return false
	var m := int(z.get("unlock_after_mission", 0))
	return m == 0 or completed_missions.has(m)


func to_dict() -> Dictionary:
	return {
		"money": money,
		"health": health,
		"reputation": reputation.duplicate(),
		"completed_missions": completed_missions.duplicate(),
		"player_position": [player_position.x, player_position.y, player_position.z],
		"player_yaw": player_yaw,
		"has_position": has_position,
		"play_time": play_time,
		"active_mission": active_mission,
		"mission_step": mission_step,
		"world_minutes": world_minutes,
	}


func from_dict(d: Dictionary) -> void:
	money = int(d.get("money", START_MONEY))
	health = clampf(float(d.get("health", MAX_HEALTH)), 1.0, MAX_HEALTH)
	reputation = {}
	var rep: Dictionary = d.get("reputation", {})
	for k in rep:
		reputation[String(k)] = int(rep[k])
	completed_missions = []
	for m in d.get("completed_missions", []):
		completed_missions.append(int(m))
	completed_missions.sort()
	var p: Array = d.get("player_position", [0, 0, 0])
	if p.size() == 3:
		player_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	player_yaw = float(d.get("player_yaw", 0.0))
	has_position = bool(d.get("has_position", false))
	play_time = float(d.get("play_time", 0.0))
	active_mission = String(d.get("active_mission", ""))
	mission_step = int(d.get("mission_step", 0))
	world_minutes = float(d.get("world_minutes", 7.0 * 60.0 + 30.0))
	EventBus.money_changed.emit(money)
