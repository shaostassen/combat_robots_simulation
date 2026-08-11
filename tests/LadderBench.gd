extends SceneTree
## Runs the whole ladder with every bot on AI and reports the bracket.
##
##   godot --headless --path . --script res://tests/LadderBench.gd

const TICK := 1.0 / 120.0

func _initialize() -> void:
	var scene: Node = load("res://scenes/Tournament.tscn").instantiate()
	var ladder := scene as Tournament
	# Connected before the scene enters the tree. Deferring the opening bout buys
	# one frame, which is not enough for a listener that only subscribes after
	# awaiting one -- the first fight would go unannounced.
	ladder.bout_started.connect(func(l: String, r: String) -> void:
		print("  %s: %s vs %s" % [ladder.round_name(), l, r]))
	root.add_child(scene)
	await process_frame

	print("Godot %s | %d Hz | %s" % [Engine.get_version_info().string,
		Engine.physics_ticks_per_second,
		ProjectSettings.get_setting("physics/3d/physics_engine")])
	print("")
	print("[ladder] %s" % " · ".join(ladder.seeding))
	print("")
	var elapsed := 0.0
	while ladder.champion == "" and elapsed < 600.0:
		await process_frame
		elapsed += TICK

	print("")
	print("[results]")
	for line: String in ladder.results:
		print("  %s" % line)
	print("")
	print("  decided by         %s" % _reasons(ladder))
	print("  bouts fought       %d" % ladder.bout_index)
	print("  champion           %s" % (ladder.champion if ladder.champion != "" else "NONE"))
	var fought := true
	for line: String in ladder.results:
		if "time limit" in line:
			fought = false
	print("  verdict            %s" % ("ladder completed"
		if ladder.champion != "" and ladder.bout_index == 3
		else "INCOMPLETE -- expected 3 bouts and a champion"))
	print("  fight quality      %s" % ("decisive" if fought
		else "every bout went to the judges -- check the AIs are actually engaging"))
	quit()

func _reasons(ladder: Tournament) -> String:
	var seen: Array[String] = []
	for line: String in ladder.results:
		var reason: String = line.split(" by ")[-1]
		if reason not in seen:
			seen.append(reason)
	return ", ".join(seen)
