class_name EngineSynth
extends RefCounted
## Sintetizador procedural de la mototaxi: motor monocilíndrico de 4 tiempos, rodadura y golpes.
##
## El motor es un tren de explosiones: una cada dos vueltas del cigüeñal (rpm / 120 por
## segundo). Cada explosión es un pulso corto que excita resonadores fijos (cuerpo del
## silenciador y tubo de escape). Al subir las rpm solo cambia la frecuencia de los pulsos y
## no el timbre, como en un motor real; por eso no suena a sirena. La variación aleatoria entre
## ciclos (en tiempo y fuerza) da el "traqueteo" del ralentí.
##
## No depende del árbol de escenas: render() devuelve muestras, así se puede escuchar en el
## juego (MototaxiAudio) o grabar a WAV sin ventana (tests/render_engine_audio.gd).

var mix_rate := 22050.0
## Objetivos; dentro de cada bloque se interpolan muestra a muestra.
var rpm := 1400.0
var load := 0.0       ## 0 = sin gas (freno motor), 1 = acelerador a fondo.
var roll := 0.0       ## 0..1 ruido de las llantas sobre el suelo.
var volume := 0.8


## Filtro pasa banda (RBJ, ganancia 1 en el centro).
class Resonator:
	var b0 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func _init(freq: float, q: float, rate: float) -> void:
		setup(freq, q, rate)

	func setup(freq: float, q: float, rate: float) -> void:
		var w := TAU * freq / rate
		var alpha := sin(w) / (2.0 * q)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w) / a0
		a2 = (1.0 - alpha) / a0

	func process(x: float) -> float:
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y


var _rng := RandomNumberGenerator.new()
var _rpm_now := 1400.0
var _load_now := 0.0
var _roll_now := 0.0

# Motor
var _phase := 0.0
var _cycle_scale := 1.0
var _pulse := 0.0
var _pulse_decay := 0.0
var _tick := 0.0          # golpeteo de válvulas a mitad del ciclo
var _ticked := false
var _pop_lp := 0.0        # parte grave del pulso ("pop" del escape)
var _tone_lp := 0.0       # filtro de brillo: más abierto con más gas
var _muffler: Resonator
var _pipe: Resonator
var _pipe2: Resonator
var _rasp: Resonator
var _valve: Resonator

# Rodadura
var _roll_lp := 0.0
var _roll_lp2 := 0.0

# Golpes
var _thump := 0.0
var _thump_f := 110.0
var _thump_ph := 0.0
var _clank_exc := 0.0
var _rattle := 0.0
var _clank: Array[Resonator] = []
var _thump_decay := 0.0
var _clank_exc_decay := 0.0
var _rattle_decay := 0.0


func _init(rate := 22050.0, seed_value := 0) -> void:
	mix_rate = rate
	_rng.seed = seed_value if seed_value != 0 else randi()
	_pulse_decay = exp(-1.0 / (0.0035 * rate))
	_thump_decay = exp(-1.0 / (0.13 * rate))
	_clank_exc_decay = exp(-1.0 / (0.012 * rate))
	_rattle_decay = exp(-1.0 / (0.22 * rate))
	_muffler = Resonator.new(90.0, 1.6, rate)
	_pipe = Resonator.new(235.0, 4.5, rate)
	_pipe2 = Resonator.new(610.0, 3.0, rate)
	_rasp = Resonator.new(1750.0, 1.4, rate)
	_valve = Resonator.new(2900.0, 6.0, rate)
	for f in [820.0, 1430.0, 2270.0, 3650.0]:
		_clank.append(Resonator.new(f, 30.0, rate))


## Golpe contra algo; strength en [0, 1].
func hit(strength: float) -> void:
	strength = clampf(strength, 0.0, 1.0)
	_thump = maxf(_thump, strength)
	_thump_f = lerpf(95.0, 140.0, _rng.randf())
	_thump_ph = 0.0
	_clank_exc = maxf(_clank_exc, strength)
	_rattle = maxf(_rattle, strength * 0.6)
	# Cada golpe suena a una lata distinta.
	var bases := [820.0, 1430.0, 2270.0, 3650.0]
	for i in _clank.size():
		_clank[i].setup(bases[i] * _rng.randf_range(0.88, 1.12), _rng.randf_range(20.0, 40.0), mix_rate)


func render(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	if frames <= 0:
		return out
	var inv := 1.0 / mix_rate
	var rpm_step := (rpm - _rpm_now) / frames
	var load_step := (load - _load_now) / frames
	var roll_step := (roll - _roll_now) / frames
	var roll_k := 1.0 - exp(-TAU * 380.0 * inv)
	var pop_k := 1.0 - exp(-TAU * 160.0 * inv)
	for i in frames:
		_rpm_now += rpm_step
		_load_now += load_step
		_roll_now += roll_step
		var noise := _rng.randf() * 2.0 - 1.0

		# --- Motor ---
		_phase += _rpm_now / 120.0 * inv * _cycle_scale
		if _phase >= 1.0:
			_phase -= 1.0
			_ticked = false
			_fire()
		elif not _ticked and _phase >= 0.5:
			_ticked = true
			_tick = 0.12 + 0.05 * _rng.randf()
		_pulse *= _pulse_decay
		_tick *= _pulse_decay
		var exc := _pulse * (0.6 + 0.4 * noise)
		_pop_lp += (exc - _pop_lp) * pop_k
		var bright := 0.25 + 0.75 * _load_now
		var engine := _pop_lp * 2.2 \
			+ _muffler.process(exc) * 1.6 \
			+ _pipe.process(exc) * 1.1 \
			+ _pipe2.process(exc) * 0.5 \
			+ _rasp.process(exc) * (0.12 + 0.4 * bright) \
			+ _valve.process(_tick * noise) * 0.35
		var tone_k := 1.0 - exp(-TAU * lerpf(1100.0, 4500.0, bright) * inv)
		_tone_lp += (engine - _tone_lp) * tone_k
		var s := _tone_lp

		# --- Rodadura: ruido grave que crece con la velocidad ---
		if _roll_now > 0.001:
			_roll_lp += (noise - _roll_lp) * roll_k
			_roll_lp2 += (_roll_lp - _roll_lp2) * roll_k
			s += _roll_lp2 * _roll_now * 0.9

		# --- Golpes: golpe sordo + chapa que vibra ---
		if _thump > 0.0005:
			_thump_f = maxf(38.0, _thump_f * 0.99985)
			_thump_ph += _thump_f * inv
			s += sin(TAU * _thump_ph) * _thump * 0.9
			_thump *= _thump_decay
		if _clank_exc > 0.0005 or _rattle > 0.0005:
			var ce := noise * _clank_exc
			if _rattle > 0.0005 and _rng.randf() < 0.006:
				ce += _rattle * (1.0 if _rng.randf() < 0.5 else -1.0) * 2.0
			var c := 0.0
			for r in _clank:
				c += r.process(ce)
			s += c * 0.7
			_clank_exc *= _clank_exc_decay
			_rattle *= _rattle_decay

		var v := tanh(s * 1.4) * volume
		out[i] = Vector2(v, v)
	return out


## Una explosión: fuerza según el gas, con variación entre ciclos.
func _fire() -> void:
	var idle_ness := clampf((2600.0 - _rpm_now) / 1200.0, 0.0, 1.0)
	_cycle_scale = 1.0 + _rng.randf_range(-1.0, 1.0) * lerpf(0.012, 0.05, idle_ness)
	var amp := lerpf(0.4, 1.0, _load_now) * (1.0 + _rng.randf_range(-0.15, 0.15))
	if _load_now < 0.1 and _rpm_now > 3200.0 and _rng.randf() < 0.05:
		amp *= 2.0  # petardeo al soltar el gas con el motor alto
	elif idle_ness > 0.5 and _rng.randf() < 0.02:
		amp *= 0.3  # ciclo flojo en ralentí
	_pulse = amp
