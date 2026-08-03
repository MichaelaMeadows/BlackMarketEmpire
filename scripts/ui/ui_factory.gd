extends RefCounted
class_name UiFactory

const T := preload("res://scripts/ui/ui_tokens.gd")
const THEME := preload("res://scripts/ui/ui_theme.gd")

static func label(text: String, role: String = "body") -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	match role:
		"title":
			node.add_theme_font_size_override("font_size", T.TEXT_TITLE)
		"section":
			node.add_theme_font_size_override("font_size", T.TEXT_SECTION)
		"support":
			node.add_theme_font_size_override("font_size", T.TEXT_SUPPORT)
			node.modulate = T.DUST
		"muted":
			node.add_theme_font_size_override("font_size", T.TEXT_SUPPORT)
			node.modulate = T.MUTED
		_:
			node.add_theme_font_size_override("font_size", T.TEXT_BODY)
	return node


static func button(text: String, tooltip: String = "", primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.tooltip_text = tooltip
	node.custom_minimum_size.y = T.PRIMARY_CONTROL_HEIGHT if primary else T.CONTROL_HEIGHT
	if primary:
		node.add_theme_stylebox_override("normal", THEME.panel_style(Color("173436"), T.SIGNAL, 1, T.CORNER, T.SPACE_2))
	return node


static func panel(padding: int = T.SPACE_4) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", THEME.panel_style(T.STEEL, T.RULE, 1, T.CORNER, padding))
	return node


static func apply_status(label_node: Label, status: String) -> void:
	match status:
		"success": label_node.modulate = T.SUCCESS
		"warning": label_node.modulate = T.WARNING
		"danger": label_node.modulate = T.DANGER
		"cash": label_node.modulate = T.CASH
		"signal": label_node.modulate = T.SIGNAL
		"muted": label_node.modulate = T.MUTED
		_: label_node.modulate = T.PAPER

