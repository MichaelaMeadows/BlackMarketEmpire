extends Node
class_name CombatAiController

enum AiState {
	IDLE,
	FOLLOWING,
	CHASING,
	ATTACKING,
	TAKING_COVER,
}

const STATE_NAMES := {
	AiState.IDLE: "IDLE",
	AiState.FOLLOWING: "FOLLOWING",
	AiState.CHASING: "CHASING",
	AiState.ATTACKING: "ATTACKING",
	AiState.TAKING_COVER: "TAKING_COVER",
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

var owner_unit: CharacterBody2D
var faction := "neutral"
var hostile_factions: Array = []
var current_target: Node2D
var follow_target: Node2D
var last_seen_position := Vector2.ZERO
var cover_position := Vector2.ZERO
var state := AiState.IDLE


func setup(new_owner: CharacterBody2D, config: Dictionary = {}) -> void:
	owner_unit = new_owner
	enabled = bool(config.get("enabled", enabled))
	faction = str(config.get("faction", _read_owner_faction()))
	hostile_factions = _read_string_array(config.get("hostile_factions", hostile_factions))
	detection_radius = float(config.get("detection_radius", detection_radius))
	attack_range = float(config.get("attack_range", attack_range))
	preferred_range = float(config.get("preferred_range", preferred_range))
	chase_speed = float(config.get("chase_speed", chase_speed))
	follow_speed = float(config.get("follow_speed", follow_speed))
	cover_search_radius = float(config.get("cover_search_radius", cover_search_radius))
	cover_health_fraction = float(config.get("cover_health_fraction", cover_health_fraction))
	desired_follow_distance = float(config.get("desired_follow_distance", desired_follow_distance))
	combat_follow_leash = float(config.get("combat_follow_leash", combat_follow_leash))


func set_follow_target(target: Node2D, distance: float = -1.0, leash: float = -1.0) -> void:
	follow_target = target
	if distance >= 0.0:
		desired_follow_distance = distance
	if leash >= 0.0:
		combat_follow_leash = leash


func clear_follow_target() -> void:
	follow_target = null


func set_hostile_factions(new_hostile_factions: Array) -> void:
	hostile_factions = _read_string_array(new_hostile_factions)


func notify_attacked_by(attacker: Node) -> void:
	if not (attacker is Node2D):
		return

	var attacker_faction := _read_faction(attacker)
	if attacker_faction != "" and attacker_faction != faction and not hostile_factions.has(attacker_faction):
		hostile_factions.append(attacker_faction)

	if is_hostile(attacker):
		current_target = attacker
		last_seen_position = attacker.global_position


func get_state_name() -> String:
	return str(STATE_NAMES.get(state, "UNKNOWN"))


func _physics_process(delta: float) -> void:
	tick_ai(delta)


func tick_ai(_delta: float) -> void:
	if not enabled or owner_unit == null or not is_instance_valid(owner_unit):
		return
	if _is_dead(owner_unit):
		_stop()
		return

	if not _is_valid_target(current_target):
		current_target = find_visible_hostile()

	if _is_valid_target(current_target) and can_see(current_target, detection_radius):
		last_seen_position = current_target.global_position
		cover_position = Vector2.ZERO
		_act_against_visible_target(current_target)
		return

	if _is_valid_target(current_target) and last_seen_position != Vector2.ZERO:
		_chase_position(last_seen_position)
		return

	_follow_anchor_or_idle()


func find_visible_hostile() -> Node2D:
	if owner_unit == null or owner_unit.get_tree() == null:
		return null

	var best_target: Node2D = null
	var best_distance := INF
	for candidate in owner_unit.get_tree().get_nodes_in_group("combat_unit"):
		if candidate == owner_unit or not (candidate is Node2D):
			continue
		if not _is_valid_target(candidate):
			continue
		if not is_hostile(candidate):
			continue

		var distance := owner_unit.global_position.distance_to(candidate.global_position)
		if distance < best_distance and can_see(candidate, detection_radius):
			best_distance = distance
			best_target = candidate

	return best_target


func is_hostile(candidate: Node) -> bool:
	var candidate_faction := _read_faction(candidate)
	if candidate_faction == "":
		return false
	if candidate_faction == faction:
		return false
	return hostile_factions.has(candidate_faction)


func can_see(target: Node2D, max_distance: float = -1.0) -> bool:
	if owner_unit == null or target == null:
		return false

	var distance := owner_unit.global_position.distance_to(target.global_position)
	if max_distance >= 0.0 and distance > max_distance:
		return false

	var world := owner_unit.get_world_2d()
	if world == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(owner_unit.global_position, target.global_position)
	query.exclude = [_collision_rid(owner_unit)]
	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true

	return result.get("collider") == target


func _act_against_visible_target(target: Node2D) -> void:
	var follow_destination = _get_combat_follow_destination()
	if follow_destination != null:
		state = AiState.FOLLOWING
		_move_toward(follow_destination, follow_speed)
		_aim_at(target)
		return

	if _should_take_cover():
		state = AiState.TAKING_COVER
		if cover_position == Vector2.ZERO:
			cover_position = _find_cover_position(target)
		_move_toward(cover_position, chase_speed)
		if owner_unit.global_position.distance_to(target.global_position) <= attack_range:
			_fire_at(target)
		return

	var distance := owner_unit.global_position.distance_to(target.global_position)
	if distance <= attack_range:
		state = AiState.ATTACKING
		_stop()
		_fire_at(target)
		return

	state = AiState.CHASING
	_move_toward(target.global_position, chase_speed)
	_aim_at(target)


func _chase_position(destination: Vector2) -> void:
	var follow_destination = _get_combat_follow_destination()
	if follow_destination != null:
		state = AiState.FOLLOWING
		_move_toward(follow_destination, follow_speed)
		return

	state = AiState.CHASING
	if owner_unit.global_position.distance_to(destination) <= 18.0:
		current_target = null
		last_seen_position = Vector2.ZERO
		_follow_anchor_or_idle()
		return
	_move_toward(destination, chase_speed)


func _follow_anchor_or_idle() -> void:
	if follow_target != null and is_instance_valid(follow_target):
		var follow_destination := _get_follow_destination()
		var distance := owner_unit.global_position.distance_to(follow_destination)
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
	var away := owner_unit.global_position - follow_target.global_position
	if away.length() <= 0.01:
		away = Vector2.RIGHT
	return follow_target.global_position + away.normalized() * desired_follow_distance


func _move_toward(destination: Vector2, speed: float) -> void:
	var offset := destination - owner_unit.global_position
	if offset.length() <= 8.0:
		_stop()
		return

	var direction := offset.normalized()
	owner_unit.velocity = direction * speed
	if owner_unit.has_method("move_and_slide"):
		owner_unit.move_and_slide()
	if owner_unit.has_method("set_facing_direction"):
		owner_unit.set_facing_direction(direction)
	else:
		owner_unit.set("facing", direction)


func _stop() -> void:
	if owner_unit != null:
		owner_unit.velocity = Vector2.ZERO


func _fire_at(target: Node2D) -> void:
	var direction := _aim_at(target)
	var gun = owner_unit.get("gun")
	if gun != null and gun.has_method("try_fire"):
		gun.try_fire(owner_unit, direction)


func _aim_at(target: Node2D) -> Vector2:
	var direction := target.global_position - owner_unit.global_position
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
	if health == null or not health.has_method("get_health_fraction"):
		return false
	return health.get_health_fraction() <= cover_health_fraction


func _find_cover_position(target: Node2D) -> Vector2:
	var away := owner_unit.global_position - target.global_position
	if away.length() <= 0.01:
		away = Vector2.RIGHT
	away = away.normalized()

	var perpendicular := Vector2(-away.y, away.x)
	var candidates := [
		owner_unit.global_position + away * cover_search_radius,
		owner_unit.global_position + (away + perpendicular * 0.7).normalized() * cover_search_radius,
		owner_unit.global_position + (away - perpendicular * 0.7).normalized() * cover_search_radius,
		owner_unit.global_position + perpendicular * cover_search_radius,
		owner_unit.global_position - perpendicular * cover_search_radius,
	]

	for candidate in candidates:
		if _has_line_blocker(candidate, target):
			return candidate

	return candidates[0]


func _has_line_blocker(from_position: Vector2, target: Node2D) -> bool:
	if owner_unit == null:
		return false

	var world := owner_unit.get_world_2d()
	if world == null:
		return false

	var query := PhysicsRayQueryParameters2D.create(from_position, target.global_position)
	query.exclude = [_collision_rid(owner_unit), _collision_rid(target)]
	var result := world.direct_space_state.intersect_ray(query)
	return not result.is_empty()


func _is_valid_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not (target is Node2D):
		return false
	return not _is_dead(target)


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


func _read_faction(candidate: Node) -> String:
	if candidate == null:
		return ""
	if candidate.has_method("get_faction"):
		return str(candidate.get_faction())
	var value = candidate.get("faction")
	if value != null:
		return str(value)
	return ""


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
