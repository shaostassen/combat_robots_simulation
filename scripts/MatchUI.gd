extends CanvasLayer
## Match banner: countdown, the fight clock, the count on a stalled bot, and the
## result. Deliberately sparse -- the fight is the thing worth looking at.

@export var match_path: NodePath
@export var player_path: NodePath

@onready var _banner: Label = $Centre/Banner
@onready var _status: Label = $Centre/Status
@onready var _hint: Label = $Centre/Hint

var _match: Match
var _player: CombatBot

func _ready() -> void:
	_match = get_node_or_null(match_path) as Match
	_player = get_node_or_null(player_path) as CombatBot
	_hint.text = ""

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _match != null and _match.phase == Match.Phase.DECIDED \
			and key.physical_keycode == KEY_ENTER:
		# Panels do not un-shear, so a rematch is a genuine reload rather than a
		# reposition -- otherwise round two starts against a half-wrecked bot.
		get_tree().reload_current_scene()

func _process(_delta: float) -> void:
	if _match == null:
		return
	match _match.phase:
		Match.Phase.COUNTDOWN:
			_banner.text = str(ceili(_match.clock))
			_status.text = "WASD to drive" + \
				("   ·   SPACE spins the weapon" if _player is SpinnerBot else "")
			_hint.text = ""
		Match.Phase.FIGHTING:
			_banner.text = ""
			_status.text = "%d:%02d" % [int(_match.clock) / 60, int(_match.clock) % 60]
			_hint.text = _count_text()
		Match.Phase.DECIDED:
			if _match.winner == null:
				_banner.text = "DRAW"
			else:
				_banner.text = "WINNER: %s" % _match.winner.name
			_status.text = "by %s" % _match.reason
			_hint.text = "ENTER for a rematch"

## The count is the tensest number in the sport -- show it once it is real, for
## whichever bot is on it.
func _count_text() -> String:
	for path in _match.bot_paths:
		var bot := _match.get_node_or_null(path) as CombatBot
		if bot == null:
			continue
		var counted := _match.count_on(bot)
		if counted >= 3.0:
			return "%s counted out in %d..." % [bot.name,
				ceili(_match.count_out_seconds - counted)]
	return ""
