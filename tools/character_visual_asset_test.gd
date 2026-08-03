extends SceneTree

const CHARACTER_VISUAL := preload("res://scripts/visuals/character_visual_2d.gd")
const PLAYER_SHEET := preload("res://assets/sprites/characters/player_streetwear.png")

var _failures := 0

func _init() -> void:
	_expect(CHARACTER_VISUAL != null, "character visual script compiles with sheet support")
	_expect(PLAYER_SHEET.get_size() == Vector2(576, 144), "player sheet is exactly 576x144")
	var image := PLAYER_SHEET.get_image()
	_expect(image.detect_alpha() != Image.ALPHA_NONE, "player sheet has transparency")
	var source := FileAccess.get_file_as_string("res://scripts/visuals/character_visual_2d.gd")
	_expect(source.contains("_build_player_sprite_frames"), "player uses imported sprite frames")
	_expect(source.contains("direction_rows := {\"down\": 0, \"up\": 1, \"side\": 2}"), "player sheet row mapping is explicit")
	_expect(source.contains("\"walk\": [2, 3, 4, 5]"), "player walk animation uses four specified frames")
	quit(_failures)

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
