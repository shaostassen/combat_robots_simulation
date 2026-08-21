extends Node
class_name BotAI
## Utility driver for one bot. Sits as a child of the chassis it drives.
##
## Deliberately not clever: no learning, no pathfinding, no perception model.
## The arena is an open box, so "point at the enemy and commit" is already a
## credible opponent, and everything past that is per-archetype judgement about
## *when* to commit.
##
## It cheats openly rather than subtly -- it reads the enemy's exact position
## straight out of the scene -- but only re-reads it every `reaction_time`. That
## stale aim is what makes it miss a moving target and feel like a driver rather
## than a turret, and it is far cheaper than simulating senses it does not have.
##
## Crucially it steers through `CombatBot.drive`, the same call the keyboard
## goes through, so it is bound by the same traction, torque and inertia the
## player is. It cannot cheat at physics, only at knowing.

enum State {
	CHARGING,  ## Committed: full throttle at the enemy.
	WINDING,   ## Backing off to rebuild weapon energy before re-engaging.
}

@export var enemy_path: NodePath
## Seconds between decisions. This is the whole difficulty knob: shorter aims
## better and tracks harder.
@export var reaction_time: float = 0.18
## Steer-only below this alignment, rather than driving off at a tangent.
@export var engage_angle: float = 30.0
@export_group("Weapon handling")
## Charge once the blade holds this fraction of its full energy.
@export var commit_energy: float = 0.85
## Break off below this. Energy goes as the square of blade rate, so a bot that
## re-engages at half rate arrives with a quarter of the punch -- backing off to
## re-spin is nearly always the better trade.
@export var retreat_energy: float = 0.45
@export_group("Working the enemy into a wall")
## How far past the enemy to aim, toward whichever wall is nearest to them.
##
## Driving at an enemy's centre shoves it into open floor, where a 54 kg machine
## absorbs the whole hit by simply moving -- a full-RPM blade lands 69 N on its
## armour, against a 250 N tolerance, and nothing breaks. The same strike on a
## machine with its back to a wall lands 1779 N and shears a panel off in one.
## Aiming through the enemy at the wall behind it is that difference, and it is
## the sport's actual tactic rather than a rule bolted on: take the escape away
## first, then hit it.
@export var wall_push: float = 4.0
## Only bias the aim inside this range. Chasing a point past a distant enemy
## reads as driving at the wall, and a bot grinding a wall is one the referee is
## counting.
@export var wall_push_range: float = 7.0
## Arena.tscn's wall inner faces, as in KillCam.
@export var arena_half_extent: Vector2 = Vector2(10.0, 10.0)

@export_group("Arm weapons")
## How close a flipper or hammer has to be before it commits its one stroke.
## Too eager and it spends the match firing at empty floor while it reloads.
@export var fire_range: float = 1.9

var state: State = State.CHARGING
## Last command issued, exposed for the HUD and the bench.
var throttle: float = 0.0
var turn: float = 0.0

var _bot: CombatBot
var _spinner: SpinnerBot
var _arm: ArmBot
var _enemy: Node3D
var _aim: Vector3
var _since_decision: float = 0.0

func _ready() -> void:
	_bot = get_parent() as CombatBot
	_spinner = _bot as SpinnerBot
	_arm = _bot as ArmBot
	_enemy = get_node_or_null(enemy_path) as Node3D
	if _bot != null:
		_aim = _bot.global_position

## Points this driver at a target directly.
##
## Bots built at runtime cannot use `enemy_path`: the AI has to be inside the
## tree before a relative path resolves, and by then _ready has run and cached a
## null. Setting the path afterwards looks like it works and silently does not --
## the driver simply never sees an opponent.
func set_enemy(target: Node3D) -> void:
	_enemy = target

func _physics_process(delta: float) -> void:
	if _bot == null or _enemy == null:
		return

	_since_decision += delta
	if _since_decision >= reaction_time:
		_since_decision = 0.0
		_aim = _enemy.global_position
		# Aim through the enemy rather than at it, once close enough that the
		# offset means a shove rather than a detour.
		var here := _bot.global_position
		if here.distance_to(_aim) < wall_push_range:
			_aim += _wall_side(_aim) * wall_push

	var to_enemy := _aim - _bot.global_position
	to_enemy.y = 0.0
	var distance := to_enemy.length()
	if distance < 0.01:
		return

	# Signed bearing to the target: negative means it is off to the right, which
	# is the direction a positive turn command sends us.
	var bearing := rad_to_deg((-_bot.global_basis.z).signed_angle_to(to_enemy, Vector3.UP))

	# A plan is a throttle plus the bearing to hold: 0 means drive straight at
	# the enemy, an offset means arc around them.
	var plan := _plan(distance)
	var aim_error := bearing - plan.y
	turn = clampf(-aim_error / engage_angle, -1.0, 1.0)
	throttle = plan.x
	if absf(aim_error) > engage_angle:
		# Badly off-aim: turn first rather than driving away at a tangent.
		throttle *= 0.25

	_bot.drive(throttle, turn, delta)

	# One stroke, then a long reload -- so only spend it with the enemy close and
	# actually in front, never on the approach.
	if _arm != null:
		_arm.drive_arm(delta)
		if _arm.arm_ready() and distance < fire_range and absf(bearing) < 22.0:
			_arm.fire()

## Unit direction from a point toward the nearest arena wall, in the floor plane.
## Which wall does not matter to the physics -- only that the enemy runs out of
## room in that direction.
func _wall_side(at: Vector3) -> Vector3:
	var east := arena_half_extent.x - at.x
	var west := at.x + arena_half_extent.x
	var north := arena_half_extent.y - at.z
	var south := at.z + arena_half_extent.y
	var nearest := minf(minf(east, west), minf(north, south))
	if nearest == east:
		return Vector3.RIGHT
	if nearest == west:
		return Vector3.LEFT
	if nearest == north:
		return Vector3.BACK
	return Vector3.FORWARD

## Returns (throttle, bearing to hold in degrees) for this archetype.
##
## The wedge has nothing to manage -- its weapon is its geometry and it is always
## ready, so it simply commits. The spinner has to decide whether it is armed.
func _plan(distance: float) -> Vector2:
	if _spinner == null:
		return Vector2(1.0, 0.0)

	# Asked fresh rather than cached at _ready: this node is a *child* of the bot,
	# so it readies first, back when the blade's inertia was still its default.
	# Caching it here read the full-energy yardstick five times too high, and the
	# spinner spent entire matches circling because it never believed it was
	# armed.
	var charged := _spinner.blade_energy / maxf(_spinner.full_energy(), 1.0)
	if state == State.CHARGING and charged < retreat_energy:
		state = State.WINDING
	elif state == State.WINDING and charged >= commit_energy:
		state = State.CHARGING

	# The weapon runs constantly. The blade is the spinner's whole threat, and
	# spin-up takes seconds it will not have once the fight is on.
	_spinner.spin_weapon(true, get_physics_process_delta_time())

	if state == State.WINDING:
		# Circle at range rather than stand off. Standing still while the blade
		# comes up is how a spinner gets counted out doing nothing, and a bot
		# that stops moving is one the referee is already counting. Arcing keeps
		# the range open, keeps the weapon pointed the right way, and keeps the
		# wheels turning.
		return Vector2(0.55, 60.0 if distance < 6.0 else 25.0)
	return Vector2(1.0, 0.0)
