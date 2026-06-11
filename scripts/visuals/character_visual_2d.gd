extends AnimatedSprite2D
class_name CharacterVisual2D

const FRAME_SIZE := 48
const TRANSPARENT := Color(0.0, 0.0, 0.0, 0.0)
const OUTLINE := Color(0.025, 0.030, 0.034, 1.0)
const SHADOW := Color(0.0, 0.0, 0.0, 0.34)
const SKIN := Color(0.78, 0.58, 0.43, 1.0)
const DETAIL := Color(0.92, 0.96, 1.0, 0.55)
const HEALTH_BACK := Color(0.025, 0.030, 0.034, 0.86)
const PLAYER_HEALTH := Color(0.20, 0.88, 0.58, 1.0)
const NPC_HEALTH := Color(0.88, 0.28, 0.22, 1.0)

@export var body_color := Color(0.08, 0.74, 0.76, 1.0)
@export var accent_color := Color(0.94, 0.98, 1.0, 1.0)
@export var health_color := PLAYER_HEALTH
@export var visual_id := "player"

var facing := Vector2.DOWN
var aim_direction := Vector2.DOWN
var velocity := Vector2.ZERO
var health_fraction := 1.0
var is_dead := false
var is_hurt := false
var is_firing := false

func _ready() -> void:
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _is_headless():
		visible = false
		return
	sprite_frames = _build_sprite_frames()
	play("idle_down")


func setup(new_visual_id: String, new_body_color: Color, new_health_color: Color = PLAYER_HEALTH) -> void:
	visual_id = new_visual_id
	body_color = new_body_color
	health_color = new_health_color
	if _is_headless():
		visible = false
		return
	sprite_frames = _build_sprite_frames()
	_update_animation()
	queue_redraw()


func set_visual_state(new_facing: Vector2, new_aim_direction: Vector2, new_velocity: Vector2, new_health_fraction: float, dead: bool = false, firing: bool = false) -> void:
	if new_facing.length() > 0.0:
		facing = new_facing.normalized()
	if new_aim_direction.length() > 0.0:
		aim_direction = new_aim_direction.normalized()
	velocity = new_velocity
	health_fraction = clampf(new_health_fraction, 0.0, 1.0)
	is_dead = dead
	is_hurt = health_fraction < 0.45 and not is_dead
	is_firing = firing
	_update_animation()
	queue_redraw()


func _draw() -> void:
	if _is_headless():
		return
	draw_circle(Vector2(0.0, 15.0), 13.0, SHADOW)
	if health_fraction < 0.995 and not is_dead:
		var width := 30.0
		var position := Vector2(-width * 0.5, -31.0)
		draw_rect(Rect2(position, Vector2(width, 3.0)), HEALTH_BACK)
		draw_rect(Rect2(position, Vector2(width * health_fraction, 3.0)), health_color)


func _update_animation() -> void:
	if _is_headless():
		return
	var action := "idle"
	if is_dead:
		action = "death"
	elif is_firing:
		action = "fire"
	elif is_hurt:
		action = "hurt"
	elif velocity.length() > 1.0:
		action = "walk"
	elif aim_direction.length() > 0.0:
		action = "aim"

	var direction := aim_direction if action in ["aim", "fire"] else facing
	var suffix := _direction_suffix(direction)
	flip_h = suffix == "side" and direction.x < 0.0
	var animation_name := "%s_%s" % [action, suffix]
	if sprite_frames != null and sprite_frames.has_animation(animation_name):
		if animation != animation_name:
			play(animation_name)


func _direction_suffix(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "side"
	if direction.y < 0.0:
		return "up"
	return "down"


func _build_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for action in ["idle", "walk", "aim", "fire", "hurt", "death"]:
		for direction in ["down", "up", "side"]:
			var animation_name := "%s_%s" % [action, direction]
			frames.add_animation(animation_name)
			frames.set_animation_speed(animation_name, 6.0 if action == "walk" else 4.0)
			frames.set_animation_loop(animation_name, action != "death")
			var frame_count := 4 if action == "walk" else 2
			if action in ["hurt", "death"]:
				frame_count = 1
			for frame_index in range(frame_count):
				frames.add_frame(animation_name, _make_frame(action, direction, frame_index))
	return frames


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _make_frame(action: String, direction: String, frame_index: int) -> Texture2D:
	var image := Image.create(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(TRANSPARENT)
	var bob := 0
	if action == "walk":
		bob = -1 if frame_index % 2 == 0 else 1
	if action == "death":
		_draw_dead_body(image)
	else:
		_draw_standing_body(image, action, direction, frame_index, bob)
	return ImageTexture.create_from_image(image)


func _draw_standing_body(image: Image, action: String, direction: String, frame_index: int, bob: int) -> void:
	var center_x := 24
	var base_y := 24 + bob
	var leg_shift := 2 if frame_index % 2 == 0 else -2
	var coat := body_color.darkened(0.12) if action == "hurt" else body_color
	var glow := accent_color if action == "fire" else DETAIL

	_rect(image, center_x - 7, base_y - 3, 14, 18, OUTLINE)
	_rect(image, center_x - 6, base_y - 4, 12, 17, coat)
	_rect(image, center_x - 5, base_y - 1, 10, 2, coat.lightened(0.16))

	_rect(image, center_x - 7 + leg_shift, base_y + 12, 5, 10, OUTLINE)
	_rect(image, center_x - 6 + leg_shift, base_y + 13, 3, 8, SKIN.darkened(0.15))
	_rect(image, center_x + 2 - leg_shift, base_y + 12, 5, 10, OUTLINE)
	_rect(image, center_x + 3 - leg_shift, base_y + 13, 3, 8, SKIN.darkened(0.15))

	var head_y := base_y - 14
	_rect(image, center_x - 6, head_y - 1, 12, 12, OUTLINE)
	_rect(image, center_x - 5, head_y, 10, 10, SKIN)
	_rect(image, center_x - 3, head_y + 2, 6, 2, SKIN.lightened(0.14))

	match direction:
		"up":
			_rect(image, center_x - 4, head_y, 8, 4, OUTLINE.lightened(0.05))
			_rect(image, center_x - 9, base_y - 4, 3, 13, OUTLINE)
			_rect(image, center_x + 6, base_y - 4, 3, 13, OUTLINE)
		"side":
			_rect(image, center_x + 3, head_y + 3, 3, 3, OUTLINE)
			_rect(image, center_x - 10, base_y - 1, 5, 12, OUTLINE)
			_rect(image, center_x - 9, base_y, 3, 10, SKIN.darkened(0.08))
			if action in ["aim", "fire"]:
				_rect(image, center_x + 6, base_y - 3, 12, 4, OUTLINE)
				_rect(image, center_x + 7, base_y - 2, 10, 2, glow)
				if action == "fire":
					_rect(image, center_x + 18, base_y - 4, 5, 6, Color(1.0, 0.72, 0.18, 1.0))
		_:
			_rect(image, center_x - 9, base_y - 1, 5, 12, OUTLINE)
			_rect(image, center_x - 8, base_y, 3, 10, SKIN.darkened(0.08))
			_rect(image, center_x + 4, base_y - 1, 5, 12, OUTLINE)
			_rect(image, center_x + 5, base_y, 3, 10, SKIN.darkened(0.08))
			if action in ["aim", "fire"]:
				_rect(image, center_x + 6, base_y + 1, 4, 12, OUTLINE)
				_rect(image, center_x + 7, base_y + 2, 2, 10, glow)
				if action == "fire":
					_rect(image, center_x + 5, base_y + 13, 6, 4, Color(1.0, 0.72, 0.18, 1.0))


func _draw_dead_body(image: Image) -> void:
	_rect(image, 12, 28, 25, 8, OUTLINE)
	_rect(image, 14, 29, 21, 6, body_color.darkened(0.24))
	_rect(image, 33, 25, 9, 9, OUTLINE)
	_rect(image, 34, 26, 7, 7, SKIN.darkened(0.10))


func _rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	for px in range(max(0, x), min(FRAME_SIZE, x + width)):
		for py in range(max(0, y), min(FRAME_SIZE, y + height)):
			image.set_pixel(px, py, color)
