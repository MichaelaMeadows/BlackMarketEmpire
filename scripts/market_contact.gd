extends Area2D
class_name MarketContact

signal contacted(contact: Area2D)
signal player_presence_changed(contact: Area2D, is_near: bool)

@export var contact_name: String = "Contact"
@export_enum("supplier", "buyer", "fixer") var contact_type: String = "supplier"
@export var display_color: Color = Color(0.93, 0.72, 0.25)

var player_near := false
var _label: Label
var _pulse := 0.0

func _ready() -> void:
	z_index = 18
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_label = Label.new()
	_label.text = contact_name
	_label.position = Vector2(-70.0, -58.0)
	_label.size = Vector2(140.0, 24.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.modulate = Color(0.88, 0.90, 0.86, 0.62)
	add_child(_label)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 2.8, TAU)
	if player_near and Input.is_action_just_pressed("interact"):
		contacted.emit(self)
	if player_near:
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(4.0, 12.0), 18.0, Color(0.0, 0.0, 0.0, 0.30))
	if player_near:
		var ring_color := display_color
		ring_color.a = 0.16 + sin(_pulse) * 0.05
		draw_circle(Vector2.ZERO, 34.0 + sin(_pulse) * 2.5, ring_color)
	_draw_contact_sprite()


func set_contact_data(new_name: String, new_type: String, new_color: Color) -> void:
	contact_name = new_name
	contact_type = new_type
	display_color = new_color
	if _label != null:
		_label.text = contact_name
	queue_redraw()


func get_action_label() -> String:
	match contact_type:
		"buyer":
			return "Sell"
		"fixer":
			return "Reduce Heat"
		_:
			return "Buy"


func _on_body_entered(body: Node) -> void:
	if body is CharacterBody2D:
		player_near = true
		player_presence_changed.emit(self, true)
		queue_redraw()


func _on_body_exited(body: Node) -> void:
	if body is CharacterBody2D:
		player_near = false
		player_presence_changed.emit(self, false)
		queue_redraw()


func _draw_contact_sprite() -> void:
	match contact_type:
		"buyer":
			_draw_buyer()
		"fixer":
			_draw_fixer()
		_:
			_draw_supplier()


func _draw_supplier() -> void:
	var bag := Rect2(Vector2(-18.0, -2.0), Vector2(36.0, 24.0))
	draw_rect(Rect2(bag.position + Vector2(3.0, 4.0), bag.size), Color(0.0, 0.0, 0.0, 0.24))
	draw_rect(bag, display_color.darkened(0.10))
	draw_rect(bag, Color(0.05, 0.045, 0.035), false, 3.0)
	draw_line(Vector2(-9.0, -2.0), Vector2(-4.0, -12.0), Color(0.05, 0.045, 0.035), 3.0)
	draw_line(Vector2(9.0, -2.0), Vector2(4.0, -12.0), Color(0.05, 0.045, 0.035), 3.0)
	draw_rect(Rect2(Vector2(-8.0, 5.0), Vector2(16.0, 4.0)), display_color.lightened(0.18))


func _draw_buyer() -> void:
	draw_circle(Vector2(0.0, -13.0), 8.0, Color(0.04, 0.045, 0.05))
	draw_circle(Vector2(0.0, -13.0), 6.0, Color(0.72, 0.58, 0.46))
	draw_rect(Rect2(Vector2(-10.0, -5.0), Vector2(20.0, 25.0)), display_color.darkened(0.04))
	draw_rect(Rect2(Vector2(-10.0, -5.0), Vector2(20.0, 25.0)), Color(0.035, 0.040, 0.045), false, 2.0)
	draw_rect(Rect2(Vector2(-6.0, 3.0), Vector2(12.0, 3.0)), display_color.lightened(0.16))


func _draw_fixer() -> void:
	var booth := Rect2(Vector2(-15.0, -24.0), Vector2(30.0, 46.0))
	draw_rect(Rect2(booth.position + Vector2(4.0, 5.0), booth.size), Color(0.0, 0.0, 0.0, 0.25))
	draw_rect(booth, display_color.darkened(0.12))
	draw_rect(booth, Color(0.035, 0.040, 0.048), false, 3.0)
	draw_rect(Rect2(Vector2(-10.0, -18.0), Vector2(20.0, 16.0)), Color(0.34, 0.48, 0.58, 0.72))
	draw_rect(Rect2(Vector2(-7.0, 3.0), Vector2(14.0, 12.0)), Color(0.05, 0.045, 0.052))
