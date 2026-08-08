extends SceneTree
## Headless spinner bench: how long the blade takes to come up, how much energy
## it banks, and what one full-RPM strike actually does.
##
## Energy is the number that matters. It goes as the square of the rate, so the
## difference between a half-spun blade and a full one is not a near miss -- it
## is most of the punch. This bench exists to keep that honest while tuning.
##
##   godot --headless --path . --script res://tests/SpinnerBench.gd

const TICK := 1.0 / 120.0

var _bot: SpinnerBot
var _blade: RigidBody3D

var _scene: Node

func _initialize() -> void:
	await _load_scene()

	print("Godot %s | %d Hz | %s" % [Engine.get_version_info().string,
		Engine.physics_ticks_per_second,
		ProjectSettings.get_setting("physics/3d/physics_engine")])
	print("")
	await _bench_spin_up()
	await _bench_strike()
	await _bench_versus_wedge()
	quit()

func _idle(ticks: int, weapon: bool) -> void:
	for _i in ticks:
		_bot.drive(0.0, 0.0, TICK)
		_bot.spin_weapon(weapon, TICK)
		await process_frame

func _bench_spin_up() -> void:
	_bot.reset_to(Transform3D(Basis(), Vector3(-3.0, 0.35, 6.0)))
	await _idle(120, false)

	var box := (_blade.get_node("Collision") as CollisionShape3D).shape as BoxShape3D
	var inertia: float = _blade.mass * (box.size.y ** 2 + box.size.z ** 2) / 12.0
	print("[blade]")
	print("  mass               %.1f kg" % _blade.mass)
	print("  inertia about spin %.3f kg·m²" % inertia)
	print("  radius             %.2f m" % (box.size.z * 0.5))
	print("")

	var marks := {0.5: -1.0, 0.9: -1.0, 0.99: -1.0}
	var peak := 0.0
	for tick in 900:  # 7.5 s
		_bot.drive(0.0, 0.0, TICK)
		_bot.spin_weapon(true, TICK)
		await process_frame
		peak = maxf(peak, absf(_bot.blade_rate))
		for fraction: float in marks:
			if marks[fraction] < 0.0 and absf(_bot.blade_rate) >= fraction * _bot.blade_speed:
				marks[fraction] = tick * TICK

	print("[spin-up to %.0f rad/s target]" % _bot.blade_speed)
	print("  reached            %.0f rad/s (%.0f RPM, %.0f m/s at tip, %s)"
		% [peak, peak * 60.0 / TAU, peak * 0.25,
			"up-cutting" if _bot.blade_speed_now() > 0.0 else "DOWN-cutting"])
	for fraction: float in [0.5, 0.9, 0.99]:
		print("  %3.0f%% of target      %s" % [fraction * 100.0,
			"%.2f s" % marks[fraction] if marks[fraction] >= 0.0 else "not reached"])
	print("  stored energy      %.0f J" % _bot.blade_energy)
	print("")

	# Cut the motor and watch it coast. A spinner has no brake; the long
	# spin-down is part of the drama and part of the tactical cost of a miss.
	var from := _bot.blade_rate
	var coasted := 0
	while absf(_bot.blade_rate) > 0.5 * absf(from) and coasted < 1800:
		_bot.drive(0.0, 0.0, TICK)
		_bot.spin_weapon(false, TICK)
		await process_frame
		coasted += 1
	print("[coast-down, motor cut]")
	print("  half energy lost   %.2f s" % (coasted * TICK))
	print("")

## Rebuilds the world from scratch. Damage is permanent by design, so any test
## that breaks something has to start from a clean rig or the next one is
## measuring a different machine.
func _load_scene() -> void:
	if _scene != null:
		_scene.free()
	_scene = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_bot = root.get_node("Main/SpinnerBot")
	_blade = _bot.get_node("Blade")
	_bot.set_physics_process(false)
	(root.get_node("Main/WedgeBot") as CombatBot).set_physics_process(false)

func _bench_strike() -> void:
	var dummy := root.get_node("Main/Props/PanelDummy") as RigidBody3D
	var panels: Array[ArmorPanel] = []
	for child in dummy.get_children():
		if child is ArmorPanel:
			panels.append(child)
	var approach := Vector3(dummy.global_position.x, 0.35, dummy.global_position.z)

	for spun: bool in [false, true]:
		await _load_scene()
		dummy = root.get_node("Main/Props/PanelDummy")
		panels.clear()
		for child in dummy.get_children():
			if child is ArmorPanel:
				panels.append(child)
		_bot.reset_to(Transform3D(Basis(), approach + Vector3(0, 0, 5.0)))
		# reset_to leaves the blade turning; the unspun run has to actually stop it.
		_blade.angular_velocity = Vector3.ZERO
		await _idle(30, false)
		if spun:
			# Come up to speed standing still, exactly as a driver would before
			# committing to the charge.
			await _idle(600, true)

		var energy_before := _bot.blade_energy
		var dummy_start := dummy.global_position


		var trough := energy_before
		var airborne := 0.0
		var broke: ArmorPanel = null
		for _i in 300:
			_bot.drive(1.0, 0.0, TICK)
			_bot.spin_weapon(spun, TICK)
			await process_frame

			# The bite is a running minimum, not something gated on the chassis
			# feeling a hit: the impact travels through the blade, which is a
			# separate body, so the chassis may register nothing at all.
			trough = minf(trough, _bot.blade_energy)
			airborne = maxf(airborne, dummy.global_position.y - dummy_start.y)
			for panel in panels:
				if panel.broken and broke == null:
					broke = panel

		var total := 0.0
		for panel in panels:
			total += panel.damage
		print("[charge with blade %s]" % ("at full RPM" if spun else "stopped"))
		print("  energy at contact  %.0f J" % energy_before)
		print("  energy low-water   %.0f J%s" % [trough,
			"" if energy_before < 1.0
			else "  (%.0f%% dumped into the target)"
				% (100.0 * (1.0 - trough / energy_before))])
		print("  target launched    %.0f mm up, %.2f m away"
			% [airborne * 1000.0, dummy_start.distance_to(dummy.global_position)])
		print("  panel damage       %.1f N·s%s"
			% [total, "   %s SHEARED" % broke.name if broke != null else ""])
		print("")

## The M2 headline: spinner versus wedge. The panelled dummy is a controlled test
## rig at 150 kg; this is the matchup the milestone is actually about, against a
## machine of comparable mass that can be sent flying.
func _bench_versus_wedge() -> void:
	var wedge := root.get_node("Main/WedgeBot") as CombatBot
	# Clear lane: the crates sit at x = -4/-6/-8 and the dummies at x = 3/6, so a
	# wedge thrown down the middle has room to actually fly.
	var lane := Vector3(0.0, 0.35, 2.0)
	wedge.reset_to(Transform3D(Basis(), lane))
	_bot.reset_to(Transform3D(Basis(), lane + Vector3(0, 0, 5.0)))
	_blade.angular_velocity = Vector3.ZERO
	await _idle(60, false)
	await _idle(480, true)  # spin up standing still, as a driver would

	var energy_before := _bot.blade_energy
	var wedge_start := wedge.global_position
	var trough := energy_before
	var launch := 0.0
	var recoil := 0.0
	var hurled := 0.0
	var tumble := 0.0
	var fastest := 0.0
	for _i in 300:
		_bot.drive(1.0, 0.0, TICK)
		_bot.spin_weapon(true, TICK)
		wedge.drive(0.0, 0.0, TICK)
		await process_frame
		trough = minf(trough, _bot.blade_energy)
		launch = maxf(launch, wedge.global_position.y - wedge_start.y)
		var forward: float = _bot.linear_velocity.dot(-_bot.global_basis.z)
		fastest = maxf(fastest, forward)
		recoil = maxf(recoil, fastest - forward)
		hurled = maxf(hurled, wedge.linear_velocity.length())
		tumble = maxf(tumble, absf(rad_to_deg(wedge.angular_velocity.length())))

	print("[SPINNER vs WEDGE, full RPM]")
	print("  energy at contact  %.0f J" % energy_before)
	print("  energy low-water   %.0f J (%.0f%% dumped)"
		% [trough, 100.0 * (1.0 - trough / maxf(energy_before, 0.001))])
	print("  wedge launched     %.0f mm up, thrown %.2f m"
		% [launch * 1000.0, wedge_start.distance_to(wedge.global_position)])
	print("  wedge peak speed   %.2f m/s, tumbling %.0f deg/s" % [hurled, tumble])
	print("  wedge left %s"
		% ("INVERTED" if wedge.global_basis.y.y < 0.0 else "on its wheels (%.0f deg off level)"
			% rad_to_deg(acos(clampf(wedge.global_basis.y.dot(Vector3.UP), -1.0, 1.0)))))
	print("  spinner recoil     %.2f m/s of its own speed killed" % recoil)
	print("")
