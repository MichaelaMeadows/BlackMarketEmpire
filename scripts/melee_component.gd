extends Node2D

@export var weapon_name := "Baseball Bat"
@export var weapon_type := "bat"
@export var damage := 18
@export var range := 70.0
@export var arc_degrees := 95.0
@export var swing_cooldown := 0.55
@export var swing_duration := 0.16
@export var knockback := 0.0

var cooldown_remaining := 0.0
var swing_remaining := 0.0
var last_hit_targets: Array = []
var _swing_direction := Vector2.RIGHT


func _process(delta: float) -> void:
	cooldown_remaining = max(0.0, cooldown_remaining - delta)
	swing_remaining = max(0.0, swing_remaining - delta)
	if swing_remaining > 0.0:
		queue_redraw()
	elif visible:
		visible = false
		queue_redraw()


func setup(weapon_data: Dictionary) -> void:
	weapon_name = str(weapon_data.get("name", weapon_name))
	weapon_type = str(weapon_data.get("weapon_type", weapon_type))
	damage = max(1, int(weapon_data.get("damage", damage)))
	range = max(12.0, float(weapon_data.get("range", range)))
	arc_degrees = clampf(float(weapon_data.get("arc_degrees", arc_degrees)), 5.0, 180.0)
	swing_cooldown = max(0.01, float(weapon_data.get("swing_cooldown", swing_cooldown)))
	swing_duration = max(0.01, float(weapon_data.get("swing_duration", swing_duration)))
	knockback = max(0.0, float(weapon_data.get("knockback", knockback)))
	cooldown_remaining = 0.0
	swing_remaining = 0.0
	last_hit_targets = []
	visible = false


func try_swing(owner: Node2D, direction: Vector2) -> bool:
	if owner == null or cooldown_remaining > 0.0 or direction.length() <= 0.0:
		return false

	_swing_direction = direction.normalized()
	last_hit_targets = []
	visible = true
	swing_remaining = swing_duration
	cooldown_remaining = swing_cooldown
	_hit_targets(owner)
	queue_redraw()
	return true


func is_swinging() -> bool:
	return swing_remaining > 0.0


func get_effective_range() -> float:
	return range


func _draw() -> void:
	if swing_remaining <= 0.0:
		return

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	var base_angle := _swing_direction.angle()
	var half_arc := deg_to_rad(arc_degrees * 0.5)
	var segment_count := 14
	for index in range(segment_count + 1):
		var t := float(index) / float(segment_count)
		var angle := base_angle - half_arc + half_arc * 2.0 * t
		points.append(Vector2(cos(angle), sin(angle)) * range)
	draw_colored_polygon(points, Color(1.0, 0.82, 0.28, 0.20))

	var edge_points := PackedVector2Array()
	for index in range(segment_count + 1):
		var t := float(index) / float(segment_count)
		var angle := base_angle - half_arc + half_arc * 2.0 * t
		edge_points.append(Vector2(cos(angle), sin(angle)) * range)
	draw_polyline(edge_points, Color(1.0, 0.88, 0.42, 0.75), 4.0, true)


func _hit_targets(owner: Node2D) -> void:
	var tree: SceneTree = owner.get_tree()
	if tree == null:
		return

	for candidate in tree.get_nodes_in_group("damageable"):
		var target_node := candidate as Node2D
		if target_node == null or target_node == owner:
			continue
		if not target_node.has_method("apply_damage"):
			continue
		if not _is_in_arc(owner.global_position, target_node.global_position):
			continue

		if target_node.has_method("notify_attacked_by"):
			target_node.notify_attacked_by(owner)
		target_node.apply_damage(damage)
		last_hit_targets.append(target_node)
		_apply_knockback(owner, target_node)


func _is_in_arc(owner_position: Vector2, target_position: Vector2) -> bool:
	var offset := target_position - owner_position
	if offset.length() > range:
		return false
	if offset.length() <= 0.01:
		return true
	var angle_degrees: float = abs(rad_to_deg(_swing_direction.angle_to(offset.normalized())))
	return angle_degrees <= arc_degrees * 0.5


func _apply_knockback(owner: Node2D, target: Node) -> void:
	var body := target as CharacterBody2D
	if knockback <= 0.0 or body == null:
		return
	var direction: Vector2 = body.global_position - owner.global_position
	if direction.length() <= 0.01:
		return
	body.velocity += direction.normalized() * knockback
