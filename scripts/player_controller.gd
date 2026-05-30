extends CharacterBody2D
class_name PlayerController

signal health_changed(current_health: int, max_health: int)
signal died

const HEALTH_COMPONENT_SCRIPT := preload("res://scripts/health_component.gd")
const GUN_COMPONENT_SCRIPT := preload("res://scripts/gun_component.gd")
const HUMAN_MARKER_DRAWER := preload("res://scripts/human_marker_drawer.gd")

@export var speed: float = 280.0
@export var max_health: int = 100

var faction := "player"
var facing: Vector2 = Vector2.DOWN
var aim_direction: Vector2 = Vector2.DOWN
var controls_enabled := true
var health
var gun

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("player")
	add_to_group("combat_unit")

	health = HEALTH_COMPONENT_SCRIPT.new()
	add_child(health)
	health.setup(max_health)
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)

	gun = GUN_COMPONENT_SCRIPT.new()
	add_child(gun)

func _physics_process(_delta: float) -> void:
	if not controls_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length() > 0.0:
		facing = input_vector.normalized()

	_update_aim_direction()
	velocity = input_vector * speed
	move_and_slide()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if controls_enabled and event.is_action_pressed("fire"):
		fire_weapon()


func fire_weapon() -> void:
	if gun != null:
		_update_aim_direction()
		gun.try_fire(self, aim_direction)


func apply_damage(amount: int) -> void:
	if health != null:
		health.apply_damage(amount)


func get_faction() -> String:
	return faction


func _draw() -> void:
	HUMAN_MARKER_DRAWER.draw_human(self, Color(0.08, 0.74, 0.76), aim_direction, 0.95)
	var hand_offset := Vector2(-aim_direction.y, aim_direction.x) * 8.0
	draw_line(aim_direction * 4.0 + hand_offset, aim_direction * 24.0 + hand_offset, Color(0.94, 0.98, 1.0), 3.0, true)

	if health != null:
		var bar_width := 34.0
		var bar_position := Vector2(-bar_width * 0.5, -30.0)
		draw_rect(Rect2(bar_position, Vector2(bar_width, 4.0)), Color(0.12, 0.12, 0.12))
		draw_rect(Rect2(bar_position, Vector2(bar_width * health.get_health_fraction(), 4.0)), Color(0.20, 0.88, 0.58))


func _on_health_changed(current_health: int, current_max_health: int) -> void:
	health_changed.emit(current_health, current_max_health)
	queue_redraw()


func _on_died() -> void:
	died.emit()
	controls_enabled = false


func _update_aim_direction() -> void:
	var mouse_direction := get_global_mouse_position() - global_position
	if mouse_direction.length() > 0.0:
		aim_direction = mouse_direction.normalized()
