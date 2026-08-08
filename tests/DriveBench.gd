extends SceneTree
## Headless drivetrain bench. Loads the real Main scene, drives the real bot
## through scripted manoeuvres, and prints the numbers that define drive feel.
##
## Drive quality stops being a matter of opinion once you can measure it: top
## speed, time to reach it, stopping distance, pivot rate, wheel slip, and
## whether the plow edge actually clears the floor are all just numbers. Run
## this before and after touching anything in the drivetrain.
##
##   godot --headless --path . --script res://tests/DriveBench.gd

const TICK := 1.0 / 120.0
## Long clear lane down the middle of the arena; the targets live off to the sides.
const LANE_START := Vector3(0.0, 0.35, 9.0)
## The bot sweeps a ~1.7 m radius once the plow is counted, so a pivot has to be
## staged well clear of the walls -- run it up at the lane head and it spends the
## test grinding its plow into the barrier instead of rotating.
const PIVOT_ORIGIN := Vector3(0.0, 0.35, 0.0)

var _bot: RigidBody3D
var _plow: CollisionShape3D
var _throttle := 0.0
var _turn := 0.0

func _initialize() -> void:
	root.add_child(load("res://scenes/Sandbox.tscn").instantiate())
	# Nodes enter the tree and run _ready deferred, so nothing below may touch
	# them until a frame has actually gone by.
	await process_frame
	_bot = root.get_node("Sandbox/WedgeBot")
	_plow = _bot.get_node("Plow")
	# Take input out of the loop: the bench commands the drivetrain directly so
	# results do not depend on a keyboard that headless mode does not have.
	_bot.set_physics_process(false)

	print("Godot %s | %d Hz | %s" % [
		Engine.get_version_info().string,
		Engine.physics_ticks_per_second,
		ProjectSettings.get_setting("physics/3d/physics_engine"),
	])
	print("")
	_report_static()
	await _bench_straight_line()
	await _bench_pivot()
	await _bench_plow()
	await _bench_damage()
	quit()

func _report_static() -> void:
	var total := _bot.mass
	for child in _bot.get_children():
		if child is RigidBody3D:
			total += (child as RigidBody3D).mass
	var hull := _plow.shape as ConvexPolygonShape3D
	print("[static]")
	print("  total mass         %.1f kg (chassis %.1f + wheels)" % [total, _bot.mass])
	print("  centre of mass     %.0f mm above ground plane"
		% ((_bot.center_of_mass.y - _ground_plane_y()) * 1000.0))
	print("  plow collider      %s, %d hull points"
		% ["present" if hull != null else "MISSING", hull.points.size() if hull else 0])
	print("  plow attack angle  %.1f deg" % rad_to_deg(atan2(_plow.rise, _plow.run)))
	print("")

## Local y of the plane the wheels rest on, derived from the front wheel rather
## than hard-coded, so it stays honest if the geometry changes.
func _ground_plane_y() -> float:
	var wheel := _bot.get_node("FrontLeftWheel") as RigidBody3D
	var radius := (wheel.get_node("WheelCollision").shape as CylinderShape3D).radius
	return wheel.position.y - radius

## Goes through the bot's public command path, so mixing, ramping and the
## torque curve are all the ones the player actually gets.
func _drive() -> void:
	_bot.drive(_throttle, _turn, TICK)

func _run(ticks: int) -> void:
	for _i in ticks:
		_drive()
		await process_frame

func _forward_speed() -> float:
	return _bot.linear_velocity.dot(-_bot.global_basis.z)

## Places the bot somewhere, facing down the lane, and lets it settle.
func _stage(origin: Vector3 = LANE_START) -> void:
	_throttle = 0.0
	_turn = 0.0
	_bot.reset_to(Transform3D(Basis(), origin))
	await _run(120)

func _bench_straight_line() -> void:
	await _stage()
	var start := _bot.global_position
	_throttle = 1.0

	var top := 0.0
	var peak_slip := 0.0
	var trace: Array[float] = []
	for _i in 240:  # 2 s -- long enough to top out, short enough to leave
			# braking room before the far wall
		_drive()
		await process_frame
		top = maxf(top, _forward_speed())
		peak_slip = maxf(peak_slip, absf(_bot.slip_left))
		trace.append(_forward_speed())

	# Time to 90% of the speed actually achieved -- 90% of the theoretical free
	# speed is meaningless on a drivetrain that is deliberately traction-limited.
	var to_90 := -1.0
	for i in trace.size():
		if trace[i] >= 0.9 * top:
			to_90 = i * TICK
			break

	print("[straight line, 2 s full throttle]")
	print("  top speed          %.2f m/s (%.1f km/h)" % [top, top * 3.6])
	print("  free-speed ceiling %.2f m/s" % (_bot.free_speed * _bot.wheel_radius))
	print("  time to 90%% of top %s" % ("%.2f s" % to_90 if to_90 >= 0.0 else "not reached"))
	print("  peak wheel slip    %.2f m/s" % peak_slip)
	print("  distance           %.2f m" % start.distance_to(_bot.global_position))
	print("")

	# Roll straight into the brake test while there is still speed on the clock.
	var entry := _forward_speed()
	var brake_start := _bot.global_position
	_throttle = 0.0
	var ticks := 0
	var max_pitch := 0.0
	while absf(_forward_speed()) > 0.05 and ticks < 600:
		_drive()
		await process_frame
		ticks += 1
		max_pitch = maxf(max_pitch, -rad_to_deg(asin(clampf(-_bot.global_basis.z.y, -1.0, 1.0))))
	print("[brake from speed]")
	print("  entry speed        %.2f m/s" % entry)
	print("  stopping distance  %.2f m" % brake_start.distance_to(_bot.global_position))
	var distance := brake_start.distance_to(_bot.global_position)
	print("  stopping time      %.2f s" % (ticks * TICK))
	print("  peak nose-down     %.1f deg" % max_pitch)
	# Sanity rail: tyres cannot pull much past 1 g, so anything well above that
	# means the bot hit something and the run is contaminated, not that braking
	# suddenly got good.
	print("  implied decel      %.1f m/s^2 (%.2f g)%s" % [
		entry * entry / maxf(2.0 * distance, 0.001),
		entry * entry / maxf(2.0 * distance, 0.001) / 9.8,
		"  <-- SUSPECT, check for an obstacle" if entry * entry / maxf(2.0 * distance, 0.001) > 14.0 else ""])
	print("")

func _bench_pivot() -> void:
	await _stage(PIVOT_ORIGIN)
	var start := _bot.global_position
	_throttle = 0.0
	_turn = 1.0
	var peak_yaw := 0.0
	var swept := 0.0
	for _i in 360:  # 3 s
		_drive()
		await process_frame
		var yaw: float = rad_to_deg(_bot.angular_velocity.dot(_bot.global_basis.y))
		peak_yaw = maxf(peak_yaw, absf(yaw))
		swept += absf(yaw) * TICK
	print("[pivot in place, 3 s full lock]")
	print("  peak yaw rate      %.0f deg/s" % peak_yaw)
	print("  swept              %.0f deg (%.2f s per 360)"
		% [swept, 360.0 / maxf(swept / 3.0, 0.001)])
	print("  drift from start   %.2f m" % start.distance_to(_bot.global_position))
	print("")

func _bench_plow() -> void:
	await _stage()

	# Lowest point of the plow hull in world space, with the bot settled on its
	# wheels. If this is not a clear margin above the floor the wedge scrapes,
	# which costs traction everywhere and kills the pivot.
	var hull := _plow.shape as ConvexPolygonShape3D
	var lowest := INF
	for point in hull.points:
		lowest = minf(lowest, (_plow.global_transform * point).y)
	print("[plow at rest]")
	print("  edge height        %.1f mm above floor" % (lowest * 1000.0))
	print("  chassis pitch      %.2f deg"
		% rad_to_deg(asin(clampf(-_bot.global_basis.z.y, -1.0, 1.0))))
	print("")

	for crate_name: String in ["CrateLight", "CrateMedium", "CrateHeavy"]:
		await _charge_crate(crate_name)
	await _charge_crate("DummyTarget")

## Lines the bot up three metres behind a crate and drives through it.
func _charge_crate(crate_name: String) -> void:
	var crate := root.get_node("Sandbox/Props/" + crate_name) as RigidBody3D
	_throttle = 0.0
	_turn = 0.0
	_bot.reset_to(Transform3D(Basis(), crate.global_position
		+ Vector3(0.0, 0.35 - crate.global_position.y, 3.0)))
	await _run(60)

	var crate_start := crate.global_position
	var rest_y := crate.global_position.y
	_throttle = 1.0
	var lift := 0.0
	var impulse := 0.0
	for _i in 240:  # 2 s
		_drive()
		await process_frame
		lift = maxf(lift, crate.global_position.y - rest_y)
		impulse = maxf(impulse, _bot.peak_force)

	var tilt := rad_to_deg(acos(clampf(crate.global_basis.y.dot(Vector3.UP), -1.0, 1.0)))
	print("[plow vs %s, %.0f kg]" % [crate_name, crate.mass])
	print("  lifted             %.0f mm" % (lift * 1000.0))
	print("  displaced          %.2f m" % crate_start.distance_to(crate.global_position))
	print("  tilted             %.0f deg off level" % tilt)
	print("  peak contact force %.0f N" % impulse)
	print("")

## M1: the damage model. Two things have to hold at once -- a shove must do
## nothing at all, and a real strike must eventually shear a panel off. A model
## that only satisfies one of those is not a damage model, it is a threshold.
##
## Every panel is tracked rather than a nominated one, so the result does not
## depend on guessing which face the bot happens to strike.
func _bench_damage() -> void:
	var dummy := root.get_node("Sandbox/Props/PanelDummy") as RigidBody3D
	var panels: Array[ArmorPanel] = []
	for child in dummy.get_children():
		if child is ArmorPanel:
			panels.append(child)
	var approach := Vector3(dummy.global_position.x, 0.35, dummy.global_position.z)

	_throttle = 0.0
	_turn = 0.0
	_bot.reset_to(Transform3D(Basis(), approach + Vector3(0, 0, 2.2)))
	await _run(60)

	# 1. Lean on it at quarter throttle. Nothing should register anywhere.
	for _i in 300:  # 2.5 s of steady pushing
		_bot.drive(0.25, 0.0, TICK)
		await process_frame
	print("[damage: 2.5 s shove at quarter throttle]")
	print("  total damage       %.1f N·s across %d panels" % [_total(panels), panels.size()])
	print("  verdict            %s"
		% ("shrugged it off" if _total(panels) == 0.0 else "LEAKING -- tolerance too low"))
	print("")

	# 2. Now ram it from six metres and count what it takes.
	print("[damage: full-speed rams, tolerance %.0f N / integrity %.0f N·s]"
		% [panels[0].tolerance, panels[0].integrity])
	var hits := 0
	var broken: ArmorPanel = null
	while hits < 8 and broken == null:
		hits += 1
		var before := _total(panels)
		_bot.reset_to(Transform3D(Basis(), approach + Vector3(0, 0, 6.0)))
		_throttle = 0.0
		await _run(30)
		var impact := 0.0
		for _i in 240:
			_bot.drive(1.0, 0.0, TICK)
			await process_frame
			impact = maxf(impact, _bot.peak_force)
			for panel in panels:
				if panel.broken and broken == null:
					broken = panel
			if broken != null:
				break
		print("  ram %d: hit %.0f N -> banked +%.0f N·s, total %.0f%s"
			% [hits, impact, _total(panels) - before, _total(panels),
				"   %s SHEARED" % broken.name if broken != null else ""])
	print("")

	if broken == null:
		print("  no panel broke in %d rams -- integrity is out of reach" % hits)
		for panel in panels:
			print("    %-12s %.0f N·s" % [panel.name, panel.damage])
		return

	# 3. A detached panel has to behave like debris: still simulated, still
	# colliding, no longer welded.
	var settle_start := broken.global_position
	for _i in 120:
		_bot.drive(0.0, 0.0, TICK)
		await process_frame
	print("[debris: %s]" % broken.name)
	print("  still in tree      %s" % ("yes" if is_instance_valid(broken) else "no -- it was freed"))
	print("  weld gone          %s" % ("yes" if broken.get_node_or_null("Joint") == null else "no"))
	print("  travelled after    %.2f m in 1 s" % settle_start.distance_to(broken.global_position))
	print("  came to rest       %.0f deg off level"
		% rad_to_deg(acos(clampf(broken.global_basis.y.dot(Vector3.UP), -1.0, 1.0))))
	print("")

func _total(panels: Array[ArmorPanel]) -> float:
	var sum := 0.0
	for panel in panels:
		sum += panel.damage
	return sum
