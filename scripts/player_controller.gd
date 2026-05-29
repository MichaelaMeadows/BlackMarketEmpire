extends CharacterBody2D
class_name PlayerController

@export var speed: float = 280.0

var facing: Vector2 = Vector2.DOWN

func _physics_process(_delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length() > 0.0:
		facing = input_vector.normalized()

	velocity = input_vector * speed
	move_and_slide()
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 14.0, Color(0.08, 0.74, 0.76))
	draw_circle(Vector2.ZERO, 8.0, Color(0.04, 0.16, 0.18))
	draw_line(Vector2.ZERO, facing * 22.0, Color(0.94, 0.98, 1.0), 3.0)
