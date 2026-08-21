extends SceneTree
## Headless bench for the arm archetypes.
##
## These two exist to teach impulse and leverage, so that is what gets measured:
## does the stroke actually launch a comparable machine, and does getting under
## the target first matter as much as it should.
##
##   godot --headless --path . --script res://tests/ArmBench.gd

const TICK := 1.0 / 120.0

var _scene: Node
var _bot: ArmBot
var _target: CombatBot
var _peak_pitch: float = 0.0

func _initialize() -> void:
	for kind: String in ["FlipperBot", "HammerBot"]:
		await _load(kind)
		await _bench(kind)
	quit()

func _load(kind: String) -> void:
	if _scene != null:
		_scene.free()
	_scene = Node3D.new()
	root.add_child(_scene)
	_scene.add_child(load("res://scenes/Arena.tscn").instantiate())
	_bot = load("res://scenes/%s.tscn" % kind).instantiate()
	_bot.name = kind
	_bot.player_controlled = false
	_scene.add_child(_bot)
	# The victim is a wedge: comparable mass, and the archetype these are
	# supposed to be able to answer.
	_target = load("res://scenes/WedgeBot.tscn").instantiate()
	_target.name = "Victim"
	_target.player_controlled = false
	_scene.add_child(_target)
	await process_frame

func _settle(ticks: int) -> void:
	for _i in ticks:
		_bot.drive(0.0, 0.0, TICK)
		_bot.drive_arm(TICK)
		_target.drive(0.0, 0.0, TICK)
		await process_frame

func _bench(kind: String) -> void:
	print("[%s]" % kind)
	print("  arm rests at       %.0f deg, strokes to %.0f deg"
		% [_bot.rest_angle, _bot.fired_angle])

	# 1. Fire into thin air. Establishes the stroke works and shows the recoil
	#    the bot puts through its own chassis.
	_bot.reset_to(Transform3D(Basis(), Vector3(0.0, 0.35, 4.0)))
	_target.reset_to(Transform3D(Basis(), Vector3(8.0, 0.35, 8.0)))
	await _settle(180)
	var start_angle := _bot.arm_angle()
	var self_lift := 0.0
	var base_y := _bot.global_position.y
	_peak_pitch = 0.0
	_bot.fire()
	# Peak travel, not the angle a second later -- by then the arm has fired,
	# reset and is sitting back at rest, which reads as no stroke at all.
	var extreme := start_angle
	for _i in 120:
		_bot.drive(0.0, 0.0, TICK)
		_bot.drive_arm(TICK)
		await process_frame
		if absf(_bot.arm_angle() - start_angle) > absf(extreme - start_angle):
			extreme = _bot.arm_angle()
		self_lift = maxf(self_lift, _bot.global_position.y - base_y)
		# Rearing up is the hammer's whole look; going over is losing the bout.
		# Peak pitch says which one happened, and the settle says whether it came
		# back down on its wheels.
		_peak_pitch = maxf(_peak_pitch, rad_to_deg(_bot.global_basis.get_euler().x))
	print("  dry stroke         %.0f -> %.0f deg (target %.0f)"
		% [start_angle, extreme, _bot.fired_angle])
	print("  own nose lifted    %.0f mm (its own recoil)" % (self_lift * 1000.0))
	await _settle(180)
	var settled := rad_to_deg(_bot.global_basis.get_euler().x)
	print("  reared to          %.0f deg, settled at %.0f deg%s"
		% [_peak_pitch, settled,
			"   WENT OVER" if absf(settled) > 60.0 else ""])

	# 2. Fire with the victim sitting on the arm -- the shot the archetype is for.
	await _reload()
	var perched := _bot.global_position + (-_bot.global_basis.z) * 1.0
	perched.y = 0.35
	_target.reset_to(Transform3D(Basis(), perched))
	await _settle(150)
	var victim_start := _target.global_position
	var launched := 0.0
	var tumble := 0.0
	var speed := 0.0
	_bot.fire()
	for _i in 300:
		_bot.drive(0.0, 0.0, TICK)
		_bot.drive_arm(TICK)
		_target.drive(0.0, 0.0, TICK)
		await process_frame
		launched = maxf(launched, _target.global_position.y - victim_start.y)
		tumble = maxf(tumble, rad_to_deg(_target.angular_velocity.length()))
		speed = maxf(speed, _target.linear_velocity.length())
	print("  vs 54 kg wedge     launched %.0f mm, %.2f m/s, tumbling %.0f deg/s"
		% [launched * 1000.0, speed, tumble])
	print("  victim ended       %s" % ("INVERTED" if _target.global_basis.y.y < 0.0
		else "%.0f deg off level" % rad_to_deg(acos(clampf(
			_target.global_basis.y.dot(Vector3.UP), -1.0, 1.0)))))
	print("  thrown             %.2f m" % victim_start.distance_to(_target.global_position))
	# A hammer drives down rather than throwing, so launch height understates it
	# badly. What it does is dent armour, which is what this actually measures.
	print("  armour damage      %.1f N·s%s" % [_damage(_target), _shorn(_target)])

	# 3. The reload is the archetype's real cost: one shot, then nothing. Timed
	#    from the trigger, so it has to be measured around a fresh stroke rather
	#    than after one that has already finished recharging.
	await _reload()
	var waited := 0.0
	_bot.fire()
	while not _bot.arm_ready() and waited < 12.0:
		_bot.drive(0.0, 0.0, TICK)
		_bot.drive_arm(TICK)
		await process_frame
		waited += TICK
	print("  cycle time         %.2f s from trigger to ready again" % waited)
	print("")

func _damage(bot: CombatBot) -> float:
	var total := 0.0
	for child in bot.get_children():
		if child is ArmorPanel:
			total += (child as ArmorPanel).damage
	return total

func _shorn(bot: CombatBot) -> String:
	for child in bot.get_children():
		if child is ArmorPanel and (child as ArmorPanel).broken:
			return "   %s SHEARED" % child.name
	return ""

func _reload() -> void:
	var waited := 0.0
	while not _bot.arm_ready() and waited < 8.0:
		_bot.drive(0.0, 0.0, TICK)
		_bot.drive_arm(TICK)
		await process_frame
		waited += TICK
