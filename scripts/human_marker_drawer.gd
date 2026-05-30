extends RefCounted
class_name HumanMarkerDrawer

const SKIN_COLOR := Color(0.78, 0.58, 0.44)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.22)
const OUTLINE_COLOR := Color(0.035, 0.045, 0.05, 0.86)
const DETAIL_COLOR := Color(0.94, 0.98, 1.0, 0.38)


static func draw_human(canvas: CanvasItem, body_color: Color, facing: Vector2, marker_scale: float = 1.0) -> void:
	var direction := facing.normalized()
	if direction.length() == 0.0:
		direction = Vector2.DOWN

	var right := Vector2(-direction.y, direction.x)

	canvas.draw_circle(Vector2.ZERO, 15.0 * marker_scale, SHADOW_COLOR)
	_draw_limb(canvas, -direction * 6.0 + right * 4.5, -direction * 14.0 + right * 6.0, 4.8, marker_scale)
	_draw_limb(canvas, -direction * 6.0 - right * 4.5, -direction * 14.0 - right * 6.0, 4.8, marker_scale)
	_draw_limb(canvas, -direction * 0.5 + right * 8.0, direction * 4.0 + right * 12.0, 4.2, marker_scale)
	_draw_limb(canvas, -direction * 0.5 - right * 8.0, direction * 4.0 - right * 12.0, 4.2, marker_scale)

	var torso := PackedVector2Array([
		direction * 8.0 * marker_scale,
		right * 8.5 * marker_scale,
		-direction * 9.5 * marker_scale,
		-right * 8.5 * marker_scale,
	])
	var torso_outline := PackedVector2Array([torso[0], torso[1], torso[2], torso[3], torso[0]])
	canvas.draw_colored_polygon(torso, body_color)
	canvas.draw_polyline(torso_outline, OUTLINE_COLOR, 2.0 * marker_scale, true)

	canvas.draw_line(-right * 5.5 * marker_scale, right * 5.5 * marker_scale, body_color.lightened(0.18), 2.0 * marker_scale, true)
	canvas.draw_circle(direction * 13.0 * marker_scale, 6.2 * marker_scale, OUTLINE_COLOR)
	canvas.draw_circle(direction * 13.0 * marker_scale, 4.7 * marker_scale, SKIN_COLOR)
	canvas.draw_circle(direction * 14.6 * marker_scale, 1.4 * marker_scale, DETAIL_COLOR)


static func _draw_limb(canvas: CanvasItem, start: Vector2, end: Vector2, width: float, marker_scale: float) -> void:
	canvas.draw_line(start * marker_scale, end * marker_scale, OUTLINE_COLOR, (width + 1.5) * marker_scale, true)
	canvas.draw_line(start * marker_scale, end * marker_scale, SKIN_COLOR, width * marker_scale, true)
