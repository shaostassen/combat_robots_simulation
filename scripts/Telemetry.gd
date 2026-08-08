extends CanvasLayer
## Live physics readout for the player bot.
##
## This is a tuning instrument, not UI. Drive feel is a set of numbers, and it
## is far faster to read "3.4 m/s of wheel slip" than to infer it from the chase
## camera. The impulse row is also a dry run for M1: if contact impulses here
## are not in a sane range, the damage model built on top of them will not be
## either.

@export var target_path: NodePath
## Tab cycles the overlay off for clean capture, then back on.
@export var toggle_key: Key = KEY_TAB

@onready var _labels: Label = $Panel/Margin/Rows/Labels
@onready var _values: Label = $Panel/Margin/Rows/Values

var _bot: WedgeBot

const ROWS: Array[String] = [
	"speed", "yaw rate", "slip L / R", "drive torque", "pitch / roll",
	"peak hit", "physics", "render",
]

func _ready() -> void:
	if target_path != NodePath():
		_bot = get_node_or_null(target_path) as WedgeBot
	_labels.text = "\n".join(ROWS)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == toggle_key:
		visible = not visible
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _bot == null or not visible:
		return

	# Pitch and roll come from the basis rather than from Euler angles: once the
	# bot is upside down, Euler decomposition flips signs and the readout lies
	# exactly when you most want to trust it.
	var up := _bot.global_basis.y
	var pitch := rad_to_deg(asin(clampf(-_bot.global_basis.z.y, -1.0, 1.0)))
	var roll := rad_to_deg(asin(clampf(_bot.global_basis.x.y, -1.0, 1.0)))
	var inverted := " (inverted)" if up.y < 0.0 else ""

	_values.text = "\n".join([
		"%5.2f m/s   %5.1f km/h" % [_bot.speed, _bot.speed * 3.6],
		"%6.1f deg/s" % _bot.yaw_rate,
		"%5.2f / %5.2f m/s" % [_bot.slip_left, _bot.slip_right],
		"%5.1f / %5.1f N·m" % [_bot.torque_left, _bot.torque_right],
		"%5.1f / %5.1f deg%s" % [pitch, roll, inverted],
		"%6.0f N" % _bot.peak_force,
		"%d Hz" % Engine.physics_ticks_per_second,
		"%d fps" % Engine.get_frames_per_second(),
	])
