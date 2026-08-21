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
@export_group("Arena bounds")
## Half-extents of the walled floor. The orbit is kept inside this box.
##
## A bot beaten against a wall -- which is most of them, since that is where a
## wedge pins things -- sits less than orbit_radius from it, so a naive circle
## puts the camera inside the wall for a third of the replay. The finishing blow
## then plays out as several seconds of flat red. Pulling the camera in and
## lifting it trades a wide orbit for one that always sees the subject.
## Arena.tscn puts the wall centres at +/-10.5 with a thickness of 1, so the
## inner faces -- what the camera must stay behind -- are at +/-10.0.
@export var arena_half_extent: Vector2 = Vector2(10.0, 10.0)
## Closest the camera may sit to a wall before it starts climbing instead.
@export var wall_margin: float = 0.8
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
	global_position = _seat(focus, radians)
	look_at(focus, Vector3.UP)

## Where the camera sits this frame: on the orbit if that point is inside the
## arena, otherwise pulled in to the nearest legal spot and lifted by whatever
## reach it gave up, so the subject stays framed from above instead of from
## inside the wall.
func _seat(focus: Vector3, radians: float) -> Vector3:
	var offset := Vector3(sin(radians), 0.0, cos(radians)) * orbit_radius
	var wanted := focus + offset
	var limit := Vector3(
		clampf(wanted.x, -arena_half_extent.x + wall_margin, arena_half_extent.x - wall_margin),
		0.0,
		clampf(wanted.z, -arena_half_extent.y + wall_margin, arena_half_extent.y - wall_margin))

	# How much reach the clamp cost, as a fraction of the full orbit. Spending it
	# on height keeps the subject the same size in frame.
	var kept := Vector2(limit.x - focus.x, limit.z - focus.z).length()
	var lost := clampf(1.0 - kept / maxf(orbit_radius, 0.001), 0.0, 1.0)
	return Vector3(limit.x, focus.y + orbit_height + lost * orbit_radius * 0.8, limit.z)

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
