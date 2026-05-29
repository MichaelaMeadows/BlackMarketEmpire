extends Node

signal health_changed(current_health: int, max_health: int)
signal died

@export var max_health: int = 100

var current_health: int = 100

func _ready() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)


func setup(new_max_health: int) -> void:
	max_health = max(1, new_max_health)
	current_health = max_health
	health_changed.emit(current_health, max_health)


func apply_damage(amount: int) -> void:
	if amount <= 0 or current_health <= 0:
		return

	current_health = max(0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		died.emit()


func heal(amount: int) -> void:
	if amount <= 0 or current_health <= 0:
		return

	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)


func get_health_fraction() -> float:
	if max_health <= 0:
		return 0.0
	return float(current_health) / float(max_health)
