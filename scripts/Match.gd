extends Node
class_name Match
## Match loop: countdown, fight, knockout, result.
##
## The knockout rule is lifted straight from the real sport, and it is the one
## piece of "game logic" here that is still physics: a bot is counted out when
## it is being *commanded* to move and simply is not moving. Nothing tracks
## health, nothing decides a bot is dead. If it can still drive, it is still in
## the fight; if it is pinned, flipped onto its back, or has lost a wheel, the
## count starts on its own.
##
## A bot sitting still on purpose is not immobilised, which is why the rule
## checks the command and not just the speed.

signal phase_changed(phase: Phase)
signal finished(winner: CombatBot, reason: String)

enum Phase { COUNTDOWN, FIGHTING, DECIDED }

@export var bot_paths: Array[NodePath] = []
@export var countdown_seconds: float = 3.0
@export var time_limit: float = 120.0
@export_group("Knockout")
## Speed under which a bot counts as not moving, m/s.
@export var immobile_speed: float = 0.35
## How long it has to stay that way while trying to move.
@export var count_out_seconds: float = 10.0

var phase: Phase = Phase.COUNTDOWN
var clock: float = 0.0
var winner: CombatBot = null
var reason: String = ""

var _bots: Array[CombatBot] = []
var _stalled: Array[float] = []

func _ready() -> void:
	for path in bot_paths:
		var bot := get_node_or_null(path) as CombatBot
		if bot != null:
			_bots.append(bot)
			_stalled.append(0.0)
	clock = countdown_seconds
	_set_bots_live(false)
	phase_changed.emit(phase)

func _physics_process(delta: float) -> void:
	match phase:
		Phase.COUNTDOWN:
			clock -= delta
			if clock <= 0.0:
				clock = time_limit
				phase = Phase.FIGHTING
				_set_bots_live(true)
				phase_changed.emit(phase)
		Phase.FIGHTING:
			clock -= delta
			_check_knockouts(delta)
			if phase == Phase.FIGHTING and clock <= 0.0:
				_decide_on_damage()
		Phase.DECIDED:
			pass

## Seconds each bot has been counted out for, for the HUD.
func count_on(bot: CombatBot) -> float:
	var index := _bots.find(bot)
	return _stalled[index] if index >= 0 else 0.0

func _check_knockouts(delta: float) -> void:
	for i in _bots.size():
		var bot := _bots[i]
		if bot.is_commanded() and bot.linear_velocity.length() < immobile_speed:
			_stalled[i] += delta
		else:
			_stalled[i] = 0.0
		if _stalled[i] >= count_out_seconds:
			_finish(_other_than(bot), "knockout")
			return

## Time-limit fallback: fewest newton-seconds absorbed takes it. Still physics --
## it is the impulse the armour actually banked, not a points table.
func _decide_on_damage() -> void:
	var best: CombatBot = null
	var least := INF
	var tied := false
	for bot in _bots:
		var taken := _damage_taken(bot)
		if is_equal_approx(taken, least):
			tied = true
		elif taken < least:
			least = taken
			best = bot
			tied = false
	_finish(null if tied else best, "time limit")

func _damage_taken(bot: CombatBot) -> float:
	var total := 0.0
	for child in bot.get_children():
		if child is ArmorPanel:
			var panel := child as ArmorPanel
			total += panel.integrity if panel.broken else panel.damage
	return total

func _other_than(bot: CombatBot) -> CombatBot:
	for candidate in _bots:
		if candidate != bot:
			return candidate
	return null

func _finish(won: CombatBot, why: String) -> void:
	phase = Phase.DECIDED
	winner = won
	reason = why
	_set_bots_live(false)
	phase_changed.emit(phase)
	finished.emit(winner, reason)

## Drivers off means the keyboard and the AI both stop issuing commands; the
## bodies stay simulated, so anything already in flight keeps flying.
func _set_bots_live(live: bool) -> void:
	for bot in _bots:
		bot.set_physics_process(live)
		if not live:
			bot.drive(0.0, 0.0, 1.0)
		for child in bot.get_children():
			if child is BotAI:
				child.set_physics_process(live)
