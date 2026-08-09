extends Camera3D
class_name KillCam
## Slow-motion replay camera for the finishing blow.
##
## Takes over the moment the match is decided, drops `Engine.time_scale` and
## orbits the beaten machine while the arena keeps simulating around it -- debris
## still falling, a blade still coasting down. Nothing is recorded or replayed:
## it is the same physics, just watched slowly from a better seat, which is why
## it never disagrees with what actually happened.
##
## Its own clock runs on wall time. Every `delta` in the engine is scaled by
## `time_scale`, so a replay timed with delta would stretch by exactly the factor
## it is trying to time.

@export var match_path: NodePath
@export var chase_path: NodePath
@export var orbit_radius: float = 4.5
@export var orbit_height: float = 2.2
@export var orbit_speed: float = 50.0
## How far down time is dragged at the slowest point.
@export var slow_motion: float = 0.18
## Wall-clock seconds the replay runs for.
@export var duration: float = 4.0

var active: bool = false

var _match: Match
var _chase: Camera3D
var _subject: Node3D
var _started_ms: int = 0
var _angle: float = 0.0

func _ready() -> void:
	_match = get_node_or_null(match_path) as Match
	_chase = get_node_or_null(chase_path) as Camera3D
	if _match != null:
		_match.finished.connect(_on_finished)

func _on_finished(_winner: CombatBot, _reason: String) -> void:
	_subject = _match.loser()
	if _subject == null:
		return
	active = true
	current = true
	_started_ms = Time.get_ticks_msec()
	# Start the orbit behind the subject so the first frame is not a jump cut.
	var offset := global_position - _subject.global_position
	_angle = rad_to_deg(atan2(offset.x, offset.z))

func _process(_delta: float) -> void:
	if not active or _subject == null:
		return

	var elapsed := (Time.get_ticks_msec() - _started_ms) / 1000.0
	if elapsed >= duration:
		_stop()
		return

	# Snap into slow motion, hold, then let time run back up so the arena settles
	# at normal speed rather than snapping out of it.
	var progress := elapsed / duration
	var scale := slow_motion
	if progress > 0.75:
		scale = lerpf(slow_motion, 1.0, (progress - 0.75) / 0.25)
	Engine.time_scale = scale

	_angle += orbit_speed * _delta / maxf(scale, 0.01)
	var radians := deg_to_rad(_angle)
	var focus := _subject.global_position
	global_position = focus + Vector3(
		sin(radians) * orbit_radius, orbit_height, cos(radians) * orbit_radius)
	look_at(focus, Vector3.UP)

func _exit_tree() -> void:
	# Time scale is global and outlives this node. Being freed mid-replay -- a
	# scene reload, a quit -- would otherwise leave the whole game in slow motion
	# with nothing still running that knows to undo it.
	if active:
		_stop()

func _stop() -> void:
	active = false
	Engine.time_scale = 1.0
	if _chase != null and is_instance_valid(_chase):
		_chase.current = true
