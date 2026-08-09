extends CombatBot
class_name SpinnerBot
## Vertical spinner: the signature archetype, and the one the damage model was
## built to be hit by.
##
## The blade is its own rigid body on a motorised hinge, and that is the whole
## trick. Nothing here special-cases a "weapon". The blade stores real rotational
## energy over several seconds of spin-up, and on contact Jolt resolves it as an
## ordinary collision between two rigid bodies -- which means the recoil kicking
## both machines apart, the weapon bogging down after a big bite, and the
## gyroscopic resistance you feel when turning at full RPM all fall out for free
## rather than being animated.
##
## Energy is the number to watch, not RPM: it goes as the square of the rate, so
## the last few hundred RPM of spin-up carry most of the punch.

@export_group("Weapon")
## Target blade rate in rad/s. 200 rad/s is ~1900 RPM, about 50 m/s at the tip.
@export var blade_speed: float = 200.0
## Torque the weapon motor can put into the blade, N*m. This sets spin-up time,
## and just as importantly how quickly the blade recovers after a hit robs it.
@export var blade_torque: float = 18.0
@export var weapon_key: Key = KEY_SPACE

## Live weapon telemetry, read by the HUD.
var blade_rate: float = 0.0
var blade_energy: float = 0.0
var weapon_active: bool = false

var _blade: RigidBody3D
var _hinge: HingeJoint3D
var _blade_inertia: float = 1.0
var _blur: MeshInstance3D
var _blur_material: StandardMaterial3D

func _ready() -> void:
	super()
	_blade = $Blade
	_hinge = $Blade/Joint
	_hinge.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)

	# Solid box about its spin axis. Worth deriving rather than hard-coding: the
	# stored energy readout is only honest if this tracks the blade's real shape.
	var box := ($Blade/Collision as CollisionShape3D).shape as BoxShape3D
	_blade_inertia = _blade.mass * (box.size.y * box.size.y + box.size.z * box.size.z) / 12.0

	_blur = get_node_or_null("Blade/Blur") as MeshInstance3D
	if _blur != null:
		_blur_material = (_blur.get_active_material(0) as StandardMaterial3D).duplicate()
		_blur.material_override = _blur_material

func _unhandled_key_input(event: InputEvent) -> void:
	super(event)
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == weapon_key:
		weapon_active = not weapon_active

func _physics_process(delta: float) -> void:
	super(delta)
	# Under AI control the weapon is the AI's to command. Running this anyway
	# would clobber its call with weapon_active's stale `false` every tick, and
	# the blade would never leave a standstill.
	if player_controlled:
		spin_weapon(weapon_active, delta)

## Drives the weapon motor. Separated from input for the same reason `drive` is:
## the bench needs the real thing, not an imitation of it.
func spin_weapon(active: bool, delta: float) -> void:
	_hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,
		blade_speed if active else 0.0)
	# PARAM_MOTOR_MAX_IMPULSE is an impulse, not a torque, despite sitting where
	# a torque limit belongs. Feeding it newton-metres hands the motor that much
	# torque *per tick* -- at 120 Hz an intended 18 N*m became 2160, and the
	# blade snapped to full RPM in three ticks with no spin-up to watch.
	# Cutting the motor releases the blade to coast rather than braking it: a
	# spinner has no brake, and the long spin-down is half the drama.
	_hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE,
		blade_torque * delta if active else 0.0)

	blade_rate = blade_speed_now()
	blade_energy = 0.5 * _blade_inertia * blade_rate * blade_rate
	_update_blur()

## Fades the swept-arc disc in as the blade spins up, and counter-rotates it so
## it reads as a stationary disc rather than a plate bolted to the blade.
func _update_blur() -> void:
	if _blur_material == null:
		return
	var fraction := clampf(absf(blade_rate) / maxf(blade_speed, 1.0), 0.0, 1.0)
	_blur.visible = fraction > 0.12
	_blur_material.albedo_color.a = 0.55 * fraction
	_blur_material.emission_energy_multiplier = 1.6 * fraction
	_blur.global_basis = global_basis

## Energy the blade holds at its commanded rate -- the yardstick for "fully
## spun", so callers can judge readiness as a fraction instead of in joules.
func full_energy() -> float:
	return 0.5 * _blade_inertia * blade_speed * blade_speed

## Signed blade rate about the hinge, relative to the chassis. Positive is
## up-cutting: at the blade's forward-most point the edge is travelling upward,
## which is what scoops an opponent into the air rather than driving it down.
func blade_speed_now() -> float:
	return (_blade.angular_velocity - angular_velocity).dot(global_basis.x)
