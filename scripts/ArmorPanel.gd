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
## The 140 N / 700 N figures this was originally calibrated from were read off
## the ATTACKER's chassis, not off the panel, and the two differ by more than an
## order of magnitude. Re-measured properly (`tests/ImpactBench.gd`, which reads
## `peak_force` on the panel itself):
##
##   full-speed wedge ram, free bot     attacker 426-453 N, armour    0 N
##   spinner at 4302 J, free bot                             armour   69 N
##   wedge shove, bot pinned on a wall                       armour    5 N
##   spinner at 4302 J, bot pinned on a wall                 armour 1779 N
##
## 250 N is right where it belongs: a shove on a cornered machine is 5 N and a
## full-RPM strike on the same machine is 1779 N, so the threshold separates them
## by a wide margin in both directions. What decides damage is not the weapon
## alone but whether the target can retreat -- a free 54 kg bot absorbs the blade
## by being thrown 791 mm into the air, and a cornered one has to absorb it
## through its armour. That is the sport, and it falls out of the physics rather
## than being written down anywhere.
@export var tolerance: float = 250.0
## Banked over-tolerance impulse (N*s) the weld survives before it lets go.
##
## The "roughly 4.5 N*s per ram, so three or four solid hits" this once claimed
## was never measured on a panel: a wedge ram banks nothing at all, because the
## plow passes UNDER the armour and drives into the core. The intent in the same
## breath was right, and is what actually happens -- a plow is a ramp, it turns
## an impact into lift and shove rather than a square blow, so it should struggle
## to shear armour. It does not struggle; it never touches it.
@export var integrity: float = 14.0

## A collision spans dozens of ticks; without a floor on the gap between bursts
## a single hit would spawn hundreds of them.
const SPARK_INTERVAL_TICKS := 6
## Enough vertices for dents to read without turning armour into a mesh budget.
const DENT_SUBDIVISIONS := 12

var damage: float = 0.0
var broken: bool = false
## Hardest contact force this panel has felt, in newtons.
##
## Recorded before the tolerance test, not after, which is the entire point: a
## panel that banks no damage looks identical to one nothing ever touched, and
## the two need very different fixes. This says whether a weapon missed, grazed
## at 90 N, or landed at 240 N and fell just short of the 250 N it needed.
var peak_force: float = 0.0

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
	peak_force = maxf(peak_force, force)
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
