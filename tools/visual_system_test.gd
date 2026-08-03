extends SceneTree

const TOKENS := preload("res://scripts/ui/ui_tokens.gd")
const UI_THEME := preload("res://scripts/ui/ui_theme.gd")
const UI := preload("res://scripts/ui/ui_factory.gd")
const VISUAL_ASSETS := preload("res://scripts/ui/visual_asset_catalog.gd")

var _failures := 0

func _init() -> void:
	var theme := UI_THEME.create()
	_expect(theme != null, "shared UI theme builds")
	_expect(theme.get_color("font_color", "Label") == TOKENS.PAPER, "theme uses shared primary text token")
	_expect(theme.has_stylebox("hover", "Button"), "buttons have an explicit hover state")
	_expect(theme.has_stylebox("focus", "Button"), "buttons have a keyboard focus state")
	var button := UI.button("Test")
	_expect(button.custom_minimum_size.y >= TOKENS.CONTROL_HEIGHT, "factory buttons meet the minimum target height")
	var support := UI.label("Secondary", "support")
	_expect(support.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "factory labels wrap readable text")
	button.free()
	support.free()
	_expect(FileAccess.file_exists("res://docs/visual_style_guide.md"), "visual style guide exists")
	_expect(FileAccess.file_exists("res://assets/asset_manifest.md"), "asset manifest exists")
	for icon_name in ["base", "crew", "raids", "map", "bank", "market", "orders", "hire"]:
		var path := "res://assets/ui/icons/nav_%s.png" % icon_name
		_expect(FileAccess.file_exists(path), "%s navigation icon exists" % icon_name)
		var texture := load(path) as Texture2D
		_expect(texture != null, "%s navigation icon imports as a texture" % icon_name)
		var image := texture.get_image()
		_expect(image.get_size() == Vector2i(32, 32), "%s navigation icon is 32x32" % icon_name)
		_expect(image.detect_alpha() != Image.ALPHA_NONE, "%s navigation icon has transparency" % icon_name)
	_test_market_good_icons()
	quit(_failures)

func _test_market_good_icons() -> void:
	var goods_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/economy/goods.json"))
	for good in goods_data.get("goods", []):
		var good_id := str(good.get("id", ""))
		_expect(VISUAL_ASSETS.GOOD_FAMILIES.has(good_id), "%s has an explicit visual family" % good_id)
		var texture := VISUAL_ASSETS.get_good_icon(good_id)
		_expect(texture != null, "%s resolves to a market icon" % good_id)
		_expect(texture.get_size() == Vector2(32, 32), "%s market icon is 32x32" % good_id)

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
