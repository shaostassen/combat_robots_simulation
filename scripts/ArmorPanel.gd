@tool
extends RigidBody3D
class_name ArmorPanel
## An armour panel welded to a parent chassis by a locked 6DOF joint, which
## shears off once it has absorbed enough punishment.
##
## Godot has no breakable joint, so breaking is ours: the panel watches its own
## contact impulses, banks whatever exceeds its tolerance, and when the total
## passes its integrity the joint is simply freed. The panel is already a rigid
## body at that point, so it keeps the velocity it had and tumbles away on its
## own -- no spawning, no swapping, no special case.
##
## Damage is denominated in N*s rather than hit points: a slow shove is below
## tolerance and does literally nothing, and a full-speed strike is catastrophic,
## with no lookup table anywhere in the chain.
##
## Expects to sit as a direct child of the chassis body, so the joint's
## NodePath("../..") resolves to it.

signal damaged(fraction: float)
signal broke(panel: ArmorPanel)

@export var size := Vector3(0.5, 0.3, 0.05):
	set(value):
		size = value
		_rebuild()

@export_group("Damage")
## Contact force the panel shrugs off entirely, in newtons.
##
## Measured as force, not impulse, and summed across every contact point rather
## than tested point by point. Both matter: a collision spreads its impulse over
## many points and many ticks, so no single point ever looks dramatic, and a
## raw impulse threshold would silently mean something different at 60 Hz than
## at 120 Hz. Force is what the panel actually feels, at any tick rate.
##
## Measured against the wedge: leaning on a panel at quarter throttle peaks
## around 140 N, and a full-speed ram peaks around 700 N. 250 N sits between
## them with margin on both sides.
@export var tolerance: float = 250.0
## Banked over-tolerance impulse (N*s) the weld survives before it lets go.
##
## A full-speed wedge ram banks roughly 4.5 N*s, so 14 means three or four solid
## hits -- and that is deliberate. A plow is a ramp: it turns an impact into lift
## and shove rather than a square blow, so it should struggle to shear armour.
## The headroom above it belongs to M2's spinner, which is meant to do this in
## one strike.
@export var integrity: float = 14.0

## A collision spans dozens of ticks; without a floor on the gap between bursts
## a single hit would spawn hundreds of them.
const SPARK_INTERVAL_TICKS := 6
## Enough vertices for dents to read without turning armour into a mesh budget.
const DENT_SUBDIVISIONS := 12

var damage: float = 0.0
var broken: bool = false

var _spark_cooldown: int = 0

var _joint: Generic6DOFJoint3D
var _material: ShaderMaterial

func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	_joint = $Joint
	contact_monitor = true
	max_contacts_reported = 8

	# Each panel dents independently, so it needs its own material instead of the
	# shared one every instance would otherwise point at.
	var mesh_node := $Mesh as MeshInstance3D
	var source := mesh_node.get_active_material(0) as ShaderMaterial
	if source != null:
		_material = source.duplicate()
		mesh_node.material_override = _material

func _rebuild() -> void:
	if not is_inside_tree():
		return
	var mesh_node := get_node_or_null("Mesh") as MeshInstance3D
	if mesh_node != null:
		var box := BoxMesh.new()
		box.size = size
		# Subdivided so the dent shader has something to push around. A stock box
		# is eight corners and nothing between them, and displacing that just
		# drags the corners.
		box.subdivide_width = DENT_SUBDIVISIONS
		box.subdivide_height = DENT_SUBDIVISIONS
		box.subdivide_depth = DENT_SUBDIVISIONS
		mesh_node.mesh = box
	var collision := get_node_or_null("Collision") as CollisionShape3D
	if collision != null:
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if broken or Engine.is_editor_hint() or state.step <= 0.0:
		return

	# Total the tick's contact impulses and convert to the force behind them,
	# tracking the hardest single point so sparks land where the hit did.
	var impulse := 0.0
	var worst := 0.0
	var at := global_position
	var normal := Vector3.UP
	for i in state.get_contact_count():
		var magnitude := state.get_contact_impulse(i).length()
		impulse += magnitude
		if magnitude > worst:
			worst = magnitude
			at = state.get_contact_local_position(i)
			normal = state.get_contact_local_normal(i)

	var force := impulse / state.step
	_spark_cooldown = maxi(_spark_cooldown - 1, 0)
	if force <= tolerance:
		return

	damage += (force - tolerance) * state.step
	if _spark_cooldown == 0:
		Sparks.burst(self, at, normal, force)
		_spark_cooldown = SPARK_INTERVAL_TICKS

	if damage >= integrity:
		# Deferred: the solver is mid-step and freeing a joint from inside it is
		# not safe.
		_shear.call_deferred(at)
		return
	_refresh_tint()

func _refresh_tint() -> void:
	var fraction := clampf(damage / maxf(integrity, 0.001), 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("damage", fraction)
	damaged.emit(fraction)

func _shear(at: Vector3) -> void:
	if broken:
		return
	broken = true
	if is_instance_valid(_joint):
		_joint.queue_free()
	_refresh_tint()
	Sparks.burst(self, at, Vector3.UP, tolerance * 3.0)
	broke.emit(self)
