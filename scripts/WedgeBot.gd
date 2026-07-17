extends RigidBody3D
## Skid-steer tank drive. Reads WASD directly (no InputMap setup required)
## and mixes throttle/turn into left/right wheel target velocities, which
## drive the wheels through motorized joints -- friction with the floor is
## what actually moves the chassis, same as a real skid-steer robot.

@export var max_wheel_speed: float = 45.0  # rad/s at full throttle
@export var motor_torque: float = 90.0     # N*m the wheel motor can exert
## Flip this if the bot drives backwards relative to its visual nose.
@export var reverse_direction: bool = false

var _left_joints: Array[Generic6DOFJoint3D] = []
var _right_joints: Array[Generic6DOFJoint3D] = []

func _ready() -> void:
	_left_joints = [$FrontLeftWheel/Joint, $RearLeftWheel/Joint]
	_right_joints = [$FrontRightWheel/Joint, $RearRightWheel/Joint]
	for joint in _left_joints + _right_joints:
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, motor_torque)

func _physics_process(_delta: float) -> void:
	var throttle := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	var turn := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))

	var dir_sign := 1.0 if not reverse_direction else -1.0
	var left_speed := dir_sign * clampf(throttle + turn, -1.0, 1.0) * max_wheel_speed
	var right_speed := dir_sign * clampf(throttle - turn, -1.0, 1.0) * max_wheel_speed

	for joint in _left_joints:
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, left_speed)
	for joint in _right_joints:
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, right_speed)
