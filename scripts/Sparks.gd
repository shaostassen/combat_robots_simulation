extends Node
class_name Sparks
## Impact sparks, scaled by the impulse that caused them.
##
## The readability job here matters as much as the look: burst size is a direct
## readout of how hard a hit landed, so a spectator who knows nothing about the
## game can still tell a glancing scrape from a solid strike.

const BURST_SCENE: PackedScene = preload("res://scenes/SparkBurst.tscn")

## Below this the hit is not worth drawing; above it, particle count climbs with
## the force behind it until it saturates, so a huge strike cannot flood a frame.
const MIN_FORCE := 150.0
const MAX_PARTICLES := 96

## Emits a burst in [param context]'s world, at a world-space [param position],
## thrown back along [param normal], sized by the contact [param force] in
## newtons. Bursts free themselves once done, so the caller can fire and forget.
static func burst(context: Node3D, position: Vector3, normal: Vector3,
		force: float) -> void:
	if force < MIN_FORCE or not context.is_inside_tree():
		return

	var node := BURST_SCENE.instantiate() as GPUParticles3D
	# Parented to the scene root rather than to the struck body: sparks should
	# keep flying on their own arc, not ride along with whatever spawned them --
	# and they must outlive a panel that gets freed.
	var tree := context.get_tree()
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(node)
	node.global_position = position
	if normal.length_squared() > 0.001:
		# Floor and ceiling hits give a normal parallel to UP, which makes
		# look_at degenerate; any perpendicular reference will do for a
		# radially symmetric burst.
		var reference := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		node.look_at(position + normal, reference, true)

	node.amount = clampi(int(force / 25.0), 8, MAX_PARTICLES)
	node.emitting = true
	node.finished.connect(node.queue_free)
