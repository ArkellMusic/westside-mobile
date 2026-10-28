class_name Traffic
extends Node3D
## Tráfico ligero: coches cinemáticos que siguen el grafo de calles por su carril,
## giran en los cruces y frenan si tienen algo delante. Son AnimatableBody3D,
## así que el coche del jugador choca contra ellos.

const LANE_OFFSET_STREET := 2.6
const LANE_OFFSET_AVENUE := 2.2

var graph: Dictionary
var cars: Array = []
var obstacles: Array = []  # nodos a evitar (jugador, coche del jugador...)
var rng := RandomNumberGenerator.new()
var enabled: bool = true


class TrafficCar:
	extends AnimatableBody3D
	var from_node: int
	var to_node: int
	var path: Array = []
	var speed: float = 0.0
	var cruise: float = 11.0
	var heading: Vector3 = Vector3.FORWARD
	var length: float = 4.7


func setup(count: int) -> void:
	rng.seed = 77
	graph = CityLayout.road_graph()
	var nodes: Array = graph["nodes"]
	var colors := CityBuilder.CAR_COLORS
	var used := {}
	for i in count:
		var tc := TrafficCar.new()
		tc.sync_to_physics = false
		var style := rng.randi() % 4
		var mi := MeshInstance3D.new()
		mi.mesh = CarModel.build(style, colors[rng.randi() % colors.size()], true)
		tc.add_child(mi)
		var spec := CarModel.spec(style)
		var shape := BoxShape3D.new()
		shape.size = Vector3(float(spec["half_w"]) * 2.0, float(spec["height"]) - 0.3, spec["length"])
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.3 + (float(spec["height"]) - 0.3) * 0.5
		tc.add_child(cs)
		tc.length = spec["length"]
		tc.cruise = rng.randf_range(9.0, 13.0)
		add_child(tc)
		# Nodo inicial distinto para cada coche.
		var start := rng.randi() % nodes.size()
		while used.has(start):
			start = (start + 1) % nodes.size()
		used[start] = true
		tc.from_node = start
		var links: Array = graph["links"][start]
		tc.to_node = links[rng.randi() % links.size()]
		var a: Vector2 = nodes[tc.from_node]
		var b: Vector2 = nodes[tc.to_node]
		var dir := (b - a).normalized()
		var p := a.lerp(b, rng.randf_range(0.3, 0.6)) + _right(dir) * _lane(dir)
		tc.global_position = Vector3(p.x, 0.04, p.y)
		tc.heading = Vector3(dir.x, 0, dir.y)
		tc.path = _segment_points(tc.from_node, tc.to_node)
		cars.append(tc)


func _right(dir: Vector2) -> Vector2:
	return Vector2(-dir.y, dir.x)


func _lane(dir: Vector2) -> float:
	return LANE_OFFSET_STREET if absf(dir.x) > absf(dir.y) else LANE_OFFSET_AVENUE


func _segment_points(a_i: int, b_i: int) -> Array:
	var nodes: Array = graph["nodes"]
	var a: Vector2 = nodes[a_i]
	var b: Vector2 = nodes[b_i]
	var dir := (b - a).normalized()
	var off := _right(dir) * _lane(dir)
	var end := b - dir * 9.0 + off
	return [Vector3(end.x, 0.04, end.y)]


func _choose_next(tc: TrafficCar) -> void:
	var links: Array = graph["links"][tc.to_node]
	var options: Array = []
	for l in links:
		if l != tc.from_node:
			options.append(l)
	if options.is_empty():
		options = links.duplicate()
	var nxt: int = options[rng.randi() % options.size()]
	var nodes: Array = graph["nodes"]
	var b: Vector2 = nodes[tc.to_node]
	var c: Vector2 = nodes[nxt]
	var d2 := (c - b).normalized()
	var off2 := _right(d2) * _lane(d2)
	var corner := b + off2 + d2 * 6.0
	tc.from_node = tc.to_node
	tc.to_node = nxt
	tc.path = [Vector3(corner.x, 0.04, corner.y)]
	tc.path.append_array(_segment_points(tc.from_node, tc.to_node))


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	for tc in cars:
		var car: TrafficCar = tc
		if car.path.is_empty():
			_choose_next(car)
		var target: Vector3 = car.path[0]
		var to_t := target - car.global_position
		to_t.y = 0
		if to_t.length() < 2.0:
			car.path.pop_front()
			continue
		var desired := to_t.normalized()
		var turn := car.heading.signed_angle_to(desired, Vector3.UP)
		var max_turn := 1.6 * delta
		car.heading = car.heading.rotated(Vector3.UP, clampf(turn, -max_turn, max_turn)).normalized()
		var want := car.cruise
		if absf(turn) > 0.5:
			want = 5.5
		if _blocked(car):
			want = 0.0
		car.speed = move_toward(car.speed, want, (9.0 if want < car.speed else 3.5) * delta)
		var pos := car.global_position + car.heading * car.speed * delta
		car.global_transform = Transform3D(Basis.looking_at(-car.heading, Vector3.UP), pos)


func _blocked(car: TrafficCar) -> bool:
	var ahead := car.heading
	var p := car.global_position
	for other in cars:
		if other == car:
			continue
		var d: Vector3 = (other as Node3D).global_position - p
		d.y = 0
		var along := d.dot(ahead)
		if along > 0.0 and along < 10.0 and absf(d.cross(ahead).y) < 2.0:
			return true
	for o in obstacles:
		var n := o as Node3D
		if n == null or not n.is_visible_in_tree():
			continue
		var d := n.global_position - p
		d.y = 0
		var along := d.dot(ahead)
		if along > 0.0 and along < 11.0 and absf(d.cross(ahead).y) < 2.4:
			return true
	return false
