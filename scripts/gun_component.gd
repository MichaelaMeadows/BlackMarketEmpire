extends Node

const PROJECTILE_SCRIPT := preload("res://scripts/projectile.gd")

@export var weapon_name := "Basic Pistol"
@export var damage := 20
@export var projectile_speed := 720.0
@export var projectile_lifetime := 1.2
@export var fire_cooldown := 0.28
@export var muzzle_distance := 22.0

var cooldown_remaining := 0.0

func _process(delta: float) -> void:
	cooldown_remaining = max(0.0, cooldown_remaining - delta)


func setup(weapon_data: Dictionary) -> void:
	weapon_name = str(weapon_data.get("name", weapon_name))
	damage = int(weapon_data.get("damage", damage))
	projectile_speed = float(weapon_data.get("projectile_speed", projectile_speed))
	projectile_lifetime = float(weapon_data.get("projectile_lifetime", projectile_lifetime))
	fire_cooldown = float(weapon_data.get("fire_cooldown", fire_cooldown))
	muzzle_distance = float(weapon_data.get("muzzle_distance", muzzle_distance))


func try_fire(owner: Node2D, direction: Vector2) -> bool:
	if cooldown_remaining > 0.0 or direction.length() <= 0.0:
		return false

	var projectile = PROJECTILE_SCRIPT.new()
	var weapon_data := {
		"name": weapon_name,
		"damage": damage,
		"projectile_speed": projectile_speed,
		"projectile_lifetime": projectile_lifetime,
	}
	projectile.setup(owner.global_position + direction.normalized() * muzzle_distance, direction, weapon_data, owner)
	var projectile_parent: Node = owner.get_tree().current_scene
	if projectile_parent == null:
		projectile_parent = owner.get_parent()
	projectile_parent.add_child(projectile)
	cooldown_remaining = fire_cooldown
	return true
