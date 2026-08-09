extends CombatBot
class_name ArmBot
## A weapon on a limited hinge: one powered stroke, then a reload. Both the
## flipper and the hammer are this, differing only in where the pivot sits, how
## far the arm travels and how hard it is driven.
##
## Unlike the spinner there is no stored energy here -- the arm is nearly
## weightless until it fires, and everything depends on the stroke itself. That
## makes these two archetypes a straight lesson in impulse and leverage: whether
## the opponent actually goes over is decided by its mass, where the arm caught
## it, and whether the arm got underneath at all. Miss the timing and a
## full-power stroke does nothing but lift the bot's own nose.
##
## Torque is deliberately huge compared with the drivetrain, because a real
## flipper is a pressure vessel dumping in a tenth of a second, not a motor.

signal fired

enum ArmState {
	READY,     ## Sitting at rest, able to fire.
	FIRING,    ## Stroke in progress.
	RESETTING, ## Travelling back to rest.
	RELOADING, ## Back at rest, waiting out the recharge.
}

@export_group("Weapon")
## Where the arm sits when ready, degrees about the hinge.
@export var rest_angle: float = 0.0
## End of the powered stroke.
@export var fired_angle: float = 75.0
## Torque during the stroke, N*m. Enormous on purpose.
@export var fire_torque: float = 900.0
## Torque returning to rest -- gentle, so the arm does not slam itself back.
@export var reset_torque: float = 90.0
## How long the stroke stays powered.
@export var stroke_time: float = 0.22
## Recharge once the arm is home again.
@export var reload_time: float = 1.6
@export var weapon_key: Key = KEY_SPACE

var arm_state: ArmState = ArmState.READY
## 0..1, how far through the recharge. 1 means ready.
var reload_fraction: float = 1.0

var _arm: RigidBody3D
var _hinge: HingeJoint3D
var _timer: float = 0.0

func _ready() -> void:
	super()
	_arm = $Arm
	_hinge = $Arm/Joint
	_hinge.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)

func _unhandled_key_input(event: InputEvent) -> void:
	super(event)
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo \
			and key.physical_keycode == weapon_key:
		fire()

func _physics_process(delta: float) -> void:
	super(delta)
	drive_arm(delta)

## True when a stroke would actually do something.
func arm_ready() -> bool:
	return arm_state == ArmState.READY

## Requests a stroke. Ignored unless the arm is home and recharged, so holding
## the key down does not turn the weapon into a continuous drive.
func fire() -> bool:
	if arm_state != ArmState.READY:
		return false
	arm_state = ArmState.FIRING
	_timer = stroke_time
	reload_fraction = 0.0
	fired.emit()
	return true

## Runs the arm's state machine. Split from input so the AI and the bench use
## exactly this path.
func drive_arm(delta: float) -> void:
	_timer -= delta
	match arm_state:
		ArmState.FIRING:
			_command(fired_angle, fire_torque, delta)
			if _timer <= 0.0:
				arm_state = ArmState.RESETTING
				_timer = 2.0
		ArmState.RESETTING:
			_command(rest_angle, reset_torque, delta)
			# Home when it gets there, or when it clearly is not going to --
			# something jammed under the arm should not deadlock the weapon.
			if absf(arm_angle() - rest_angle) < 6.0 or _timer <= 0.0:
				arm_state = ArmState.RELOADING
				_timer = reload_time
		ArmState.RELOADING:
			_command(rest_angle, reset_torque, delta)
			reload_fraction = clampf(1.0 - _timer / maxf(reload_time, 0.001), 0.0, 1.0)
			if _timer <= 0.0:
				arm_state = ArmState.READY
				reload_fraction = 1.0
		ArmState.READY:
			_command(rest_angle, reset_torque, delta)

## Current arm position in degrees about the hinge, relative to the chassis.
func arm_angle() -> float:
	var relative := global_basis.inverse() * _arm.global_basis
	var forward := relative * Vector3.FORWARD
	return rad_to_deg(atan2(forward.y, -forward.z))

func _command(target_angle: float, torque: float, delta: float) -> void:
	# Drive toward the target angle rather than at a fixed rate: the hinge limit
	# stops the arm, and the motor just keeps pushing until it gets there.
	var error := target_angle - arm_angle()
	_hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,
		clampf(deg_to_rad(error) * 12.0, -30.0, 30.0))
	# Same trap as the spinner: max_impulse is an impulse, so a torque has to be
	# handed over as torque * delta or it is scaled by the tick rate.
	_hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, torque * delta)
