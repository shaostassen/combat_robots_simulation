extends AudioStreamPlayer3D
## Weapon whine, pitched by stored energy.
##
## The readability job: a spinner's threat is invisible once the blade is a blur,
## so the ear carries it. Pitch and volume track blade rate, which means you can
## hear a weapon come up to speed, hear it bog down when it bites, and hear it
## coast back -- the same information the energy readout carries, without having
## to look away from the fight.
##
## The tone is generated rather than loaded so the project stays asset-free: a
## sawtooth-ish stack of harmonics, which is roughly what a loaded brushless
## motor sounds like and far more useful than a pure sine.

## Hz of the generated loop. Playback pitch is scaled from here.
const BASE_HZ := 110.0
const SAMPLE_RATE := 22050

@export var bot_path: NodePath
## Pitch multiplier at full blade rate.
@export var top_pitch: float = 3.2
@export var top_volume_db: float = -6.0

var _bot: SpinnerBot

func _ready() -> void:
	_bot = get_node_or_null(bot_path) as SpinnerBot
	stream = _build_tone()
	volume_db = -80.0
	play()

func _process(_delta: float) -> void:
	if _bot == null:
		return
	# Rate, not energy: energy goes as the square, and a pitch that follows the
	# square drops away to nothing the moment the blade slows. Rate is what the
	# ear expects a motor to do.
	var fraction := clampf(absf(_bot.blade_rate) / maxf(_bot.blade_speed, 1.0), 0.0, 1.0)
	pitch_scale = lerpf(0.35, top_pitch, fraction)
	volume_db = -80.0 if fraction < 0.02 else lerpf(-32.0, top_volume_db, fraction)

## One cycle of a harmonic stack, looped. Building exactly one period at the
## sample rate means the loop point lands on a zero crossing, so it does not
## click every time it wraps.
func _build_tone() -> AudioStreamWAV:
	var frames := int(SAMPLE_RATE / BASE_HZ)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var phase := TAU * float(i) / float(frames)
		var sample := sin(phase) * 0.55
		sample += sin(phase * 2.0) * 0.25
		sample += sin(phase * 3.0) * 0.14
		sample += sin(phase * 5.0) * 0.06
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 30000.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	return wav
