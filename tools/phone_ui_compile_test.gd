extends SceneTree

const PHONE_UI_SCRIPT := preload("res://scripts/phone_ui.gd")

var _failures: int = 0


func _init() -> void:
	_expect(PHONE_UI_SCRIPT != null, "phone UI script compiles")
	_test_tab_closes_open_phone()

	if _failures == 0:
		print("Phone UI compile tests passed.")
	else:
		push_error("Phone UI compile tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_tab_closes_open_phone() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	_expect(source.contains("func _input(event: InputEvent)"), "main handles phone input before GUI focus")
	_expect(source.contains("event.is_action_pressed(\"phone\")"), "main listens for the phone action")
	_expect(source.contains("phone_ui.toggle()"), "phone action toggles an already-open phone UI")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
