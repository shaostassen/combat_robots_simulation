extends RigidBody3D
class_name CombatBot
## Skid-steer combat-robot drivetrain, shared by every archetype. Reads WASD directly (no InputMap setup
## required) and mixes throttle/turn into per-side wheel speeds, which drive the
## wheels through motorised joints -- tyre friction against the floor is what
## actually moves the chassis, exactly like a real skid-steer bot.
##
## Archetypes subclass this and bolt their weapon on top; the wedge adds nothing
## at all, since its weapon is its geometry.
##
## The wheels are driven as brushed DC motors rather than as fixed torque
## sources: available torque falls off linearly as a wheel approaches its
## commanded speed, and rises to stall torque when it is far from it. That one
## curve is what makes the bot dig in hard off the line, coast to a natural top
## speed, shove with everything it has when pinned against a wall, and feel
## genuinely heavy when you slam it from full forward into reverse.

@export_group("Drivetrain")
## Wheel speed under no load, rad/s. At a 0.28 m radius, 42 rad/s is ~11.8 m/s.
@export var free_speed: float = 42.0
## Torque one wheel can exert at zero speed, N*m at the wheel (post-gearbox).
##
## 45 N*m per wheel is deliberately above what the tyres can put down (~154 N of
## grip each, so ~43 N*m). Being traction-limited rather than torque-limited is
## what a real combat drivetrain feels like: it can break the wheels loose, it
## can pivot against tyre scrub, and the torque curve above -- not an arbitrary
## cap -- is what decides how much of that actually reaches the floor.
@export var stall_torque: float = 45.0
## Short-brake torque when the sticks are centred. Combat ESCs brake rather than
## coast, and that is a large part of why real bots feel precise.
@export var brake_torque: float = 14.0
## Must match the wheel collider; used only to derive slip for the readout.
@export var wheel_radius: float = 0.28

@export_group("Handling")
## Scales the turn command against throttle. Below 1.0 the bot keeps some
## forward drive through a full-lock turn instead of pivoting in place.
@export var turn_authority: float = 0.8
## Command units per second. Stands in for ESC ramping -- without it a keypress
## is a step input and the bot twitches instead of leaning into the throttle.
@export var input_ramp: float = 5.0
## Flip if the bot drives backwards relative to its plow.
@export var reverse_direction: bool = false
## When false the bot ignores the keyboard entirely and waits to be driven by
## something else -- a BotAI, or a bench. Both go through `drive`, so an AI
## opponent is under exactly the same physical limits the player is.
@export var player_controlled: bool = true

## Live telemetry, read by the HUD. Kept as plain fields rather than signals
## because the overlay samples once a frame and nothing else cares.
var speed: float = 0.0
var yaw_rate: float = 0.0
var slip_left: float = 0.0
var slip_right: float = 0.0
var torque_left: float = 0.0
var torque_right: float = 0.0
var peak_force: float = 0.0
## Where on the chassis the hardest contact of the frame landed, in the bot's
## own space. Armour is only useful where the hits actually are, and that is a
## measurement rather than an assumption.
var peak_contact: Vector3 = Vector3.ZERO

var _left_wheels: Array[RigidBody3D] = []
var _right_wheels: Array[RigidBody3D] = []
## Every rigid body bolted to this chassis -- wheels, weapon, armour. Tracked as
## one list so a reset moves the whole machine; teleporting the chassis and
## leaving a joined body behind lets the joint snap it back with real violence.
var _attached: Array[RigidBody3D] = []
var _attached_offsets: Array[Transform3D] = []
var _spawn_transform: Transform3D
var _throttle: float = 0.0
var _turn: float = 0.0
var _frame_force: float = 0.0

func _ready() -> void:
	_spawn_transform = global_transform
	_left_wheels = [$FrontLeftWheel, $RearLeftWheel]
	_right_wheels = [$FrontRightWheel, $RearRightWheel]

	var to_local := global_transform.affine_inverse()
	for child in get_children():
		if child is RigidBody3D:
			_attached.append(child)
			_attached_offsets.append(to_local * (child as RigidBody3D).global_transform)

	for wheel in _left_wheels + _right_wheels:
		var joint := wheel.get_node("Joint") as Generic6DOFJoint3D
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_R:
		reset_to_spawn()

func _physics_process(delta: float) -> void:
	if not player_controlled:
		return
	drive(
		float(Input.is_physical_key_pressed(KEY_W))
			- float(Input.is_physical_key_pressed(KEY_S)),
		float(Input.is_physical_key_pressed(KEY_D))
			- float(Input.is_physical_key_pressed(KEY_A)),
		delta)

## Applies a driver command, each in -1..1. Kept separate from input reading so
## the headless bench exercises exactly the path the player does, ramping and
## all, instead of a lookalike copy that can quietly drift out of sync with it.
func drive(throttle: float, turn: float, delta: float) -> void:
	_throttle = move_toward(_throttle, clampf(throttle, -1.0, 1.0), input_ramp * delta)
	_turn = move_toward(_turn, clampf(turn, -1.0, 1.0), input_ramp * delta)

	# Normalise rather than clamp each side: clamping a saturated mix quietly
	# eats the turn component, so full-throttle steering would stop responding.
	var left := _throttle + _turn * turn_authority
	var right := _throttle - _turn * turn_authority
	var peak := maxf(absf(left), absf(right))
	if peak > 1.0:
		left /= peak
		right /= peak

	var direction := -1.0 if reverse_direction else 1.0
	torque_left = _drive_side(_left_wheels, direction * left * free_speed)
	torque_right = _drive_side(_right_wheels, direction * right * free_speed)

	_update_telemetry()

## Whether the driver is actually asking for movement. The knockout rule counts
## a bot out for being commanded and failing to move -- a bot sitting still on
## purpose is not immobilised, it is just parked.
func is_commanded() -> bool:
	return maxf(absf(_throttle), absf(_turn)) > 0.1

## Commands one side's wheels and returns the torque limit that was applied.
func _drive_side(wheels: Array[RigidBody3D], target: float) -> float:
	var applied := 0.0
	for wheel in wheels:
		var actual := _wheel_speed(wheel)
		# Back-EMF made literal: current, and so torque, is proportional to the
		# gap between commanded and actual speed, saturating at stall.
		var demand := absf(target - actual) / free_speed
		var limit := stall_torque * clampf(demand, 0.0, 1.0)
		if is_zero_approx(target):
			limit = minf(limit, brake_torque)
		applied = maxf(applied, limit)

		var joint := wheel.get_node("Joint") as Generic6DOFJoint3D
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, target)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, limit)
	return applied

## Wheel spin relative to the chassis, expressed in the joint motor's own sign
## convention so it can be compared against the commanded target directly.
##
## The geometric rate about +X and the joint's notion of positive run opposite
## to one another -- verified by commanding +42 rad/s and measuring -42 -- hence
## the negation. Subtracting the chassis's own rotation matters the moment the
## bot is spinning or tumbling, when the wheel's world-space spin is no longer
## its spin about the axle.
func _wheel_speed(wheel: RigidBody3D) -> float:
	return -(wheel.angular_velocity - angular_velocity).dot(global_basis.x)

func _update_telemetry() -> void:
	var forward := -global_basis.z
	speed = linear_velocity.length()
	yaw_rate = rad_to_deg(angular_velocity.dot(global_basis.y))
	var ground_speed := linear_velocity.dot(forward)
	var direction := -1.0 if reverse_direction else 1.0
	slip_left = direction * _wheel_speed(_left_wheels[0]) * wheel_radius - ground_speed
	slip_right = direction * _wheel_speed(_right_wheels[0]) * wheel_radius - ground_speed

	# Hold the frame's peak, then bleed it so a big hit stays readable for a
	# moment instead of flashing past in one physics tick.
	peak_force = maxf(_frame_force, peak_force * 0.94)
	_frame_force = 0.0

## Totals the tick's contact impulses into the force behind them -- the same
## measure ArmorPanel does damage from, so the HUD reads in the units that
## actually decide whether something breaks.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if state.step <= 0.0:
		return
	var impulse := 0.0
	var worst := 0.0
	var at := Vector3.ZERO
	for i in state.get_contact_count():
		var magnitude := state.get_contact_impulse(i).length()
		impulse += magnitude
		if magnitude > worst:
			worst = magnitude
			at = state.get_contact_local_position(i)
	var force := impulse / state.step
	if force > _frame_force:
		_frame_force = force
		peak_contact = global_transform.affine_inverse() * at

func reset_to_spawn() -> void:
	reset_to(_spawn_transform)

## Teleports the whole bot, upright and at rest -- chassis and everything joined
## to it. Move the chassis alone and the joints snap it straight back out of
## position, or fling a heavy weapon across the arena.
func reset_to(target: Transform3D) -> void:
	_place(self, target)
	for i in _attached.size():
		_place(_attached[i], target * _attached_offsets[i])
	_throttle = 0.0
	_turn = 0.0
	peak_force = 0.0
	_frame_force = 0.0

func _place(body: RigidBody3D, target: Transform3D) -> void:
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = target
