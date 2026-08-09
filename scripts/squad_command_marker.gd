extends Node2D
class_name SquadCommandMarker

const HOLD_COLOR := Color(0.22, 0.78, 0.79, 0.9)
const ATTACK_COLOR := Color(0.84, 0.34, 0.30, 0.95)
const HOLD_MARKER_RADIUS := 11.0

var hold_positions: Array[Vector2] = []
var attack_target: Node2D


func _process(_delta: float) -> void:
	if attack_target != null:
		if is_instance_valid(attack_target):
			queue_redraw()
		else:
			attack_target = null
			queue_redraw()


func show_follow() -> void:
	hold_positions.clear()
	attack_target = null
	queue_redraw()


func show_hold(positions: Array) -> void:
	hold_positions.clear()
	for position in positions:
		if position is Vector2:
			hold_positions.append(position)
	attack_target = null
	queue_redraw()


func show_attack(target: Node2D) -> void:
	hold_positions.clear()
	attack_target = target
	queue_redraw()


func _draw() -> void:
	for position in hold_positions:
		var local_position := to_local(position)
		draw_circle(local_position + Vector2(0.0, 1.5), HOLD_MARKER_RADIUS + 2.0, Color(0.0, 0.0, 0.0, 0.16))
		draw_circle(local_position, HOLD_MARKER_RADIUS, Color(HOLD_COLOR, 0.10))
		draw_arc(local_position, HOLD_MARKER_RADIUS, 0.0, TAU, 24, Color(HOLD_COLOR, 0.72), 1.5, true)
		var shield := PackedVector2Array([
			local_position + Vector2(-4.0, -4.0),
			local_position + Vector2(4.0, -4.0),
			local_position + Vector2(4.0, 0.5),
			local_position + Vector2(0.0, 5.0),
			local_position + Vector2(-4.0, 0.5),
		])
		draw_colored_polygon(shield, Color(HOLD_COLOR, 0.34))
		var shield_outline := PackedVector2Array(shield)
		shield_outline.append(shield[0])
		draw_polyline(shield_outline, Color(HOLD_COLOR, 0.88), 1.25, true)

	if attack_target != null and is_instance_valid(attack_target):
		var target_position := to_local(attack_target.global_position)
		var pulse := 22.0 + sin(Time.get_ticks_msec() * 0.008) * 3.0
		draw_arc(target_position, pulse, 0.0, TAU, 36, ATTACK_COLOR, 3.0)
		draw_line(target_position + Vector2(-pulse, -pulse), target_position + Vector2(-pulse + 9.0, -pulse + 9.0), ATTACK_COLOR, 3.0)
		draw_line(target_position + Vector2(pulse, -pulse), target_position + Vector2(pulse - 9.0, -pulse + 9.0), ATTACK_COLOR, 3.0)
