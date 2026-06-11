extends CharacterBody2D

signal died(npc: CharacterBody2D)

const CHARACTER_VISUAL_PATH := "res://scripts/visuals/character_visual_2d.gd"
const HEALTH_COMPONENT_SCENE_PATH := "res://scenes/combat/HealthComponent.tscn"
const GUN_COMPONENT_SCENE_PATH := "res://scenes/combat/GunComponent.tscn"
const MELEE_COMPONENT_SCENE_PATH := "res://scenes/combat/MeleeComponent.tscn"
const COMBAT_AI_CONTROLLER_SCENE_PATH := "res://scenes/combat/CombatAiController.tscn"

var npc_name := "NPC"
var npc_role := "neighbor"
var faction := "neutral"
var squad_id := ""
var display_color := Color(0.70, 0.77, 0.82)
var facing := Vector2.DOWN
var health
var gun
var melee_weapon
var combat_ai
var visual
var label: Label
var _fire_flash_remaining := 0.0

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("npc")
	add_to_group("combat_unit")
	z_index = 20

	_create_visual()

	if health == null:
		health = _instantiate_component_scene(HEALTH_COMPONENT_SCENE_PATH, ["setup", "get_health_fraction"])
		if health == null:
			return
		add_child(health)
		health.setup(60)
		health.health_changed.connect(_on_health_changed)
		health.died.connect(_on_died)

	if gun == null:
		gun = _instantiate_component_scene(GUN_COMPONENT_SCENE_PATH, ["setup", "try_fire", "is_reloading"])
		if gun == null:
			return
		add_child(gun)

	_build_label()
	_update_visual()


func _physics_process(delta: float) -> void:
	_fire_flash_remaining = max(0.0, _fire_flash_remaining - delta)
	var fired_recently := false
	if gun != null:
		var cooldown = gun.get("cooldown_remaining")
		var fire_cooldown = gun.get("fire_cooldown")
		fired_recently = cooldown != null and fire_cooldown != null and float(cooldown) > max(0.0, float(fire_cooldown) - 0.14)
	if fired_recently:
		_fire_flash_remaining = 0.10
	_update_visual()


func setup(npc_data: Dictionary) -> void:
	npc_name = str(npc_data.get("name", npc_name))
	npc_role = str(npc_data.get("role", npc_role))
	faction = str(npc_data.get("faction", faction))
	squad_id = str(npc_data.get("squad_id", squad_id))
	display_color = _read_color(npc_data.get("color", []), display_color)
	if visual != null:
		visual.setup(str(npc_data.get("visual_id", "npc_%s" % npc_role)), display_color, Color(0.88, 0.28, 0.22))

	if health == null:
		health = _instantiate_component_scene(HEALTH_COMPONENT_SCENE_PATH, ["setup", "get_health_fraction"])
		if health == null:
			return
		add_child(health)
		health.health_changed.connect(_on_health_changed)
		health.died.connect(_on_died)
	health.setup(int(npc_data.get("health", 60)))

	if gun == null:
		gun = _instantiate_component_scene(GUN_COMPONENT_SCENE_PATH, ["setup", "try_fire", "is_reloading"])
		if gun == null:
			return
		add_child(gun)
	if npc_data.has("weapon"):
		gun.setup(npc_data["weapon"])

	if npc_data.has("melee_weapon"):
		if melee_weapon == null:
			melee_weapon = _instantiate_component_scene(MELEE_COMPONENT_SCENE_PATH, ["setup", "try_swing", "is_swinging"])
			if melee_weapon == null:
				return
			add_child(melee_weapon)
		melee_weapon.setup(npc_data["melee_weapon"])

	if npc_data.has("ai"):
		_ensure_ai_controller(npc_data["ai"])

	if label != null:
		label.text = npc_name
	_update_visual()


func apply_damage(amount: int) -> void:
	if health != null:
		health.apply_damage(amount)


func notify_attacked_by(attacker: Node) -> void:
	if combat_ai != null and combat_ai.has_method("notify_attacked_by"):
		combat_ai.notify_attacked_by(attacker)


func get_faction() -> String:
	return faction


func get_squad_id() -> String:
	return squad_id


func set_facing_direction(direction: Vector2) -> void:
	if direction.length() > 0.0:
		facing = direction.normalized()
		_update_visual()


func _build_label() -> void:
	if label != null:
		return

	label = Label.new()
	label.text = npc_name
	label.position = Vector2(-40.0, -46.0)
	label.size = Vector2(80.0, 22.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(0.82, 0.86, 0.82, 0.58)
	add_child(label)


func _ensure_ai_controller(ai_data: Dictionary) -> void:
	if combat_ai == null:
		combat_ai = _instantiate_component_scene(COMBAT_AI_CONTROLLER_SCENE_PATH, ["setup", "tick_ai"])
		if combat_ai == null:
			return
		add_child(combat_ai)
	if ai_data.has("faction"):
		faction = str(ai_data["faction"])
	if ai_data.has("squad_id"):
		squad_id = str(ai_data["squad_id"])
	combat_ai.setup(self, ai_data)


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


func _on_health_changed(_current_health: int, _max_health: int) -> void:
	_update_visual()


func _on_died() -> void:
	_update_visual()
	died.emit(self)
	queue_free()


func _read_color(value: Variant, fallback: Color) -> Color:
	if value is Array and value.size() >= 3:
		var alpha: float = float(value[3]) if value.size() >= 4 else 1.0
		return Color(float(value[0]), float(value[1]), float(value[2]), alpha)
	return fallback


func _create_visual() -> void:
	if visual != null or DisplayServer.get_name() == "headless":
		return
	var visual_script = load(CHARACTER_VISUAL_PATH)
	if visual_script == null:
		return
	visual = visual_script.new()
	visual.setup("npc_%s" % npc_role, display_color, Color(0.88, 0.28, 0.22))
	add_child(visual)


func _update_visual() -> void:
	if visual == null:
		return
	var health_fraction := 1.0
	var is_dead := false
	if health != null:
		health_fraction = health.get_health_fraction()
		var current_health = health.get("current_health")
		is_dead = current_health != null and int(current_health) <= 0
	visual.set_visual_state(facing, facing, velocity, health_fraction, is_dead, _fire_flash_remaining > 0.0)
