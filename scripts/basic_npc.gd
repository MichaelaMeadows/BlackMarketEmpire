extends CharacterBody2D

signal died(npc: CharacterBody2D)

const HEALTH_COMPONENT_SCRIPT := preload("res://scripts/health_component.gd")
const GUN_COMPONENT_SCRIPT := preload("res://scripts/gun_component.gd")

var npc_name := "NPC"
var npc_role := "neighbor"
var display_color := Color(0.70, 0.77, 0.82)
var health
var gun
var label: Label

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("npc")

	if health == null:
		health = HEALTH_COMPONENT_SCRIPT.new()
		add_child(health)
		health.setup(60)
		health.health_changed.connect(_on_health_changed)
		health.died.connect(_on_died)

	if gun == null:
		gun = GUN_COMPONENT_SCRIPT.new()
		add_child(gun)

	_build_label()
	queue_redraw()


func setup(npc_data: Dictionary) -> void:
	npc_name = str(npc_data.get("name", npc_name))
	npc_role = str(npc_data.get("role", npc_role))
	display_color = _read_color(npc_data.get("color", []), display_color)

	if health == null:
		health = HEALTH_COMPONENT_SCRIPT.new()
		add_child(health)
		health.health_changed.connect(_on_health_changed)
		health.died.connect(_on_died)
	health.setup(int(npc_data.get("health", 60)))

	if gun == null:
		gun = GUN_COMPONENT_SCRIPT.new()
		add_child(gun)
	if npc_data.has("weapon"):
		gun.setup(npc_data["weapon"])

	if label != null:
		label.text = npc_name
	queue_redraw()


func apply_damage(amount: int) -> void:
	if health != null:
		health.apply_damage(amount)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 16.0, display_color)
	draw_circle(Vector2.ZERO, 8.0, Color(0.08, 0.08, 0.08))

	if health != null:
		var bar_width := 36.0
		var bar_position := Vector2(-bar_width * 0.5, -28.0)
		draw_rect(Rect2(bar_position, Vector2(bar_width, 4.0)), Color(0.12, 0.12, 0.12))
		draw_rect(Rect2(bar_position, Vector2(bar_width * health.get_health_fraction(), 4.0)), Color(0.88, 0.26, 0.20))


func _build_label() -> void:
	if label != null:
		return

	label = Label.new()
	label.text = npc_name
	label.position = Vector2(-40.0, -46.0)
	label.size = Vector2(80.0, 22.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	add_child(label)


func _on_health_changed(_current_health: int, _max_health: int) -> void:
	queue_redraw()


func _on_died() -> void:
	died.emit(self)
	queue_free()


func _read_color(value: Variant, fallback: Color) -> Color:
	if value is Array and value.size() >= 3:
		var alpha: float = float(value[3]) if value.size() >= 4 else 1.0
		return Color(float(value[0]), float(value[1]), float(value[2]), alpha)
	return fallback
