extends Node2D
class_name ImpactEffect2D

var lifetime := 0.18
var direction := Vector2.RIGHT

func _ready() -> void:
	z_index = 31


func setup(new_position: Vector2, new_direction: Vector2 = Vector2.RIGHT) -> void:
	global_position = new_position
	if new_direction.length() > 0.0:
		direction = new_direction.normalized()


func _process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var alpha := clampf(lifetime / 0.18, 0.0, 1.0)
	var spark := Color(1.0, 0.72, 0.20, alpha)
	var smoke := Color(0.38, 0.42, 0.40, alpha * 0.35)
	draw_circle(Vector2.ZERO, 9.0 * alpha, smoke)
	draw_line(-direction * 9.0, direction * 7.0, spark, 3.0, true)
	draw_line(Vector2(-direction.y, direction.x) * 5.0, Vector2(direction.y, -direction.x) * 5.0, spark.lightened(0.25), 2.0, true)
