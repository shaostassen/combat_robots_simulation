extends Node3D
class_name Tournament
## Four-archetype single-elimination ladder.
##
## Owns the arena and spawns each bout into it, rather than reloading a scene
## per fight -- which is what keeps the bracket in memory without a singleton or
## a save file. Bots are freed and rebuilt between bouts, so every fighter comes
## to the line undamaged and a shorn panel never carries over.
##
## The player drives whichever entrant is theirs, for as long as they keep
## winning; once they are out, the rest of the bracket plays itself out.

signal bout_started(left: String, right: String)
signal tournament_finished(champion: String)

const ENTRANTS := {
	"Wedge": "res://scenes/WedgeBot.tscn",
	"Spinner": "res://scenes/SpinnerBot.tscn",
	"Flipper": "res://scenes/FlipperBot.tscn",
	"Hammer": "res://scenes/HammerBot.tscn",
}

## Seeding. Semi-finals are (0 vs 1) and (2 vs 3), then the winners meet.
@export var seeding: Array[String] = ["Wedge", "Spinner", "Flipper", "Hammer"]
## Which entrant the human drives. Empty means a fully simulated ladder.
@export var player_entrant: String = "Wedge"
@export var match_scene_path: NodePath
## Optional; repointed at each bout's player-side fighter.
@export var camera_path: NodePath
@export var spawn_separation: float = 12.0
## Wall-clock pause between bouts, so a result can be read before the next one.
@export var intermission: float = 4.0

var round_index: int = 0
var bout_index: int = 0
var champion: String = ""
var results: Array[String] = []

var _remaining: Array[String] = []
var _next_round: Array[String] = []
var _match: Match
var _camera: ChaseCamera
var _left: CombatBot
var _right: CombatBot
var _round_size: int = 0
var _intermission_left: float = 0.0
var _awaiting: bool = false

func _ready() -> void:
	_match = get_node_or_null(match_scene_path) as Match
	_camera = get_node_or_null(camera_path) as ChaseCamera
	_remaining = seeding.duplicate()
	_round_size = _remaining.size()
	if _match != null:
		_match.finished.connect(_on_bout_finished)
	# Deferred so listeners get a chance to connect first. Emitting the opening
	# bout from _ready means nothing is listening yet and it goes unannounced.
	_start_next_bout.call_deferred()

func _process(delta: float) -> void:
	if not _awaiting:
		return
	_intermission_left -= delta
	if _intermission_left <= 0.0:
		_awaiting = false
		_start_next_bout()

## Name of the bout currently on, for the HUD.
func current_bout() -> String:
	if _left == null or _right == null:
		return ""
	return "%s  vs  %s" % [String(_left.name), String(_right.name)]

func round_name() -> String:
	if champion != "":
		return "Champion"
	# Named from the size of the round when it started. Counting what is left
	# mid-round is wrong the moment a pair has been popped off to fight.
	match _round_size:
		2: return "Final"
		4: return "Semi-final"
		_: return "Round %d" % (round_index + 1)

func _start_next_bout() -> void:
	_clear_fighters()

	if _remaining.size() < 2:
		# Round over. Winners advance; a lone entrant gets a bye.
		if _remaining.size() == 1:
			_next_round.append(_remaining[0])
		_remaining = _next_round.duplicate()
		_next_round.clear()
		_round_size = _remaining.size()
		round_index += 1
		if _remaining.size() <= 1:
			champion = _remaining[0] if _remaining.size() == 1 else "nobody"
			tournament_finished.emit(champion)
			return

	var left_name: String = _remaining.pop_front()
	var right_name: String = _remaining.pop_front()
	_left = _spawn(left_name, spawn_separation * 0.5, 0.0)
	_right = _spawn(right_name, -spawn_separation * 0.5, PI)
	# Drivers are attached only once both fighters exist, since each one's enemy
	# path has to resolve against a node that is already in the tree.
	_attach_driver(_left, _right)
	_attach_driver(_right, _left)
	bout_index += 1
	# Follow the human if they are still in it; otherwise just watch the left seed.
	if _camera != null:
		_camera.set_target(_right if _right.player_controlled else _left)
	bout_started.emit(left_name, right_name)

	if _match != null:
		_match.begin([_left, _right])

## Builds a fighter at one end of the arena, facing down it.
func _spawn(entrant: String, z: float, yaw: float) -> CombatBot:
	var bot := (load(ENTRANTS[entrant]) as PackedScene).instantiate() as CombatBot
	bot.name = entrant
	bot.transform = Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)),
		Vector3(0.0, 0.35, z))
	bot.player_controlled = entrant == player_entrant
	add_child(bot)
	# After add_child: a clash with a not-yet-freed sibling gets silently renamed.
	bot.name = entrant
	return bot

## The human gets the wheel only for their own entrant; everything else is AI.
func _attach_driver(bot: CombatBot, enemy: CombatBot) -> void:
	if bot.player_controlled:
		return
	var ai := BotAI.new()
	ai.name = "AI"
	bot.add_child(ai)
	ai.set_enemy(enemy)

func _clear_fighters() -> void:
	for bot: CombatBot in [_left, _right]:
		if bot != null and is_instance_valid(bot):
			# Detach before freeing so the name is released now rather than at
			# the end of the frame, after the next pair has already been added.
			remove_child(bot)
			bot.queue_free()
	_left = null
	_right = null

func _on_bout_finished(winner: CombatBot, reason: String) -> void:
	var winner_name: String = String(winner.name) if winner != null else ""
	if winner_name == "":
		# A draw still has to advance somebody, or the bracket stalls. The left
		# seed takes it, which is what a seeded bracket is for.
		winner_name = String(_left.name) if _left != null else ""
	var beaten: String = String(_right.name) if winner_name == String(_left.name) \
		else String(_left.name)
	results.append("%s beat %s by %s" % [winner_name, beaten, reason])
	_next_round.append(winner_name)
	_awaiting = true
	_intermission_left = intermission
