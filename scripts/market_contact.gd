extends Area2D
class_name MarketContact

signal contacted(contact: MarketContact)
signal player_presence_changed(contact: MarketContact, is_near: bool)

@export var contact_name: String = "Contact"
@export_enum("supplier", "buyer", "fixer") var contact_type: String = "supplier"
@export var display_color: Color = Color(0.93, 0.72, 0.25)

var player_near := false
var _label: Label

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_label = Label.new()
	_label.text = contact_name
	_label.position = Vector2(-70.0, -58.0)
	_label.size = Vector2(140.0, 24.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	queue_redraw()


func _process(_delta: float) -> void:
	if player_near and Input.is_action_just_pressed("interact"):
		contacted.emit(self)


func _draw() -> void:
	var halo_color := display_color
	halo_color.a = 0.2 if player_near else 0.08
	draw_circle(Vector2.ZERO, 34.0, halo_color)
	draw_circle(Vector2.ZERO, 18.0, display_color)
	draw_circle(Vector2.ZERO, 10.0, Color(0.08, 0.08, 0.08))


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
	if body is PlayerController:
		player_near = true
		player_presence_changed.emit(self, true)
		queue_redraw()


func _on_body_exited(body: Node) -> void:
	if body is PlayerController:
		player_near = false
		player_presence_changed.emit(self, false)
		queue_redraw()
