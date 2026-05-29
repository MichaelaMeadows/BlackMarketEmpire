extends CanvasLayer

signal phone_visibility_changed(is_open: bool)

const PHONE_MAP_VIEW_SCRIPT := preload("res://scripts/phone_map_view.gd")

var map_loader
var player
var current_app := "home"
var phone_root: Control
var title_label: Label
var app_content: VBoxContainer
var map_view
var bank_label: Label

func _ready() -> void:
	visible = false
	_build_ui()
	GameState.state_changed.connect(_refresh_bank)
	set_process(false)


func setup(new_map_loader, new_player) -> void:
	map_loader = new_map_loader
	player = new_player
	if map_view != null and map_loader != null:
		map_view.set_map_data(map_loader.get_map_data())


func toggle() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		_show_app(current_app)
	phone_visibility_changed.emit(visible)


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	if visible and current_app == "map" and player != null:
		map_view.set_player_position(player.position)


func _build_ui() -> void:
	phone_root = Control.new()
	phone_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(phone_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.42)
	phone_root.add_child(shade)

	var phone := PanelContainer.new()
	phone.anchor_left = 0.5
	phone.anchor_top = 0.5
	phone.anchor_right = 0.5
	phone.anchor_bottom = 0.5
	phone.offset_left = -185.0
	phone.offset_top = -315.0
	phone.offset_right = 185.0
	phone.offset_bottom = 315.0
	phone_root.add_child(phone)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	phone.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	layout.add_child(header)

	title_label = Label.new()
	title_label.text = "Phone"
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "Tab"
	close_button.tooltip_text = "Close phone"
	close_button.pressed.connect(toggle)
	header.add_child(close_button)

	var app_bar := HBoxContainer.new()
	app_bar.add_theme_constant_override("separation", 8)
	layout.add_child(app_bar)

	_add_app_button(app_bar, "Messages", "messages")
	_add_app_button(app_bar, "Map", "map")
	_add_app_button(app_bar, "Bank", "bank")

	app_content = VBoxContainer.new()
	app_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app_content.add_theme_constant_override("separation", 10)
	layout.add_child(app_content)

	_build_home_app()


func _add_app_button(parent: HBoxContainer, label: String, app_id: String) -> void:
	var button := Button.new()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_show_app.bind(app_id))
	parent.add_child(button)


func _show_app(app_id: String) -> void:
	current_app = app_id
	for child in app_content.get_children():
		child.queue_free()

	match app_id:
		"messages":
			_build_messages_app()
		"map":
			_build_map_app()
		"bank":
			_build_bank_app()
		_:
			_build_home_app()


func _build_home_app() -> void:
	title_label.text = "Phone"
	var label := Label.new()
	label.text = "Choose an app."
	label.add_theme_font_size_override("font_size", 18)
	app_content.add_child(label)


func _build_messages_app() -> void:
	title_label.text = "Messages"
	var label := Label.new()
	label.text = "No new messages."
	label.add_theme_font_size_override("font_size", 18)
	app_content.add_child(label)


func _build_map_app() -> void:
	title_label.text = "Map"
	var map_name := Label.new()
	map_name.text = map_loader.get_title() if map_loader != null else "Unknown Map"
	map_name.add_theme_font_size_override("font_size", 17)
	app_content.add_child(map_name)

	map_view = PHONE_MAP_VIEW_SCRIPT.new()
	map_view.custom_minimum_size = Vector2(320.0, 420.0)
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if map_loader != null:
		map_view.set_map_data(map_loader.get_map_data())
	if player != null:
		map_view.set_player_position(player.position)
	app_content.add_child(map_view)


func _build_bank_app() -> void:
	title_label.text = "Bank"
	bank_label = Label.new()
	bank_label.add_theme_font_size_override("font_size", 18)
	app_content.add_child(bank_label)
	_refresh_bank()


func _refresh_bank() -> void:
	if bank_label == null:
		return

	bank_label.text = "Cash: $%d\nHeat: %d%%\nStock: %d %s" % [
		GameState.cash,
		GameState.heat,
		GameState.get_stock(),
		GameState.product_name,
	]
