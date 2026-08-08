extends SceneTree
## Headless match bench: plays a full match with the AI driving both bots and
## checks that it actually reaches a result.
##
## M3's success criterion is "a stranger plays a full match unaided", and the
## failure modes that would break that are not subtle ones -- a match that never
## ends, an AI that drives into a wall and stays there, a knockout that fires on
## a bot that is plainly still fighting. All of those are visible from outside.
##
##   godot --headless --path . --script res://tests/MatchBench.gd

const TICK := 1.0 / 120.0

func _initialize() -> void:
	var scene: Node = load("res://scenes/Match.tscn").instantiate()
	root.add_child(scene)
	await process_frame

	var loop := scene.get_node("MatchLoop") as Match
	var wedge := scene.get_node("Wedge") as CombatBot
	var spinner := scene.get_node("Spinner") as SpinnerBot

	# Give the player's bot an AI too, so the match can be played end to end
	# without a keyboard. Same driver the opponent uses.
	wedge.player_controlled = false
	var ai := BotAI.new()
	ai.name = "AI"
	ai.enemy_path = NodePath("../../Spinner")
	wedge.add_child(ai)
	ai.set_physics_process(loop.phase == Match.Phase.FIGHTING)

	print("Godot %s | %d Hz | %s" % [Engine.get_version_info().string,
		Engine.physics_ticks_per_second,
		ProjectSettings.get_setting("physics/3d/physics_engine")])
	print("")
	print("[match] countdown %.0fs, limit %.0fs, count-out %.0fs under %.2f m/s" % [
		loop.countdown_seconds, loop.time_limit,
		loop.count_out_seconds, loop.immobile_speed])

	# Seed with the phase already set in _ready, which fired before this connect.
	var phases: Array[String] = ["COUNTDOWN"]
	loop.phase_changed.connect(func(p: Match.Phase) -> void:
		phases.append(["COUNTDOWN", "FIGHTING", "DECIDED"][p]))

	var elapsed := 0.0
	var closest := INF
	var spinner_hits := 0
	var was_charged := false
	var wedge_travel := 0.0
	var last_wedge := wedge.global_position

	while loop.phase != Match.Phase.DECIDED and elapsed < 200.0:
		await process_frame
		elapsed += TICK
		closest = minf(closest, wedge.global_position.distance_to(spinner.global_position))
		wedge_travel += last_wedge.distance_to(wedge.global_position)
		last_wedge = wedge.global_position
		var charged := spinner.blade_energy > 0.6 * spinner.full_energy()
		if was_charged and not charged:
			spinner_hits += 1  # blade lost most of its energy: it bit something
		was_charged = charged

	print("")
	print("[result]")
	print("  phases seen        %s" % " -> ".join(phases))
	print("  match length       %.1f s" % elapsed)
	print("  outcome            %s by %s" % [
		loop.winner.name if loop.winner != null else "DRAW", loop.reason])
	print("")
	print("[did the fight actually happen]")
	print("  closest approach   %.2f m" % closest)
	print("  wedge drove        %.1f m" % wedge_travel)
	print("  blade bit hard     %d times" % spinner_hits)
	print("  damage taken       wedge %.0f N·s, spinner %.0f N·s"
		% [_damage(wedge), _damage(spinner)])
	print("  panels shorn       wedge %d, spinner %d" % [_shorn(wedge), _shorn(spinner)])
	print("")
	var verdict := "reached a result"
	if elapsed >= 200.0:
		verdict = "NEVER ENDED"
	elif wedge_travel < 5.0:
		verdict = "SUSPECT -- a bot barely moved"
	print("  verdict            %s" % verdict)
	quit()

func _damage(bot: CombatBot) -> float:
	var total := 0.0
	for child in bot.get_children():
		if child is ArmorPanel:
			var panel := child as ArmorPanel
			total += panel.integrity if panel.broken else panel.damage
	return total

func _shorn(bot: CombatBot) -> int:
	var count := 0
	for child in bot.get_children():
		if child is ArmorPanel and (child as ArmorPanel).broken:
			count += 1
	return count
