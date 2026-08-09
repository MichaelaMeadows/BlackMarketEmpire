extends Node
class_name CombatAiController

const HOLD_ARRIVAL_DISTANCE := 10.0
const HOLD_REPOSITION_DISTANCE := 28.0

enum AiState {
	IDLE,
	FOLLOWING,
	MOVING_TO_ORDER,
	HOLDING,
	CHASING,
	ATTACKING,
	TAKING_COVER,
	IN_COVER,
	PEEKING,
	RELOADING_IN_COVER,
}

enum OrderType {
	AUTONOMOUS,
	FOLLOW,
	ATTACK,
	HOLD,
}

@export var enabled := true
@export var detection_radius := 560.0
@export var attack_range := 420.0
@export var preferred_range := 300.0
@export var chase_speed := 185.0
@export var follow_speed := 170.0
@export var cover_search_radius := 150.0
@export var cover_health_fraction := 0.45
@export var desired_follow_distance := 96.0
@export var combat_follow_leash := 360.0
@export var ally_alert_radius := 520.0
@export var preferred_spacing := 56.0
@export var role := "assault"
@export var reaction_time := 0.18
@export var target_memory_seconds := 2.0
@export var cover_reuse_seconds := 0.7
@export var suppression_cover_threshold := 1.0
@export var hold_distance_tolerance := 48.0
@export var default_hold_radius := 220.0

var owner_unit: CharacterBody2D
var faction := "neutral"
var hostile_factions: Array = []
var squad_id := ""
var current_target: Node2D
var current_target_confidence := 0.0
var follow_target: Node2D
var last_seen_position := Vector2.ZERO
var has_last_seen_position := false
var cover_position := Vector2.ZERO
var reaction_remaining := 0.0
var aim_confidence := 1.0
var time_since_seen_target := 0.0
var suppression_remaining := 0.0
var cover_reuse_remaining := 0.0
var state := AiState.IDLE
var order_type := OrderType.AUTONOMOUS
var order_target: Node2D
var order_position := Vector2.ZERO
var order_hold_radius := 220.0
var hold_anchor_reached := false
var _uses_weapon_attack_range := true
var _uses_weapon_preferred_range := true
var navigation


func setup(new_owner: CharacterBody2D, config: Dictionary = {}) -> void:
	owner_unit = new_owner
	enabled = bool(config.get("enabled", enabled))
	faction = str(config.get("faction", _read_owner_faction()))
	hostile_factions = _read_string_array(config.get("hostile_factions", hostile_factions))
	detection_radius = float(config.get("detection_radius", detection_radius))
	_uses_weapon_attack_range = not config.has("attack_range")
	_uses_weapon_preferred_range = not config.has("preferred_range")
	attack_range = float(config.get("attack_range", _get_owner_weapon_range("effective_range", attack_range)))
	preferred_range = float(config.get("preferred_range", _get_owner_weapon_range("preferred_range", preferred_range)))
	chase_speed = float(config.get("chase_speed", chase_speed))
	follow_speed = float(config.get("follow_speed", follow_speed))
	cover_search_radius = float(config.get("cover_search_radius", cover_search_radius))
	cover_health_fraction = float(config.get("cover_health_fraction", cover_health_fraction))
	desired_follow_distance = float(config.get("desired_follow_distance", desired_follow_distance))
	combat_follow_leash = float(config.get("combat_follow_leash", combat_follow_leash))
	ally_alert_radius = float(config.get("ally_alert_radius", ally_alert_radius))
	preferred_spacing = float(config.get("preferred_spacing", preferred_spacing))
	squad_id = str(config.get("squad_id", squad_id))
	role = str(config.get("role", role))
	reaction_time = max(0.0, float(config.get("reaction_time", reaction_time)))
	target_memory_seconds = max(0.0, float(config.get("target_memory_seconds", target_memory_seconds)))
	cover_reuse_seconds = max(0.0, float(config.get("cover_reuse_seconds", cover_reuse_seconds)))
	suppression_cover_threshold = max(0.0, float(config.get("suppression_cover_threshold", suppression_cover_threshold)))
	hold_distance_tolerance = max(0.0, float(config.get("hold_distance_tolerance", hold_distance_tolerance)))
	default_hold_radius = max(32.0, float(config.get("default_hold_radius", default_hold_radius)))
	order_hold_radius = default_hold_radius
	if config.has("navigation"):
		set_navigation(config.get("navigation"))
	add_to_group("combat_ai")


func set_navigation(new_navigation) -> void:
	navigation = new_navigation


func set_follow_target(target: Node2D, distance: float = -1.0, leash: float = -1.0) -> void:
	follow_target = target
	if distance >= 0.0:
		desired_follow_distance = distance
	if leash >= 0.0:
		combat_follow_leash = leash


func issue_follow_order(target: Node2D = null) -> void:
	if target != null:
		set_follow_target(target)
	order_type = OrderType.FOLLOW
	order_target = null
	hold_anchor_reached = false
	_set_current_target(null, 0.0)


func issue_attack_order(target: Node2D) -> bool:
	if target == null or not _is_valid_target(target) or not is_hostile(target):
		return false
	order_type = OrderType.ATTACK
	order_target = target
	hold_anchor_reached = false
	_set_current_target(target, 1.0)
	return true


func issue_hold_order(position: Vector2, radius: float = -1.0) -> void:
	order_type = OrderType.HOLD
	order_target = null
	order_position = position
	order_hold_radius = default_hold_radius if radius < 0.0 else max(32.0, radius)
	hold_anchor_reached = owner_unit != null and owner_unit.global_position.distance_to(order_position) <= HOLD_ARRIVAL_DISTANCE
	_set_current_target(null, 0.0)


func clear_order() -> void:
	order_type = OrderType.AUTONOMOUS
	order_target = null
	hold_anchor_reached = false
	_set_current_target(null, 0.0)


func get_order_name() -> String:
	match order_type:
		OrderType.FOLLOW:
			return "FOLLOW"
		OrderType.ATTACK:
			return "ATTACK"
		OrderType.HOLD:
			return "HOLD"
	return "AUTONOMOUS"


func clear_follow_target() -> void:
	follow_target = null


func set_hostile_factions(new_hostile_factions: Array) -> void:
	hostile_factions = _read_string_array(new_hostile_factions)


func force_target(target: Node2D, confidence: float = 1.0) -> void:
	if target == null or not _is_valid_target(target):
		return
	if not is_hostile(target):
		return
	_set_current_target(target, confidence)


func notify_attacked_by(attacker: Node) -> void:
	if not (attacker is Node2D):
		return

	var attacker_faction: String = _read_faction(attacker)
	if attacker_faction != "" and attacker_faction != faction and not hostile_factions.has(attacker_faction):
		hostile_factions.append(attacker_faction)

	if is_hostile(attacker):
		suppress(0.75)
		_set_current_target(attacker, 0.8)
		_alert_nearby_allies(attacker, 0.8)


func receive_shared_target(target: Node2D, ally: Node2D, confidence: float = 0.5) -> void:
	if owner_unit == null or target == null or ally == null:
		return
	if not _is_valid_target(target) or not is_hostile(target):
		return
	if order_type == OrderType.ATTACK and target != order_target:
		return
	if not _is_target_allowed_by_order(target):
		return
	if not _is_same_squad_or_faction(ally):
		return
	if owner_unit.global_position.distance_to(ally.global_position) > ally_alert_radius:
		return
	var visible_target: Node2D = find_visible_hostile()
	if visible_target != null and confidence <= 1.0:
		_set_current_target(visible_target, 1.0)
		return
	if _is_valid_target(current_target) and can_see(current_target, detection_radius) and current_target_confidence >= confidence:
		return

	_set_current_target(target, confidence)


func suppress(amount: float) -> void:
	suppression_remaining = max(suppression_remaining, amount)
	aim_confidence = max(0.0, aim_confidence - amount * 0.35)


func get_state_name() -> String:
	match state:
		AiState.IDLE:
			return "IDLE"
		AiState.FOLLOWING:
			return "FOLLOWING"
		AiState.MOVING_TO_ORDER:
			return "MOVING_TO_ORDER"
		AiState.HOLDING:
			return "HOLDING"
		AiState.CHASING:
			return "CHASING"
		AiState.ATTACKING:
			return "ATTACKING"
		AiState.TAKING_COVER:
			return "TAKING_COVER"
		AiState.IN_COVER:
			return "IN_COVER"
		AiState.PEEKING:
			return "PEEKING"
		AiState.RELOADING_IN_COVER:
			return "RELOADING_IN_COVER"
	return "UNKNOWN"


func _physics_process(delta: float) -> void:
	tick_ai(delta)


func tick_ai(_delta: float) -> void:
	if not enabled or owner_unit == null or not is_instance_valid(owner_unit):
		return
	if _is_dead(owner_unit):
		_stop()
		return

	_refresh_dynamic_weapon_ranges()
	reaction_remaining = max(0.0, reaction_remaining - _delta)
	cover_reuse_remaining = max(0.0, cover_reuse_remaining - _delta)
	suppression_remaining = max(0.0, suppression_remaining - _delta)
	aim_confidence = min(1.0, aim_confidence + _delta)

	if order_type == OrderType.ATTACK:
		if not _is_valid_target(order_target):
			order_target = null
			order_type = OrderType.FOLLOW if follow_target != null and is_instance_valid(follow_target) else OrderType.AUTONOMOUS
			_set_current_target(null, 0.0)
		else:
			_set_current_target(order_target, 1.0)
			last_seen_position = order_target.global_position
			has_last_seen_position = true
			if can_see(order_target):
				_act_against_visible_target(order_target)
			else:
				_chase_position(order_target.global_position)
			return

	if not _is_valid_target(current_target):
		_set_current_target(find_visible_hostile(), 1.0)

	if _is_valid_target(current_target) and can_see(current_target, detection_radius):
		time_since_seen_target = 0.0
		last_seen_position = current_target.global_position
		has_last_seen_position = true
		_alert_nearby_allies(current_target, 1.0)
		_act_against_visible_target(current_target)
		return

	if _is_valid_target(current_target) and has_last_seen_position:
		time_since_seen_target += _delta
		if time_since_seen_target > target_memory_seconds:
			_set_current_target(null, 0.0)
			_follow_anchor_or_idle()
			return
		_chase_position(last_seen_position)
		return

	_follow_anchor_or_idle()


func find_visible_hostile() -> Node2D:
	if owner_unit == null or owner_unit.get_tree() == null:
		return null

	var best_target: Node2D = null
	var best_distance: float = INF
	for candidate in owner_unit.get_tree().get_nodes_in_group("combat_unit"):
		if candidate == owner_unit or not (candidate is Node2D):
			continue
		if not _is_valid_target(candidate):
			continue
		if not is_hostile(candidate):
			continue
		if not _is_target_allowed_by_order(candidate):
			continue

		var distance: float = owner_unit.global_position.distance_to(candidate.global_position)
		if distance < best_distance and can_see(candidate, detection_radius):
			best_distance = distance
			best_target = candidate

	return best_target


func is_hostile(candidate: Node) -> bool:
	var candidate_faction: String = _read_faction(candidate)
	if candidate_faction == "":
		return false
	if candidate_faction == faction:
		return false
	return hostile_factions.has(candidate_faction)


func can_see(target: Node2D, max_distance: float = -1.0) -> bool:
	if owner_unit == null or target == null:
		return false

	var distance: float = owner_unit.global_position.distance_to(target.global_position)
	if max_distance >= 0.0 and distance > max_distance:
		return false

	var world: World2D = owner_unit.get_world_2d()
	if world == null:
		return true

	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(owner_unit.global_position, target.global_position)
	query.exclude = _get_line_of_sight_excludes()
	var result: Dictionary = world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true

	return result.get("collider") == target


func _act_against_visible_target(target: Node2D) -> void:
	if order_type == OrderType.HOLD:
		if not _is_target_allowed_by_order(target):
			_set_current_target(null, 0.0)
			_follow_anchor_or_idle()
			return
		if _should_return_to_hold_anchor():
			state = AiState.MOVING_TO_ORDER
			_move_toward(order_position, follow_speed)
			_aim_at(target)
			return
		state = AiState.ATTACKING
		_stop()
		if owner_unit.global_position.distance_to(target.global_position) <= attack_range and reaction_remaining <= 0.0:
			_fire_at(target)
		else:
			_aim_at(target)
		return

	var follow_destination = _get_combat_follow_destination()
	if order_type != OrderType.ATTACK and order_type != OrderType.HOLD and follow_destination != null:
		state = AiState.FOLLOWING
		_move_toward(follow_destination, follow_speed)
		_aim_at(target)
		return

	var gun = _get_gun()
	if gun != null and gun.get("ammo_in_magazine") != null and int(gun.get("ammo_in_magazine")) <= 0:
		if gun.has_method("start_reload"):
			gun.start_reload()

	if _should_take_cover() or _should_reload_in_cover():
		state = AiState.TAKING_COVER
		if cover_position == Vector2.ZERO or cover_reuse_remaining <= 0.0:
			cover_position = _find_cover_position(target)
			cover_reuse_remaining = cover_reuse_seconds
		_move_toward(cover_position, chase_speed)
		if owner_unit.global_position.distance_to(cover_position) <= 18.0:
			if _is_reloading():
				state = AiState.RELOADING_IN_COVER
			else:
				state = AiState.IN_COVER
			_stop()
		if not _is_reloading() and reaction_remaining <= 0.0 and owner_unit.global_position.distance_to(target.global_position) <= attack_range:
			state = AiState.PEEKING
			_fire_at(target)
		return

	var distance: float = owner_unit.global_position.distance_to(target.global_position)
	if distance <= attack_range:
		if _should_hold_distance(distance, target):
			state = AiState.CHASING
			_move_toward(_get_hold_distance_position(target), chase_speed * 0.75)
			_aim_at(target)
			return
		state = AiState.ATTACKING
		if _should_stop_to_improve_aim():
			_stop()
		if reaction_remaining <= 0.0:
			_fire_at(target)
		else:
			_aim_at(target)
		return

	state = AiState.CHASING
	_move_toward(target.global_position, chase_speed)
	_aim_at(target)


func _chase_position(destination: Vector2) -> void:
	var follow_destination = _get_combat_follow_destination()
	if order_type != OrderType.ATTACK and order_type != OrderType.HOLD and follow_destination != null:
		state = AiState.FOLLOWING
		_move_toward(follow_destination, follow_speed)
		return

	state = AiState.CHASING
	if owner_unit.global_position.distance_to(destination) <= 18.0:
		current_target = null
		last_seen_position = Vector2.ZERO
		has_last_seen_position = false
		_follow_anchor_or_idle()
		return
	_move_toward(destination, chase_speed)


func _follow_anchor_or_idle() -> void:
	if order_type == OrderType.HOLD:
		if _should_return_to_hold_anchor():
			state = AiState.MOVING_TO_ORDER
			_move_toward(order_position, follow_speed)
			return
		state = AiState.HOLDING
		_stop()
		return

	if follow_target != null and is_instance_valid(follow_target):
		var follow_destination: Vector2 = _get_follow_destination()
		var distance: float = owner_unit.global_position.distance_to(follow_destination)
		if distance > 18.0:
			state = AiState.FOLLOWING
			_move_toward(follow_destination, follow_speed)
			return

	state = AiState.IDLE
	_stop()


func _get_combat_follow_destination():
	if follow_target == null or not is_instance_valid(follow_target):
		return null
	if owner_unit.global_position.distance_to(follow_target.global_position) <= combat_follow_leash:
		return null
	return _get_follow_destination()


func _get_follow_destination() -> Vector2:
	var away: Vector2 = owner_unit.global_position - follow_target.global_position
	if away.length() <= 0.01:
		away = Vector2.RIGHT
	return follow_target.global_position + away.normalized() * desired_follow_distance


func _move_toward(destination: Vector2, speed: float) -> void:
	if order_type == OrderType.HOLD:
		destination = _constrain_to_hold_area(destination)
	var waypoint := _get_navigation_waypoint(destination)
	var offset: Vector2 = waypoint - owner_unit.global_position
	if offset.length() <= 8.0:
		_stop()
		return

	var direction: Vector2 = _apply_spacing(offset.normalized())
	owner_unit.velocity = direction * speed
	if owner_unit.has_method("move_and_slide"):
		owner_unit.move_and_slide()
	if owner_unit.has_method("set_facing_direction"):
		owner_unit.set_facing_direction(direction)
	else:
		owner_unit.set("facing", direction)


func _get_navigation_waypoint(destination: Vector2) -> Vector2:
	if navigation == null or not navigation.has_method("find_path"):
		return destination
	var path: PackedVector2Array = navigation.find_path(owner_unit.global_position, destination)
	if path.is_empty():
		return destination
	return path[0]


func _stop() -> void:
	if owner_unit != null:
		owner_unit.velocity = Vector2.ZERO


func _fire_at(target: Node2D) -> void:
	var direction: Vector2 = _aim_at(target)
	var melee_weapon = _get_melee_weapon()
	if melee_weapon != null and melee_weapon.has_method("try_swing"):
		var melee_range := float(melee_weapon.get("range"))
		if owner_unit.global_position.distance_to(target.global_position) <= melee_range:
			if melee_weapon.try_swing(owner_unit, direction):
				aim_confidence = max(0.0, aim_confidence - 0.08)
				return

	var gun = _get_gun()
	if gun != null and gun.has_method("try_fire"):
		if gun.try_fire(owner_unit, direction):
			aim_confidence = max(0.0, aim_confidence - 0.12)


func _aim_at(target: Node2D) -> Vector2:
	var direction: Vector2 = target.global_position - owner_unit.global_position
	if direction.length() <= 0.0:
		return Vector2.ZERO

	direction = direction.normalized()
	if owner_unit.has_method("set_facing_direction"):
		owner_unit.set_facing_direction(direction)
	else:
		owner_unit.set("facing", direction)
	return direction


func _should_take_cover() -> bool:
	var health = owner_unit.get("health")
	var low_health: bool = health != null and health.has_method("get_health_fraction") and health.get_health_fraction() <= cover_health_fraction
	return low_health or suppression_remaining >= suppression_cover_threshold


func _find_cover_position(target: Node2D) -> Vector2:
	var navigation_cover: Variant = _find_navigation_cover_position(target)
	if navigation_cover != null:
		return navigation_cover

	var best_position: Vector2 = owner_unit.global_position
	var best_score: float = -INF
	for radius in _get_cover_radii():
		for direction in _get_cover_directions():
			var candidate: Vector2 = owner_unit.global_position + direction.normalized() * float(radius)
			if _is_cover_candidate_blocked(candidate) or _is_cover_candidate_occupied(candidate):
				continue
			var score: float = _score_cover_candidate(candidate, target)
			if score > best_score:
				best_score = score
				best_position = candidate
	if best_score == -INF:
		var away: Vector2 = owner_unit.global_position - target.global_position
		if away.length() <= 0.01:
			away = Vector2.RIGHT
		return _constrain_to_hold_area(owner_unit.global_position + away.normalized() * cover_search_radius)
	return _constrain_to_hold_area(best_position)


func _find_navigation_cover_position(target: Node2D):
	if navigation == null or not navigation.has_method("find_cover"):
		return null
	var cover: Dictionary = navigation.find_cover(owner_unit.global_position, target.global_position, cover_search_radius, faction)
	if cover.is_empty() or not cover.has("position"):
		return null
	var position: Vector2 = cover.get("position", owner_unit.global_position)
	position = _constrain_to_hold_area(position)
	if _is_cover_candidate_occupied(position):
		return null
	return position


func _get_cover_directions() -> Array:
	return [
		Vector2.RIGHT,
		Vector2(0.707, 0.707),
		Vector2.DOWN,
		Vector2(-0.707, 0.707),
		Vector2.LEFT,
		Vector2(-0.707, -0.707),
		Vector2.UP,
		Vector2(0.707, -0.707),
	]


func _get_cover_radii() -> Array:
	var radius: float = max(1.0, cover_search_radius)
	return [radius * 0.5, radius * 0.75, radius]


func _alert_nearby_allies(target: Node2D, confidence: float = 1.0) -> void:
	if owner_unit == null or owner_unit.get_tree() == null:
		return

	for controller in owner_unit.get_tree().get_nodes_in_group("combat_ai"):
		if controller == self or not controller.has_method("receive_shared_target"):
			continue
		controller.receive_shared_target(target, owner_unit, confidence)


func _apply_spacing(direction: Vector2) -> Vector2:
	if owner_unit == null or owner_unit.get_tree() == null or preferred_spacing <= 0.0:
		return direction

	var separation: Vector2 = Vector2.ZERO
	for ally in owner_unit.get_tree().get_nodes_in_group("combat_unit"):
		if ally == owner_unit or not (ally is Node2D):
			continue
		if not _is_same_squad_or_faction(ally):
			continue
		var distance: float = owner_unit.global_position.distance_to(ally.global_position)
		if distance <= 0.01 or distance >= preferred_spacing:
			continue
		separation += (owner_unit.global_position - ally.global_position).normalized() * (1.0 - distance / preferred_spacing)

	if separation.length() <= 0.01:
		return direction
	return (direction + separation).normalized()


func _has_line_blocker(from_position: Vector2, target: Node2D) -> bool:
	if owner_unit == null:
		return false

	var world: World2D = owner_unit.get_world_2d()
	if world == null:
		return false

	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from_position, target.global_position)
	query.exclude = [_collision_rid(owner_unit), _collision_rid(target)]
	var result: Dictionary = world.direct_space_state.intersect_ray(query)
	return not result.is_empty()


func _score_cover_candidate(candidate: Vector2, target: Node2D) -> float:
	var score: float = 0.0
	if _has_line_blocker(candidate, target):
		score += 120.0
	if not _has_line_blocker(candidate, target) and not _is_reloading():
		score += 20.0
	score += min(candidate.distance_to(target.global_position) * 0.08, 60.0)
	score -= owner_unit.global_position.distance_to(candidate) * 0.18
	if follow_target != null and is_instance_valid(follow_target):
		score -= candidate.distance_to(follow_target.global_position) * 0.04
	return score


func _is_cover_candidate_blocked(candidate: Vector2) -> bool:
	var world: World2D = owner_unit.get_world_2d()
	if world == null:
		return false
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 12.0
	query.shape = circle
	query.transform = Transform2D(0.0, candidate)
	query.exclude = [_collision_rid(owner_unit)]
	return not world.direct_space_state.intersect_shape(query, 1).is_empty()


func _is_cover_candidate_occupied(candidate: Vector2) -> bool:
	if owner_unit == null or owner_unit.get_tree() == null:
		return false
	for ally in owner_unit.get_tree().get_nodes_in_group("combat_unit"):
		if ally == owner_unit or not (ally is Node2D):
			continue
		if not _is_same_squad_or_faction(ally):
			continue
		if candidate.distance_to(ally.global_position) < preferred_spacing:
			return true
	return false


func _is_valid_target(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not (target is Node2D):
		return false
	return not _is_dead(target)


func _is_target_allowed_by_order(target: Node2D) -> bool:
	if order_type != OrderType.HOLD:
		return true
	return target.global_position.distance_to(order_position) <= order_hold_radius


func _constrain_to_hold_area(destination: Vector2) -> Vector2:
	if order_type != OrderType.HOLD:
		return destination
	var offset := destination - order_position
	if offset.length() <= order_hold_radius:
		return destination
	return order_position + offset.normalized() * order_hold_radius


func _should_return_to_hold_anchor() -> bool:
	var distance := owner_unit.global_position.distance_to(order_position)
	if hold_anchor_reached:
		if distance > HOLD_REPOSITION_DISTANCE:
			hold_anchor_reached = false
	elif distance <= HOLD_ARRIVAL_DISTANCE:
		hold_anchor_reached = true
	return not hold_anchor_reached


func _is_line_of_sight_transparent(collider: Node) -> bool:
	return collider.is_in_group("combat_unit") and not is_hostile(collider)


func _get_line_of_sight_excludes() -> Array:
	var excluded_rids: Array = [_collision_rid(owner_unit)]
	if owner_unit == null or owner_unit.get_tree() == null:
		return excluded_rids
	for unit in owner_unit.get_tree().get_nodes_in_group("combat_unit"):
		var unit_node: Node = unit as Node
		if unit_node == null or unit_node == owner_unit:
			continue
		if _is_line_of_sight_transparent(unit_node):
			excluded_rids.append(_collision_rid(unit_node))
	return excluded_rids


func _is_dead(candidate: Node) -> bool:
	var candidate_health = candidate.get("health")
	if candidate_health != null:
		var current_health = candidate_health.get("current_health")
		if current_health != null and int(current_health) <= 0:
			return true
	return false


func _read_owner_faction() -> String:
	if owner_unit == null:
		return faction
	return _read_faction(owner_unit)


func _refresh_dynamic_weapon_ranges() -> void:
	if _uses_weapon_attack_range:
		attack_range = _get_owner_weapon_range("effective_range", attack_range)
	if _uses_weapon_preferred_range:
		preferred_range = _get_owner_weapon_range("preferred_range", preferred_range)


func _get_owner_weapon_range(property_name: String, fallback: float) -> float:
	if owner_unit == null:
		return fallback
	var gun = owner_unit.get("gun")
	if gun != null:
		var value = gun.get(property_name)
		if value != null:
			return float(value)
	var melee_weapon = owner_unit.get("melee_weapon")
	if melee_weapon != null:
		var melee_range = melee_weapon.get("range")
		if melee_range != null:
			if property_name == "preferred_range":
				return max(12.0, float(melee_range) * 0.72)
			return float(melee_range)
	return fallback


func _get_gun():
	if owner_unit == null:
		return null
	return owner_unit.get("gun")


func _get_melee_weapon():
	if owner_unit == null:
		return null
	return owner_unit.get("melee_weapon")


func _is_reloading() -> bool:
	var gun = _get_gun()
	return gun != null and gun.has_method("is_reloading") and gun.is_reloading()


func _should_reload_in_cover() -> bool:
	var gun = _get_gun()
	if gun == null:
		return false
	if gun.has_method("is_reloading") and gun.is_reloading():
		return true
	if gun.has_method("get_ammo_fraction") and gun.get_ammo_fraction() <= 0.25 and int(gun.get("ammo_in_magazine")) < int(gun.get("magazine_size")):
		return true
	return false


func _should_stop_to_improve_aim() -> bool:
	var gun = _get_gun()
	if gun == null:
		return false
	var effective_spread: float = 0.0
	if gun.has_method("get_effective_spread_degrees"):
		effective_spread = gun.get_effective_spread_degrees(owner_unit)
	return aim_confidence < 0.75 or effective_spread > 7.0


func _should_hold_distance(distance: float, target: Node2D) -> bool:
	if role == "assault":
		return false
	var gun = _get_gun()
	var weapon_type: String = ""
	if gun != null and gun.get("weapon_type") != null:
		weapon_type = str(gun.get("weapon_type"))
	if role == "support" or role == "guard" or weapon_type == "rifle":
		return distance < preferred_range - hold_distance_tolerance and can_see(target, attack_range)
	return false


func _get_hold_distance_position(target: Node2D) -> Vector2:
	var away: Vector2 = owner_unit.global_position - target.global_position
	if away.length() <= 0.01:
		away = Vector2.RIGHT
	return owner_unit.global_position + away.normalized() * 90.0


func _set_current_target(target: Node2D, confidence: float) -> void:
	if target == current_target:
		current_target_confidence = max(current_target_confidence, confidence)
		return
	current_target = target
	current_target_confidence = confidence
	time_since_seen_target = 0.0
	if target != null:
		last_seen_position = target.global_position
		has_last_seen_position = true
		var gun = _get_gun()
		var weapon_aim_time: float = 0.0
		if gun != null and gun.get("aim_time") != null:
			weapon_aim_time = float(gun.get("aim_time"))
		reaction_remaining = reaction_time
		if reaction_remaining > 0.0:
			reaction_remaining += weapon_aim_time
	else:
		last_seen_position = Vector2.ZERO
		has_last_seen_position = false
		reaction_remaining = 0.0


func _read_faction(candidate: Node) -> String:
	if candidate == null:
		return ""
	if candidate.has_method("get_faction"):
		return str(candidate.get_faction())
	var value = candidate.get("faction")
	if value != null:
		return str(value)
	return ""


func _is_same_squad_or_faction(candidate: Node) -> bool:
	if candidate == null:
		return false
	var candidate_faction: String = _read_faction(candidate)
	if candidate_faction != "" and candidate_faction != faction:
		return false
	if squad_id == "":
		return candidate_faction == faction
	var candidate_ai = candidate.get("combat_ai")
	if candidate_ai != null and candidate_ai.get("squad_id") != null:
		return str(candidate_ai.get("squad_id")) == squad_id
	if candidate.has_method("get_squad_id"):
		return str(candidate.get_squad_id()) == squad_id
	return false


func _read_string_array(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func _collision_rid(node: Node) -> RID:
	if node is CollisionObject2D:
		return node.get_rid()
	return RID()
