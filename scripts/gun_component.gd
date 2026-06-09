extends Node

const PROJECTILE_SCENE_PATH := "res://scenes/combat/Projectile.tscn"
const DEFAULT_MOVEMENT_SPREAD_BY_TYPE := {
	"pistol": 5.0,
	"smg": 10.0,
	"rifle": 14.0,
	"shotgun": 7.0,
}

@export var weapon_name := "Basic Pistol"
@export var weapon_type := "pistol"
@export var damage := 20
@export var projectile_speed := 720.0
@export var projectile_lifetime := 1.2
@export var fire_cooldown := 0.28
@export var muzzle_distance := 22.0
@export var effective_range := 420.0
@export var preferred_range := 300.0
@export_range(0.0, 1.0) var accuracy := 0.82
@export var base_spread_degrees := 8.0
@export var movement_spread_degrees := -1.0
@export var max_movement_penalty_speed := 220.0
@export var projectiles_per_shot := 1
@export var projectile_spread_degrees := 0.0
@export var magazine_size := 12
@export var ammo_in_magazine := 12
@export var reload_time := 1.4
@export var burst_count := 1
@export var burst_interval := 0.08
@export var recoil_per_shot := 1.4
@export var recoil_recovery_per_second := 5.0
@export var max_recoil_spread_degrees := 10.0
@export var aim_time := 0.18
@export var suppression := 0.0

var cooldown_remaining := 0.0
var reload_remaining := 0.0
var current_recoil_spread_degrees := 0.0
var last_fired_directions: Array = []
var _rng := RandomNumberGenerator.new()
var _burst_shots_remaining := 0
var _burst_timer := 0.0
var _burst_owner: Node2D
var _burst_direction := Vector2.ZERO

func _process(delta: float) -> void:
	cooldown_remaining = max(0.0, cooldown_remaining - delta)
	current_recoil_spread_degrees = max(0.0, current_recoil_spread_degrees - recoil_recovery_per_second * delta)

	if is_reloading():
		reload_remaining = max(0.0, reload_remaining - delta)
		if reload_remaining <= 0.0:
			ammo_in_magazine = magazine_size

	if _burst_shots_remaining > 0:
		_burst_timer -= delta
		while _burst_shots_remaining > 0 and _burst_timer <= 0.0:
			if _burst_owner == null or not is_instance_valid(_burst_owner) or ammo_in_magazine <= 0:
				_burst_shots_remaining = 0
				break
			_fire_single(_burst_owner, _burst_direction, true)
			_burst_shots_remaining -= 1
			_burst_timer += burst_interval


func setup(weapon_data: Dictionary) -> void:
	weapon_name = str(weapon_data.get("name", weapon_name))
	weapon_type = str(weapon_data.get("weapon_type", weapon_type))
	damage = int(weapon_data.get("damage", damage))
	projectile_speed = float(weapon_data.get("projectile_speed", projectile_speed))
	projectile_lifetime = float(weapon_data.get("projectile_lifetime", projectile_lifetime))
	fire_cooldown = float(weapon_data.get("fire_cooldown", fire_cooldown))
	muzzle_distance = float(weapon_data.get("muzzle_distance", muzzle_distance))
	effective_range = max(1.0, float(weapon_data.get("effective_range", effective_range)))
	preferred_range = max(1.0, float(weapon_data.get("preferred_range", preferred_range)))
	accuracy = clampf(float(weapon_data.get("accuracy", accuracy)), 0.0, 1.0)
	base_spread_degrees = max(0.0, float(weapon_data.get("base_spread_degrees", base_spread_degrees)))
	movement_spread_degrees = float(weapon_data.get("movement_spread_degrees", movement_spread_degrees))
	max_movement_penalty_speed = max(1.0, float(weapon_data.get("max_movement_penalty_speed", max_movement_penalty_speed)))
	projectiles_per_shot = max(1, int(weapon_data.get("projectiles_per_shot", projectiles_per_shot)))
	projectile_spread_degrees = max(0.0, float(weapon_data.get("projectile_spread_degrees", projectile_spread_degrees)))
	magazine_size = max(1, int(weapon_data.get("magazine_size", magazine_size)))
	ammo_in_magazine = clampi(int(weapon_data.get("ammo_in_magazine", magazine_size)), 0, magazine_size)
	reload_time = max(0.01, float(weapon_data.get("reload_time", reload_time)))
	burst_count = max(1, int(weapon_data.get("burst_count", burst_count)))
	burst_interval = max(0.01, float(weapon_data.get("burst_interval", burst_interval)))
	recoil_per_shot = max(0.0, float(weapon_data.get("recoil_per_shot", recoil_per_shot)))
	recoil_recovery_per_second = max(0.0, float(weapon_data.get("recoil_recovery_per_second", recoil_recovery_per_second)))
	max_recoil_spread_degrees = max(0.0, float(weapon_data.get("max_recoil_spread_degrees", max_recoil_spread_degrees)))
	aim_time = max(0.0, float(weapon_data.get("aim_time", aim_time)))
	suppression = max(0.0, float(weapon_data.get("suppression", suppression)))
	cooldown_remaining = 0.0
	reload_remaining = 0.0
	current_recoil_spread_degrees = 0.0
	last_fired_directions = []
	_burst_shots_remaining = 0


func try_fire(owner: Node2D, direction: Vector2) -> bool:
	if cooldown_remaining > 0.0 or is_reloading() or ammo_in_magazine <= 0 or direction.length() <= 0.0:
		return false

	last_fired_directions = []
	_fire_single(owner, direction, false)
	if burst_count > 1 and ammo_in_magazine > 0:
		_burst_owner = owner
		_burst_direction = direction.normalized()
		_burst_shots_remaining = min(burst_count - 1, ammo_in_magazine)
		_burst_timer = burst_interval
	cooldown_remaining = fire_cooldown
	return true


func start_reload() -> bool:
	if is_reloading() or ammo_in_magazine >= magazine_size:
		return false
	reload_remaining = reload_time
	_burst_shots_remaining = 0
	return true


func is_reloading() -> bool:
	return reload_remaining > 0.0


func get_ammo_fraction() -> float:
	if magazine_size <= 0:
		return 0.0
	return float(ammo_in_magazine) / float(magazine_size)


func set_seed(seed: int) -> void:
	_rng.seed = seed


func get_effective_spread_degrees(owner: Node2D) -> float:
	var spread := base_spread_degrees * (1.0 - clampf(accuracy, 0.0, 1.0))
	var movement_factor := _get_movement_factor(owner)
	spread += _get_movement_spread_degrees() * movement_factor
	spread += current_recoil_spread_degrees
	return max(0.0, spread)


func calculate_shot_directions(owner: Node2D, direction: Vector2) -> Array:
	var normalized_direction := direction.normalized()
	var spread := get_effective_spread_degrees(owner)
	var directions: Array = []
	var count: int = max(1, projectiles_per_shot)
	for index in range(count):
		var pellet_offset := 0.0
		if count > 1 and projectile_spread_degrees > 0.0:
			var step := projectile_spread_degrees / float(max(1, count - 1))
			pellet_offset = -projectile_spread_degrees * 0.5 + step * float(index)
		var random_offset := _rng.randf_range(-spread * 0.5, spread * 0.5)
		directions.append(normalized_direction.rotated(deg_to_rad(pellet_offset + random_offset)).normalized())
	return directions


func _fire_single(owner: Node2D, direction: Vector2, append_to_last: bool) -> void:
	if ammo_in_magazine <= 0:
		return
	var shot_directions := calculate_shot_directions(owner, direction)
	if append_to_last:
		last_fired_directions.append_array(shot_directions)
	else:
		last_fired_directions = shot_directions
	for shot_direction in shot_directions:
		_spawn_projectile(owner, shot_direction)
	ammo_in_magazine = max(0, ammo_in_magazine - 1)
	current_recoil_spread_degrees = min(max_recoil_spread_degrees, current_recoil_spread_degrees + recoil_per_shot)


func _spawn_projectile(owner: Node2D, direction: Vector2) -> void:
	var projectile = _create_projectile()
	if projectile == null:
		return
	var weapon_data := {
		"name": weapon_name,
		"damage": damage,
		"projectile_speed": projectile_speed,
		"projectile_lifetime": projectile_lifetime,
	}
	projectile.setup(owner.global_position + direction.normalized() * muzzle_distance, direction, weapon_data, owner)
	var tree: SceneTree = owner.get_tree()
	if tree == null:
		projectile.free()
		return
	var projectile_parent: Node = tree.current_scene
	if projectile_parent == null:
		projectile_parent = owner.get_parent()
	if projectile_parent == null:
		projectile.free()
		return
	projectile_parent.add_child(projectile)


func _create_projectile() -> Area2D:
	var scene = load(PROJECTILE_SCENE_PATH)
	if scene == null:
		push_error("Failed to load projectile scene: %s" % PROJECTILE_SCENE_PATH)
		return null

	var projectile = scene.instantiate()
	if projectile == null:
		push_error("Failed to instantiate projectile scene: %s" % PROJECTILE_SCENE_PATH)
		return null
	if not projectile.has_method("setup"):
		push_error("Projectile scene %s instantiated as %s without setup method" % [
			PROJECTILE_SCENE_PATH,
			projectile.get_class(),
		])
		projectile.free()
		return null
	return projectile


func _get_movement_factor(owner: Node2D) -> float:
	if owner == null:
		return 0.0
	var velocity_value = owner.get("velocity")
	if velocity_value is Vector2:
		return clampf(velocity_value.length() / max_movement_penalty_speed, 0.0, 1.0)
	return 0.0


func _get_movement_spread_degrees() -> float:
	if movement_spread_degrees >= 0.0:
		return movement_spread_degrees
	return float(DEFAULT_MOVEMENT_SPREAD_BY_TYPE.get(weapon_type, DEFAULT_MOVEMENT_SPREAD_BY_TYPE["pistol"]))
