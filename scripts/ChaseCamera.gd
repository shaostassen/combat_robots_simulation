extends Camera3D
## Third-person chase camera: hovers behind and above the target, smoothly
## following its position and yaw (ignores roll/pitch so physics tumbling
## doesn't make the camera seasick).

@export var target_path: NodePath
@export var distance: float = 6.0
@export var height: float = 3.0
@export var look_height: float = 0.6
@export var position_smoothing: float = 6.0
@export var rotation_smoothing: float = 6.0

var _target: Node3D

func _ready() -> void:
	if target_path != NodePath():
		_target = get_node(target_path)

func _physics_process(delta: float) -> void:
	if _target == null:
		return

	var forward := -_target.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	var desired_position := _target.global_position - forward * distance + Vector3.UP * height
	var pos_weight := 1.0 - exp(-position_smoothing * delta)
	global_position = global_position.lerp(desired_position, pos_weight)

	var look_target := _target.global_position + Vector3.UP * look_height
	var to_target := look_target - global_position
	if to_target.length() > 0.01:
		var desired_basis := Transform3D().looking_at(to_target, Vector3.UP).basis
		var rot_weight := 1.0 - exp(-rotation_smoothing * delta)
		global_transform.basis = global_transform.basis.slerp(desired_basis, rot_weight)
