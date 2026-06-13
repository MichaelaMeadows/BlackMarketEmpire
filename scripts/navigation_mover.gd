extends RefCounted
class_name NavigationMover


static func move_towards(actor: CharacterBody2D, target: Vector2, speed: float, delta: float, navigation = null) -> bool:
	var final_target := _get_navigable_position(target, navigation)
	var offset: Vector2 = final_target - actor.position
	if offset.length() <= 8.0:
		actor.position = final_target
		actor.velocity = Vector2.ZERO
		return true

	var waypoint := _get_navigation_waypoint(actor.position, final_target, navigation)
	var waypoint_offset := waypoint - actor.position
	if waypoint_offset.length() <= 0.01:
		waypoint_offset = offset
	var direction: Vector2 = waypoint_offset.normalized()
	actor.velocity = direction * speed
	actor.position += direction * min(speed * delta, waypoint_offset.length())
	if actor.has_method("set_facing_direction"):
		actor.set_facing_direction(direction)
	return false


static func _get_navigable_position(position: Vector2, navigation) -> Vector2:
	if navigation != null and navigation.has_method("find_nearest_walkable"):
		return navigation.find_nearest_walkable(position)
	return position


static func _get_navigation_waypoint(from_position: Vector2, to_position: Vector2, navigation) -> Vector2:
	if navigation == null or not navigation.has_method("find_path"):
		return to_position
	var path: PackedVector2Array = navigation.find_path(from_position, to_position)
	if path.is_empty():
		return to_position
	return path[0]
