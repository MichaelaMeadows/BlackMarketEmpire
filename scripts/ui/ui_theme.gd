extends RefCounted
class_name UiTheme

const T := preload("res://scripts/ui/ui_tokens.gd")

static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = T.TEXT_BODY
	_set_colors(theme)
	_set_spacing(theme)
	_set_styles(theme)
	return theme


static func panel_style(background: Color, border: Color, border_width: int = 1, radius: int = 2, padding: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	return style


static func _set_colors(theme: Theme) -> void:
	for type_name in ["Label", "Button", "CheckBox", "OptionButton", "SpinBox", "LineEdit"]:
		theme.set_color("font_color", type_name, T.PAPER)
		theme.set_color("font_disabled_color", type_name, T.MUTED)
		theme.set_color("font_hover_color", type_name, T.PAPER)
		theme.set_color("font_pressed_color", type_name, T.PAPER)
		theme.set_color("font_focus_color", type_name, T.PAPER)
	theme.set_color("font_outline_color", "Label", Color(T.INK, 0.82))
	theme.set_constant("outline_size", "Label", 2)
	theme.set_color("font_selected_color", "LineEdit", T.INK)
	theme.set_color("selection_color", "LineEdit", T.SIGNAL)


static func _set_spacing(theme: Theme) -> void:
	theme.set_constant("separation", "HBoxContainer", T.SPACE_2)
	theme.set_constant("separation", "VBoxContainer", T.SPACE_2)
	theme.set_constant("h_separation", "GridContainer", T.SPACE_3)
	theme.set_constant("v_separation", "GridContainer", T.SPACE_2)
	theme.set_constant("icon_max_width", "Button", 24)
	theme.set_constant("outline_size", "Button", 0)


static func _set_styles(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", panel_style(T.STEEL, T.RULE))
	theme.set_stylebox("normal", "Button", panel_style(T.STEEL, T.RULE, 1, T.CORNER, T.SPACE_2))
	theme.set_stylebox("hover", "Button", panel_style(T.STEEL_LIGHT, T.DUST, 1, T.CORNER, T.SPACE_2))
	theme.set_stylebox("pressed", "Button", panel_style(Color("173436"), T.SIGNAL, 2, T.CORNER, T.SPACE_2))
	theme.set_stylebox("focus", "Button", panel_style(Color(0, 0, 0, 0), T.SIGNAL, 2, T.CORNER, 0))
	theme.set_stylebox("disabled", "Button", panel_style(T.ASPHALT, Color(T.RULE, 0.45), 1, T.CORNER, T.SPACE_2))
	for type_name in ["LineEdit", "SpinBox", "OptionButton"]:
		theme.set_stylebox("normal", type_name, panel_style(T.ASPHALT, T.RULE, 1, T.CORNER, T.SPACE_2))
		theme.set_stylebox("focus", type_name, panel_style(T.ASPHALT, T.SIGNAL, 2, T.CORNER, T.SPACE_2))
	theme.set_stylebox("panel", "PopupPanel", panel_style(T.STEEL, T.RULE, 1, T.CORNER_MODAL, T.SPACE_2))
