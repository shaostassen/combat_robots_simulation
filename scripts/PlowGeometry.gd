@tool
extends CollisionShape3D
## Generates the plow's collision hull *and* its visual mesh from one profile,
## so the thing you see and the thing you hit can never drift apart.
##
## The profile is a wedge in the YZ plane extruded across X, authored in this
## node's own local space: the leading edge lies on z = 0 at y = 0, and the ramp
## rises toward +y as it runs back toward +z. Position the node so that edge
## sits a few millimetres above the floor -- for a wedge, that clearance is the
## whole ballgame, so it is the first number to tune and the reason this is a
## real collider instead of decoration.

const MESH_CHILD := "Mesh"

@export var width: float = 1.2:
	set(value):
		width = value
		_rebuild()
## Horizontal run from leading edge to the chassis face.
@export var run: float = 0.65:
	set(value):
		run = value
		_rebuild()
## Height gained over that run. rise/run sets the attack angle; ~25 degrees is
## aggressive enough to lift a wheel without stalling on the approach.
@export var rise: float = 0.30:
	set(value):
		rise = value
		_rebuild()
## Ground-down flat at the leading edge. A mathematically sharp edge is a
## degenerate hull, and a few millimetres is what a real plow looks like after
## one match anyway.
@export var edge_thickness: float = 0.006:
	set(value):
		edge_thickness = value
		_rebuild()

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return

	var half_width := width * 0.5
	# Leading edge (z = 0), then the trailing face against the chassis (z = run).
	var edge_bottom_l := Vector3(-half_width, 0.0, 0.0)
	var edge_bottom_r := Vector3(half_width, 0.0, 0.0)
	var edge_top_l := Vector3(-half_width, edge_thickness, 0.0)
	var edge_top_r := Vector3(half_width, edge_thickness, 0.0)
	var back_bottom_l := Vector3(-half_width, 0.0, run)
	var back_bottom_r := Vector3(half_width, 0.0, run)
	var back_top_l := Vector3(-half_width, rise, run)
	var back_top_r := Vector3(half_width, rise, run)

	var hull := ConvexPolygonShape3D.new()
	hull.points = PackedVector3Array([
		edge_bottom_l, edge_bottom_r, edge_top_l, edge_top_r,
		back_bottom_l, back_bottom_r, back_top_l, back_top_r,
	])
	shape = hull

	var mesh_node := get_node_or_null(MESH_CHILD) as MeshInstance3D
	if mesh_node == null:
		return

	var ramp_normal := Vector3(0.0, run, -(rise - edge_thickness)).normalized()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(surface, edge_bottom_l, edge_bottom_r, back_bottom_r, back_bottom_l, Vector3.DOWN)
	_quad(surface, edge_top_l, back_top_l, back_top_r, edge_top_r, ramp_normal)
	_quad(surface, edge_bottom_l, edge_top_l, edge_top_r, edge_bottom_r, Vector3.FORWARD)
	_quad(surface, back_bottom_r, back_top_r, back_top_l, back_bottom_l, Vector3.BACK)
	_quad(surface, edge_bottom_l, back_bottom_l, back_top_l, edge_top_l, Vector3.LEFT)
	_quad(surface, edge_bottom_r, edge_top_r, back_top_r, back_bottom_r, Vector3.RIGHT)
	mesh_node.mesh = surface.commit()

## Emits a quad whose corners are given counter-clockwise as seen from outside.
## Godot treats clockwise winding as front-facing, so the triangles go out with
## the order reversed.
func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		normal: Vector3) -> void:
	for vertex: Vector3 in [a, c, b, a, d, c]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)
