class_name VehicleEngineAudio
extends Node
## Dos capas por motor: ralentí y escape bajo carga, con RPM suavizadas.
var idle: AudioStreamPlayer
var load_sound: AudioStreamPlayer
var turbo_sound: AudioStreamPlayer
var turbo_release: AudioStreamPlayer
var rpm := 0.0
var _load_mix := 0.0
var _time := 0.0
var _vehicle := 0
var _turbo_mix := 0.0
var _was_turbo := false
const PITCH_RANGES := [.72,.94,.62,.84,.64,.58]

func configure(index: int) -> void:
	_vehicle = index
	rpm = 0.0
	_load_mix = 0.0
	_time = 0.0
	_turbo_mix = 0.0
	_was_turbo = false
	if idle == null:
		idle = AudioStreamPlayer.new()
		idle.name = "Idle"
		add_child(idle)
		load_sound = AudioStreamPlayer.new()
		load_sound.name = "ExhaustLoad"
		add_child(load_sound)
		turbo_sound = AudioStreamPlayer.new()
		turbo_sound.name = "TurboLoop"
		add_child(turbo_sound)
		turbo_release = AudioStreamPlayer.new()
		turbo_release.name = "TurboRelease"
		add_child(turbo_release)
	idle.stop()
	load_sound.stop()
	turbo_sound.stop()
	turbo_release.stop()
	var key: String = VehicleCatalog.entry(index).id
	idle.stream = _loop("res://audio/engines/%s_idle.wav" % key)
	load_sound.stream = _loop("res://audio/engines/%s_load.wav" % key)
	turbo_sound.stream = _loop("res://audio/engines/%s_turbo.wav" % key)
	turbo_release.stream = load("res://audio/engines/%s_release.wav" % key)
	idle.volume_db = -80
	load_sound.volume_db = -80
	turbo_sound.volume_db = -80
	turbo_release.volume_db = -24
	idle.pitch_scale = 0.85
	load_sound.pitch_scale = 0.85
	idle.play()
	load_sound.play()
	turbo_sound.play()

func _loop(path: String) -> AudioStreamWAV:
	var stream := (load(path) as AudioStreamWAV).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = int(stream.mix_rate * 0.025)
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream

func update_engine(delta: float, speed: float, throttle: float, max_speed: float, turbo: bool) -> void:
	if idle == null: return
	_time += delta
	var demand := absf(throttle)
	var target_rpm := clampf(absf(speed) / maxf(max_speed,1.0) * 0.82 + demand * 0.34,0.0,1.12)
	rpm = lerpf(rpm,target_rpm,1.0-exp(-delta*(6.0 if target_rpm > rpm else 3.0)))
	_load_mix = lerpf(_load_mix,demand,1.0-exp(-delta*8.0))
	var wobble := sin(_time*21.0)*0.018 + sin(_time*37.0)*0.012 if _vehicle == 5 else 0.0
	var pitch := 0.85 + rpm*float(PITCH_RANGES[_vehicle]) + wobble
	idle.pitch_scale = pitch
	load_sound.pitch_scale = pitch
	# Equal-power crossfade keeps the engine present while lifting the accelerator.
	idle.volume_db = linear_to_db(maxf(0.001,sqrt(1.0-_load_mix)*0.18))
	load_sound.volume_db = linear_to_db(maxf(0.001,sqrt(_load_mix)*(0.26 if turbo else 0.22)))
	_turbo_mix = move_toward(_turbo_mix,1.0 if turbo else 0.0,delta*7.0)
	turbo_sound.volume_db = linear_to_db(maxf(0.0001,_turbo_mix*0.10))
	turbo_sound.pitch_scale = [1.0,1.0,0.9,0.95,1.0,0.85][_vehicle] + rpm*0.25
	if _was_turbo and not turbo:
		turbo_release.play()
	_was_turbo = turbo
