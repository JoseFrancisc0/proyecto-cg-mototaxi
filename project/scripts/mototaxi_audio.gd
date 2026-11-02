class_name MototaxiAudio
extends AudioStreamPlayer
## Sonido de la mototaxi (S14): rodadura y golpes de choque/vuelco, sintetizados en tiempo real
## (EngineSynth). El motor lo pone VehicleEngineAudio (un sonido por vehículo del garaje); el motor
## sintetizado de aquí queda como alternativa con engine_enabled = true.
##
## Las rpm salen de una caja de 4 marchas virtual: con la velocidad y la marcha se calculan
## las rpm; al pasar shift_up_rpm sube de marcha (las rpm caen y el gas se corta un instante)
## y al bajar de shift_down_rpm reduce. En primera, el embrague deja subir las rpm aunque la
## mototaxi esté quieta. Va como hijo de la Mototaxi y lee su velocidad y su acelerador.

@export var idle_rpm := 1400.0
@export var redline_rpm := 7500.0
## Velocidad (km/h) de cada marcha al llegar a redline_rpm.
@export var gear_top_kmh: PackedFloat32Array = PackedFloat32Array([18.0, 33.0, 49.0, 67.0])
@export var reverse_top_kmh := 16.0
@export var shift_up_rpm := 6900.0
@export var shift_down_rpm := 3000.0
@export var shift_time := 0.3          ## Segundos sin gas al subir de marcha.
@export var clutch_rpm := 3300.0       ## rpm máximas con el embrague patinando en primera.
@export var crash_volume := 1.0
## Motor monocilíndrico sintetizado. Apagado: el motor lo pone VehicleEngineAudio.
@export var engine_enabled := false

var synth := EngineSynth.new(22050.0)
## 0 = reversa, 1..4 = marchas.
var gear := 1
var engine_rpm := 1400.0

var _moto: Mototaxi
var _playback: AudioStreamGeneratorPlayback
var _shift_timer := 0.0


func _ready() -> void:
	_moto = get_parent() as Mototaxi
	synth.engine_enabled = engine_enabled
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = synth.mix_rate
	gen.buffer_length = 0.12
	stream = gen
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback
	if _moto:
		_moto.damaged.connect(_on_damaged)
	_fill()


func _process(delta: float) -> void:
	if _moto:
		update_engine(_moto.get_forward_speed() * 3.6, _moto.throttle, _moto.wheels_in_contact() > 0, delta)
	_fill()


## Actualiza marcha, rpm, carga y rodadura. speed_kmh con signo (negativa en reversa).
func update_engine(speed_kmh: float, throttle: float, grounded: bool, delta: float) -> void:
	var gas := clampf(throttle, 0.0, 1.0)
	var target: float
	var load := 0.0
	if speed_kmh < -1.0 or (throttle < -0.05 and speed_kmh < 0.5):
		# Reversa: el freno pasa a ser el acelerador.
		gear = 0
		gas = clampf(-throttle, 0.0, 1.0)
		target = idle_rpm + absf(speed_kmh) / reverse_top_kmh * (redline_rpm - idle_rpm)
		target = maxf(target, idle_rpm + gas * (clutch_rpm - idle_rpm))
		load = gas
	else:
		if gear == 0:
			gear = 1
		if _shift_timer <= 0.0:
			var geared := _geared_rpm(speed_kmh, gear)
			if gear < gear_top_kmh.size() and geared > shift_up_rpm and gas > 0.05:
				gear += 1
				_shift_timer = shift_time
			elif gear > 1 and geared < shift_down_rpm:
				gear -= 1
		target = maxf(_geared_rpm(speed_kmh, gear), idle_rpm)
		if gear == 1:
			target = maxf(target, idle_rpm + gas * (clutch_rpm - idle_rpm))
		load = gas
	if not grounded:
		# Llanta en el aire: el motor se embala libre.
		target = idle_rpm + absf(throttle) * (redline_rpm - idle_rpm) * 0.9
	if _shift_timer > 0.0:
		_shift_timer -= delta
		load = 0.0
	# Inercia del cigüeñal: sube rápido, baja más lento.
	var tau := 0.07 if target > engine_rpm else 0.16
	engine_rpm = lerpf(engine_rpm, target, 1.0 - exp(-delta / tau))
	engine_rpm = clampf(engine_rpm, idle_rpm * 0.9, redline_rpm * 1.03)
	synth.rpm = engine_rpm
	synth.load = load
	synth.roll = clampf(absf(speed_kmh) / 55.0, 0.0, 1.0) if grounded else 0.0


func _geared_rpm(speed_kmh: float, g: int) -> float:
	return absf(speed_kmh) / gear_top_kmh[g - 1] * redline_rpm


func _fill() -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames > 0:
		_playback.push_buffer(synth.render(frames))


func _on_damaged(amount: float, reason: String) -> void:
	var strength := clampf(amount / 25.0, 0.2, 1.0)
	if reason == "vuelco":
		strength = 1.0
	synth.hit(strength * crash_volume)
