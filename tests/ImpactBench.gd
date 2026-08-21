extends SceneTree
## What each weapon actually delivers into armour.
##
## The other benches measure whether a weapon moves its target. This one
## measures whether it HURTS it, which is a different question and the one the
## damage model answers: a panel shrugs off everything under `tolerance`, so a
## weapon that launches a bot across the arena can still, quite correctly, leave
## its armour untouched.
##
## Every archetype is driven into the same victim's panel and the panels are
## asked what they felt. Reading peak force rather than only banked damage is
## what makes a miss distinguishable from a graze and a graze from a near miss.
##
##   godot --headless --path . --script res://tests/ImpactBench.gd

const TICK := 1.0 / 120.0

var _scene: Node
var _attacker: CombatBot
var _victim: CombatBot

func _initialize() -> void:
	print("\nGodot %s | %d Hz | %s" % [
		Engine.get_version_info().string,
		Engine.physics_ticks_per_second,
		ProjectSettings.get_setting("physics/3d/physics_engine")])
	print("\nPanel tolerance is the bar every number here is measured against:")
	print("under it a hit does literally nothing.\n")
	for kind: String in ["WedgeBot", "HammerBot", "FlipperBot", "SpinnerBot"]:
		await _load(kind)
		await _bench(kind)
	# Same weapons against a flank. With today's armour layout -- top and rear
	# only -- this measures the shielding, not the armour: there is nothing on
	# the side to hit, and the wheels stand proud of the chassis anyway.
	print("=== SAME WEAPONS, AGAINST THE FLANK ===\n")
	for kind: String in ["WedgeBot", "SpinnerBot"]:
		await _load(kind)
		await _bench_flank(kind)
	quit()

## Attacker charges a victim presented side-on.
func _bench_flank(kind: String) -> void:
	print("[%s vs flank]" % kind)
	_attacker.reset_to(Transform3D(Basis(), Vector3(0.0, 0.35, 6.0)))
	# Victim turned 90 degrees, so its flank faces the charge.
	_victim.reset_to(Transform3D(Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0)),
		Vector3(0.0, 0.35, -0.6)))
	if _attacker is SpinnerBot:
		await _run(600, 0.0, false)
		var spinner := _attacker as SpinnerBot
		print("  blade at contact   %.0f J" % spinner.blade_energy)
	else:
		await _run(60, 0.0, false)
	_reset_panels()
	await _run(300, 1.0, false)
	_report(kind)
	print("")

func _load(kind: String) -> void:
	if _scene != null:
		_scene.free()
	_scene = Node3D.new()
	root.add_child(_scene)
	_scene.add_child(load("res://scenes/Arena.tscn").instantiate())
	_attacker = load("res://scenes/%s.tscn" % kind).instantiate()
	_attacker.name = kind
	_attacker.player_controlled = false
	_scene.add_child(_attacker)
	_victim = load("res://scenes/WedgeBot.tscn").instantiate()
	_victim.name = "Victim"
	_victim.player_controlled = false
	_scene.add_child(_victim)
	await process_frame

func _panels() -> Array[ArmorPanel]:
	var found: Array[ArmorPanel] = []
	for child in _victim.get_children():
		if child is ArmorPanel:
			found.append(child as ArmorPanel)
	return found

func _reset_panels() -> void:
	for panel in _panels():
		panel.peak_force = 0.0

func _report(kind: String) -> void:
	var panels := _panels()
	var hardest := 0.0
	var banked := 0.0
	var shorn := 0
	for panel in panels:
		hardest = maxf(hardest, panel.peak_force)
		banked += panel.damage
		if panel.broken:
			shorn += 1
	var tolerance: float = panels[0].tolerance if not panels.is_empty() else 0.0
	# Where the hit landed on the victim, in its own space: -Z is its nose, +Z
	# its tail, +/-X its flanks, +Y its roof.
	var at := _victim.peak_contact
	var face := "nose" if at.z < -0.35 else ("tail" if at.z > 0.35 else "flank//roof")
	if at.y > 0.16:
		face = "roof"
	elif absf(at.x) > 0.45 and absf(at.z) <= 0.35:
		face = "flank"
	print("  hardest landed at  (%.2f, %.2f, %.2f) -- the %s, at %.0f N"
		% [at.x, at.y, at.z, face, _victim.peak_force])
	var verdict := "nothing touched the armour"
	if hardest > 0.0 and hardest <= tolerance:
		verdict = "under tolerance -- %.0f%% of the way there" % (100.0 * hardest / tolerance)
	elif hardest > tolerance:
		verdict = "over tolerance by %.0f N" % (hardest - tolerance)
	print("  hardest on a panel %.0f N (tolerance %.0f N)" % [hardest, tolerance])
	print("  banked             %.1f N·s   panels shorn %d" % [banked, shorn])
	print("  verdict            %s" % verdict)

## Drives both machines for a while, attacker at full throttle at the victim.
func _run(ticks: int, throttle: float, fire: bool) -> void:
	for i in ticks:
		_attacker.drive(throttle, 0.0, TICK)
		_victim.drive(0.0, 0.0, TICK)
		if _attacker is ArmBot:
			var arm := _attacker as ArmBot
			arm.drive_arm(TICK)
			if fire and i == 0:
				arm.fire()
		if _attacker is SpinnerBot:
			(_attacker as SpinnerBot).spin_weapon(true, TICK)
		await process_frame

func _bench(kind: String) -> void:
	print("[%s]" % kind)

	if kind == "SpinnerBot":
		# Spin up first: the blade is the weapon, and it is only a weapon once
		# it holds its energy.
		_attacker.reset_to(Transform3D(Basis(), Vector3(0.0, 0.35, 6.0)))
		_victim.reset_to(Transform3D(Basis(), Vector3(0.0, 0.35, -6.0)))
		await _run(600, 0.0, false)
		var spinner := _attacker as SpinnerBot
		print("  blade at contact   %.0f J (%.0f%% charged)"
			% [spinner.blade_energy, 100.0 * spinner.blade_energy / spinner.full_energy()])
		_reset_panels()
		await _run(420, 1.0, false)
		_report(kind)
		print("")
		return

	# Everything else closes from six metres and commits.
	_attacker.reset_to(Transform3D(Basis(), Vector3(0.0, 0.35, 6.0)))
	_victim.reset_to(Transform3D(Basis(), Vector3(0.0, 0.35, -0.4)))
	await _run(60, 0.0, false)
	_reset_panels()

	if _attacker is ArmBot:
		# Close first, then swing with the victim actually in reach -- a stroke
		# fired at six metres measures nothing but the arm's own recoil.
		await _run(150, 1.0, false)
		var arm := _attacker as ArmBot
		var before_pitch := _attacker.global_basis.get_euler().x
		arm.fire()
		await _run(90, 0.3, false)
		print("  own pitch on firing %.1f deg"
			% rad_to_deg(_attacker.global_basis.get_euler().x - before_pitch))
	else:
		await _run(240, 1.0, false)

	_report(kind)
	print("")
