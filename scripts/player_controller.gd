extends CharacterBody2D
class_name PlayerController

signal health_changed(current_health: int, max_health: int)
signal died

const HEALTH_COMPONENT_SCENE_PATH := "res://scenes/combat/HealthComponent.tscn"
const GUN_COMPONENT_SCENE_PATH := "res://scenes/combat/GunComponent.tscn"
const MELEE_COMPONENT_SCENE_PATH := "res://scenes/combat/MeleeComponent.tscn"
const CHARACTER_VISUAL_PATH := "res://scripts/visuals/character_visual_2d.gd"

@export var speed: float = 280.0
@export var max_health: int = 100

var faction := "player"
var facing: Vector2 = Vector2.DOWN
var aim_direction: Vector2 = Vector2.DOWN
var controls_enabled := true
var health
var gun
var melee_weapon
var visual
var _fire_flash_remaining := 0.0

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("player")
	add_to_group("combat_unit")
	z_index = 20

	_create_visual()

	health = _instantiate_component_scene(HEALTH_COMPONENT_SCENE_PATH, ["setup", "get_health_fraction"])
	if health == null:
		return
	add_child(health)
	health.setup(max_health)
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)

	gun = _instantiate_component_scene(GUN_COMPONENT_SCENE_PATH, ["setup", "try_fire", "is_reloading"])
	if gun == null:
		return
	add_child(gun)

	melee_weapon = _instantiate_component_scene(MELEE_COMPONENT_SCENE_PATH, ["setup", "try_swing", "is_swinging"])
	if melee_weapon == null:
		return
	add_child(melee_weapon)
	melee_weapon.setup({
		"name": "Baseball Bat",
		"weapon_type": "bat",
		"damage": 22,
		"range": 76,
		"arc_degrees": 105,
		"swing_cooldown": 0.55,
		"swing_duration": 0.16,
		"knockback": 120,
	})
	_update_visual()

func _physics_process(delta: float) -> void:
	_fire_flash_remaining = max(0.0, _fire_flash_remaining - delta)
	if not controls_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_visual()
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length() > 0.0:
		facing = input_vector.normalized()

	_update_aim_direction()
	velocity = input_vector * speed
	move_and_slide()
	_update_visual()


func _unhandled_input(event: InputEvent) -> void:
	if controls_enabled and event.is_action_pressed("fire"):
		fire_weapon()
	elif controls_enabled and event.is_action_pressed("reload"):
		reload_weapon()
	elif controls_enabled and event.is_action_pressed("melee"):
		swing_melee()


func fire_weapon() -> void:
	if gun != null:
		_update_aim_direction()
		if gun.try_fire(self, aim_direction):
			_fire_flash_remaining = 0.12
			_update_visual()


func reload_weapon() -> bool:
	if gun != null and gun.has_method("start_reload"):
		return gun.start_reload()
	return false


func swing_melee() -> bool:
	if melee_weapon == null or not melee_weapon.has_method("try_swing"):
		return false
	_update_aim_direction()
	return melee_weapon.try_swing(self, aim_direction)


func apply_damage(amount: int) -> void:
	if health != null:
		health.apply_damage(amount)


func set_health_values(current_health: int, current_max_health: int) -> void:
	max_health = max(1, current_max_health)
	if health == null:
		return
	if health.has_method("setup_values"):
		health.setup_values(current_health, max_health)
	else:
		health.setup(max_health)


func get_faction() -> String:
	return faction


func _instantiate_component_scene(scene_path: String, required_methods: Array = []) -> Node:
	var scene = load(scene_path)
	if scene == null:
		push_error("Failed to load component scene: %s" % scene_path)
		return null

	var component = scene.instantiate()
	if component == null:
		push_error("Failed to instantiate component scene: %s" % scene_path)
		return null
	for method_name in required_methods:
		if not component.has_method(str(method_name)):
			push_error("Component scene %s instantiated as %s without required method %s" % [
				scene_path,
				component.get_class(),
				str(method_name),
			])
			component.free()
			return null
	return component


func _on_health_changed(current_health: int, current_max_health: int) -> void:
	health_changed.emit(current_health, current_max_health)
	_update_visual()


func _on_died() -> void:
	died.emit()
	controls_enabled = false
	_update_visual()


func _update_aim_direction() -> void:
	var mouse_direction := get_global_mouse_position() - global_position
	if mouse_direction.length() > 0.0:
		aim_direction = mouse_direction.normalized()


func _update_visual() -> void:
	if visual == null:
		return
	var health_fraction := 1.0
	var is_dead := false
	if health != null:
		health_fraction = health.get_health_fraction()
		var current_health = health.get("current_health")
		is_dead = current_health != null and int(current_health) <= 0
	visual.set_visual_state(facing, aim_direction, velocity, health_fraction, is_dead, _fire_flash_remaining > 0.0)


func _create_visual() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var visual_script = load(CHARACTER_VISUAL_PATH)
	if visual_script == null:
		return
	visual = visual_script.new()
	visual.setup("player", Color(0.08, 0.74, 0.76), Color(0.20, 0.88, 0.58))
	add_child(visual)
