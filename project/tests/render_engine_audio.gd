extends SceneTree
## Graba el sonido de la mototaxi a WAV sin abrir el juego y comprueba que esté bien formado.
##   Godot --headless --path project -s res://tests/render_engine_audio.gd
## Salida: output/audio/mototaxi_demo.wav (en la raíz del repo).
## Guion: ralentí, acelerón quieta, arranque a fondo con cambios, soltar gas, frenar,
## reversa, dos choques y un vuelco.

const RATE := 22050.0
const STEP := 1.0 / 60.0

var errors := 0


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FALLA ") + what)
	if not ok:
		errors += 1


func _initialize() -> void:
	var audio := MototaxiAudio.new()  # sin padre: se maneja a mano
	audio.synth = EngineSynth.new(RATE, 1234)
	var synth := audio.synth
	var samples := PackedVector2Array()
	var speed := 0.0
	var t := 0.0
	var gears_seen := {}
	var max_rpm := 0.0
	var render_ms := 0.0
	var crashes := {9.0: 0.5, 13.5: 1.0, 17.0: 0.3}
	while t < 22.0:
		var throttle := 0.0
		if t < 2.0: throttle = 0.0                     # ralentí
		elif t < 3.0: throttle = 1.0 if fmod(t, 0.5) < 0.25 else 0.0  # acelerones quieta
		elif t < 4.0: throttle = 0.0
		elif t < 12.0: throttle = 1.0                  # a fondo
		elif t < 14.5: throttle = 0.0                  # suelta el gas
		elif t < 17.5: throttle = -1.0                 # frena / reversa
		elif t < 18.0: throttle = 0.0
		elif t < 20.0: throttle = 0.5
		# Modelo simple de velocidad: tirón que baja con la velocidad, roce y freno.
		var moving := t >= 4.0
		if moving and throttle > 0.0:
			speed += throttle * maxf(0.4, 9.0 - speed * 0.12) * STEP
		elif throttle < 0.0:
			speed = speed - 25.0 * STEP if speed > 0.5 else maxf(speed - 4.0 * STEP, -10.0)
		else:
			speed = move_toward(speed, 0.0, 2.5 * STEP)
		speed = minf(speed, 66.0)
		audio.update_engine(speed, throttle, true, STEP)
		gears_seen[audio.gear] = true
		max_rpm = maxf(max_rpm, audio.engine_rpm)
		for ct in crashes:
			if t <= ct and ct < t + STEP:
				synth.hit(crashes[ct])
		var t0 := Time.get_ticks_usec()
		samples.append_array(synth.render(int(RATE * STEP)))
		render_ms += (Time.get_ticks_usec() - t0) / 1000.0
		t += STEP

	var peak := 0.0
	var finite := true
	var sum2 := 0.0
	for v in samples:
		if not is_finite(v.x):
			finite = false
			break
		peak = maxf(peak, absf(v.x))
		sum2 += v.x * v.x
	var rms := sqrt(sum2 / samples.size())
	var cpu := render_ms / (t * 1000.0) * 100.0
	print("Duración %.1f s, pico %.2f, RMS %.3f, rpm máx %d, marchas %s, CPU %.1f %% de un núcleo" % [t, peak, rms, int(max_rpm), gears_seen.keys(), cpu])
	_check(finite, "muestras finitas")
	_check(peak > 0.2 and peak <= 1.0, "nivel audible y sin pasar de 1")
	_check(gears_seen.has(0) and gears_seen.has(4), "usa reversa y llega a 4ta")
	_check(cpu < 15.0, "síntesis barata (< 15 % de un núcleo)")

	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i].x, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(RATE)
	wav.stereo = false
	wav.data = data
	var dir := ProjectSettings.globalize_path("res://").path_join("../output/audio").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("mototaxi_demo.wav")
	_check(wav.save_to_wav(path) == OK, "WAV guardado en " + path)
	audio.free()
	print("RESULTADO: " + ("OK" if errors == 0 else "%d fallas" % errors))
	quit(1 if errors else 0)
