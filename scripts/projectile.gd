extends Area2D

var direction := Vector2.RIGHT
var speed := 720.0
var damage := 20
var lifetime := 1.2
var source: Node

func setup(new_position: Vector2, new_direction: Vector2, weapon_data: Dictionary, new_source: Node) -> void:
	global_position = new_position
	direction = new_direction.normalized()
	speed = float(weapon_data.get("projectile_speed", speed))
	damage = int(weapon_data.get("damage", damage))
	lifetime = float(weapon_data.get("projectile_lifetime", lifetime))
	source = new_source


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.86, 0.30))
	draw_circle(Vector2.ZERO, 7.0, Color(1.0, 0.58, 0.18, 0.22))


func _on_body_entered(body: Node) -> void:
	if body == source:
		return

	if body.has_method("notify_attacked_by"):
		body.notify_attacked_by(source)

	if body.has_method("apply_damage"):
		body.apply_damage(damage)

	queue_free()
