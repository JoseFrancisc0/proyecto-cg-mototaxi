extends SceneTree
## Validacion contra la reproduccion oficial (S11 CG-A, completa).
##
## Corre los shaders ORIGINALES del repo H-Schott/MultiScaleErosion (tests/reference/*.glsl.txt,
## sin tocar los archivos) en la GPU con Vulkan, encadenados igual que PredefinedErosion() de
## su main.cpp, y compara con nuestro port en C++ (erosion.cpp) sobre el MISMO T0:
##   A. Una resolucion, receta completa: fluvial 3000 -> termica 600 -> deposicion 2000 (257 x 257).
##   B. Multiescala 129 -> 257 -> 513 con la receta del paper por nivel. El upsampling entre
##      niveles se hace con TerrainMesh.upsample_heightfield en las dos ramas: lineal (lo que hace
##      el repo oficial) y bicubico (lo que dice el paper, nuestra opcion por defecto).
## Deja el informe en docs/validacion/ (Markdown, JSON e imagenes).
##
## Necesita Vulkan (no --headless, no Compatibility):
##   godot --path project --rendering-driver vulkan -s res://tests/validacion_oficial.gd
## En Windows con Godot 4.7: Godot_v4.7.2-stable_win64.exe --path project --rendering-method mobile -s res://tests/validacion_oficial.gd

const PAPER_SIZE := 20000.0
const EXTENT := 1536.0   # metros del mapa del juego (512 celdas x 3 m)
const SEED := 2

var rd: RenderingDevice
var report := {}
var lines := PackedStringArray()
var out_dir := ""
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("Esta prueba necesita Vulkan (un RenderingDevice de compute). Usa --rendering-driver vulkan.")
		quit(2)
		return
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/validacion").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	lines.append("# Validacion contra la reproduccion oficial")
	lines.append("")
	lines.append("Shaders originales de https://github.com/H-Schott/MultiScaleErosion (data/shaders, SHA-256 en tests/reference/SHA256SUMS.txt), ejecutados en la GPU con Vulkan y encadenados como `PredefinedErosion()` de su `main.cpp`: cada proceso empieza con los buffers de agua y sedimento en cero, el terreno pasa de uno a otro, caja `Box2(Vector2::Null, 10 * 1000)` (de -10 km a 10 km).")
	lines.append("")
	lines.append("Dispositivo: %s. CPU: %s (%d hilos)." % [rd.get_device_name(), OS.get_processor_name(), OS.get_processor_count()])
	lines.append("")
	var t0 := _t0_heights(513)
	_stage_single(t0)
	_stage_multiscale(t0)
	_write_report()
	rd.free()
	print("Validacion oficial: %d fallas. Informe en %s" % [failures, out_dir])
	quit(0 if failures == 0 else 1)


## T0 del proyecto (ruido + regiones, semilla 2) en una grilla n x n sobre EXTENT metros.
func _t0_heights(n: int) -> PackedFloat32Array:
	var noise := TerrainNoise.new()
	noise.set_seed(SEED)
	noise.configure_regions({"enabled": true, "extent": EXTENT, "region_patches": 32})
	var cell := EXTENT / (n - 1)
	var h := PackedFloat32Array()
	h.resize(n * n)
	for z in n:
		for x in n:
			h[z * n + x] = noise.get_height(x * cell - EXTENT * 0.5, z * cell - EXTENT * 0.5)
	return h


func _subsample(h: PackedFloat32Array, n: int, step: int) -> PackedFloat32Array:
	var m := (n - 1) / step + 1
	var out := PackedFloat32Array()
	out.resize(m * m)
	for z in m:
		for x in m:
			out[z * m + x] = h[z * step * n + x * step]
	return out


# --- A. Una resolucion, receta completa ------------------------------------------

func _stage_single(t0_full: PackedFloat32Array) -> void:
	var n := 257
	var input := _subsample(t0_full, 513, 2)
	var cell := EXTENT / (n - 1)
	var recipe := {"fluvial": 3000, "thermal": 600, "deposition": 2000}
	var t := Time.get_ticks_msec()
	var cpu := TerrainMesh.new().erode_heightfield(input, n, cell, {"fluvial": 3000, "thermal": 600, "deposition": 2000, "levels": 0})
	var cpu_s := (Time.get_ticks_msec() - t) / 1000.0
	t = Time.get_ticks_msec()
	var gpu := _gpu_recipe(input, n, recipe)
	var gpu_s := (Time.get_ticks_msec() - t) / 1000.0
	var stats := _compare(cpu, gpu, input, n)
	stats["cpu_seconds"] = cpu_s
	stats["gpu_seconds"] = gpu_s
	report["A_una_resolucion"] = stats
	_images("A", input, cpu, gpu, n, cell)
	lines.append("## A. Una resolucion (257 x 257), receta completa 3000 / 600 / 2000")
	lines.append("")
	_table(stats)
	var ok: bool = stats["rmse_relative"] < 0.002 and stats["max_abs_m"] < 0.05 * stats["relief_m"]
	if not ok:
		failures += 1
	lines.append("")
	lines.append("Resultado: **%s** (criterio: RMSE < 0.2%% del relieve y error maximo < 5%% del relieve)." % ("aprobado" if ok else "NO aprobado"))
	lines.append("")
	lines.append("![CPU vs GPU](A_cpu_gpu.png)")
	lines.append("")
	lines.append("![Diferencia](A_diferencia.png)")
	lines.append("")


# --- B. Multiescala ----------------------------------------------------------------

func _stage_multiscale(t0_full: PackedFloat32Array) -> void:
	# Receta del paper por nivel (PredefinedErosion: 256 -> 512 -> 1024), con base 129.
	var plan := [{"fluvial": 3000, "thermal": 600, "deposition": 2000}, {"fluvial": 1500, "thermal": 1000, "deposition": 700},
		{"fluvial": 700, "thermal": 2000, "deposition": 200}]
	var n_final := 513
	var cell := EXTENT / (n_final - 1)
	var base := _subsample(t0_full, 513, 4)
	var results := {}
	for mode in [0, 1]:
		var label := "lineal" if mode == 0 else "bicubico"
		var t := Time.get_ticks_msec()
		var cpu := TerrainMesh.new().erode_heightfield(t0_full, n_final, cell, {"fluvial": 3000, "thermal": 600, "deposition": 2000, "levels": 2, "upsampling": mode})
		var cpu_s := (Time.get_ticks_msec() - t) / 1000.0
		t = Time.get_ticks_msec()
		var gpu := _gpu_multiscale(base, 129, plan, mode == 1, t0_full, n_final)
		var gpu_s := (Time.get_ticks_msec() - t) / 1000.0
		var stats := _compare(cpu, gpu, t0_full, n_final)
		stats["cpu_seconds"] = cpu_s
		stats["gpu_seconds"] = gpu_s
		results[label] = {"cpu": cpu, "gpu": gpu, "stats": stats}
		report["B_multiescala_" + label] = stats
	# Efecto del upsampling: bicubico (paper) contra lineal (repo oficial), ambos en CPU.
	var effect := _compare(results["bicubico"]["cpu"], results["lineal"]["cpu"], t0_full, n_final)
	report["B_efecto_upsampling"] = effect
	_images("B", t0_full, results["lineal"]["cpu"], results["lineal"]["gpu"], n_final, cell)
	lines.append("## B. Multiescala 129 -> 257 -> 513 (receta del paper por nivel)")
	lines.append("")
	lines.append("Niveles: 129 (3000/600/2000), 257 (1500/1000/700), 513 (700/2000/200).")
	lines.append("")
	for label in ["lineal", "bicubico"]:
		lines.append("### Upsampling %s en las dos ramas" % label)
		lines.append("")
		_table(results[label]["stats"])
		var s: Dictionary = results[label]["stats"]
		var ok: bool = s["rmse_relative"] < 0.003
		if not ok:
			failures += 1
		lines.append("")
		lines.append("Resultado: **%s** (criterio: RMSE < 0.3%% del relieve)." % ("aprobado" if ok else "NO aprobado"))
		lines.append("")
	lines.append("### Que cambia el tipo de upsampling (CPU bicubico contra CPU lineal)")
	lines.append("")
	_table(effect)
	lines.append("")
	lines.append("El paper describe un upsampling bicubico; `ScalarField2::SetResolution` del repo oficial termina usando `Value()`, que es bilineal en las dos ramas del `if`. El proyecto usa bicubico por defecto (pendientes continuas entre celdas) y deja el lineal como opcion (`erosion_upsampling`).")
	lines.append("")
	lines.append("![CPU vs GPU multiescala](B_cpu_gpu.png)")
	lines.append("")
	lines.append("![Diferencia multiescala](B_diferencia.png)")
	lines.append("")


func _gpu_multiscale(base: PackedFloat32Array, nb: int, plan: Array, bicubic: bool, t0_full: PackedFloat32Array, n_final: int) -> PackedFloat32Array:
	# Misma escala que erosion.cpp: (h - h_min) * 20 km / tamano del mapa, la misma en todos los niveles.
	var h_min := INF
	for v in t0_full:
		h_min = minf(h_min, v)
	var scale := PAPER_SIZE / EXTENT
	var h := PackedFloat32Array()
	h.resize(base.size())
	for i in base.size():
		h[i] = (base[i] - h_min) * scale
	var n := nb
	for level in plan.size():
		if level > 0:
			h = TerrainMesh.upsample_heightfield(h, n, bicubic)
			n = 2 * (n - 1) + 1
		h = _gpu_chain(h, n, plan[level])
	var out := PackedFloat32Array()
	out.resize(h.size())
	for i in h.size():
		out[i] = h[i] / scale + h_min
	return out


func _gpu_recipe(input: PackedFloat32Array, n: int, recipe: Dictionary) -> PackedFloat32Array:
	var h_min := INF
	for v in input:
		h_min = minf(h_min, v)
	var scale := PAPER_SIZE / EXTENT
	var h := PackedFloat32Array()
	h.resize(input.size())
	for i in input.size():
		h[i] = (input[i] - h_min) * scale
	h = _gpu_chain(h, n, recipe)
	for i in h.size():
		h[i] = h[i] / scale + h_min
	return h


## E -> T -> D como PredefinedErosion(): cada proceso parte del terreno del anterior.
func _gpu_chain(h: PackedFloat32Array, n: int, recipe: Dictionary) -> PackedFloat32Array:
	for stage in ["fluvial", "thermal", "deposition"]:
		if recipe[stage] > 0:
			h = _gpu_run(stage, h, n, recipe[stage])
	return h


func _gpu_run(stage: String, input: PackedFloat32Array, side: int, iterations: int) -> PackedFloat32Array:
	var source_name := "erosion" if stage == "fluvial" else stage
	var source := FileAccess.get_file_as_string("res://tests/reference/%s.glsl.txt" % source_name)
	source = source.replace("#version 450 core", "#version 450\n#define COMPUTE_SHADER")
	# Los uniform de OpenGL pasan a constantes con los valores que pone el C++ oficial.
	var expression := RegEx.new()
	expression.compile("uniform\\s+(int|float|vec2|bool)\\s+(\\w+)\\s*(?:=\\s*([^;]+))?;")
	var matches := expression.search_all(source)
	matches.reverse()
	for m: RegExMatch in matches:
		var type := m.get_string(1)
		var name := m.get_string(2)
		var value := m.get_string(3)
		if name == "nx" or name == "ny": value = str(side)
		if name == "a": value = "vec2(-10000.0)"
		if name == "b": value = "vec2(10000.0)"
		if name == "cellDiag": value = "vec2(%s)" % (PAPER_SIZE / (side - 1))
		source = source.substr(0, m.get_start()) + "const %s %s = %s;" % [type, name, value] + source.substr(m.get_end())
	if stage == "fluvial":
		# El shader oficial declara el buffer de dureza pero no lo usa.
		source = source.replace("layout(binding = 4, std430) readonly  buffer Hardness   { float in_hardness[]; };", "")
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = source
	var spirv := rd.shader_compile_spirv_from_source(shader_source)
	if not spirv.compile_error_compute.is_empty():
		push_error(spirv.compile_error_compute)
		failures += 1
		return input
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	var zero := PackedFloat32Array()
	zero.resize(input.size())
	var buffer_count := 6 if stage == "deposition" else (4 if stage == "fluvial" else 2)
	var buffers: Array[RID] = []
	for i in range(buffer_count):
		buffers.append(rd.storage_buffer_create(input.size() * 4, input.to_byte_array() if i == 0 else zero.to_byte_array()))
	var sets: Array[RID] = []
	for parity in range(2):
		var uniforms: Array[RDUniform] = []
		for binding in range(buffer_count):
			var u := RDUniform.new()
			u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.binding = binding
			u.add_id(buffers[binding ^ parity])  # doble buffer: entrada y salida se alternan
			uniforms.append(u)
		sets.append(rd.uniform_set_create(uniforms, shader, 0))
	var groups := ceili(side / 8.0) + 0
	var done := 0
	while done < iterations:
		var batch := mini(250, iterations - done)
		var commands := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(commands, pipeline)
		for i in range(batch):
			rd.compute_list_bind_uniform_set(commands, sets[(done + i) % 2], 0)
			rd.compute_list_dispatch(commands, groups, groups, 1)
			rd.compute_list_add_barrier(commands)
		rd.compute_list_end()
		rd.submit()
		rd.sync()
		done += batch
	var output := rd.buffer_get_data(buffers[iterations % 2]).to_float32_array()
	for set_rid: RID in sets:
		rd.free_rid(set_rid)
	for buffer: RID in buffers:
		rd.free_rid(buffer)
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	return output


# --- Comparacion e informe ---------------------------------------------------------

func _compare(a: PackedFloat32Array, b: PackedFloat32Array, input: PackedFloat32Array, n: int) -> Dictionary:
	var max_abs := 0.0
	var sq := 0.0
	var lo := INF
	var hi := -INF
	var within_1cm := 0
	var within_10cm := 0
	var sa := 0.0
	var sb := 0.0
	var change_a := 0.0
	for i in a.size():
		var d := absf(a[i] - b[i])
		max_abs = maxf(max_abs, d)
		sq += d * d
		lo = minf(lo, a[i])
		hi = maxf(hi, a[i])
		if d < 0.01: within_1cm += 1
		if d < 0.1: within_10cm += 1
		change_a += absf(a[i] - input[i]) if input.size() == a.size() else 0.0
	var count := float(a.size())
	var rmse := sqrt(sq / count)
	# Correlacion de los cambios respecto al T0 (cuanto se parecen los patrones de erosion).
	var ma := 0.0
	var mb := 0.0
	for i in a.size():
		ma += a[i] - input[i]
		mb += b[i] - input[i]
	ma /= count
	mb /= count
	var cov := 0.0
	var va := 0.0
	var vb := 0.0
	for i in a.size():
		var x := (a[i] - input[i]) - ma
		var y := (b[i] - input[i]) - mb
		cov += x * y
		va += x * x
		vb += y * y
	return {"samples": n, "max_abs_m": max_abs, "rmse_m": rmse, "relief_m": hi - lo, "rmse_relative": rmse / maxf(hi - lo, 1e-6),
		"within_1cm": within_1cm / count, "within_10cm": within_10cm / count, "mean_change_m": change_a / count,
		"change_correlation": cov / sqrt(maxf(va * vb, 1e-20))}


func _table(s: Dictionary) -> void:
	lines.append("| Medida | Valor |")
	lines.append("|---|---|")
	lines.append("| Muestras por lado | %d |" % s["samples"])
	lines.append("| Relieve del resultado | %.2f m |" % s["relief_m"])
	lines.append("| Cambio medio respecto a T0 | %.3f m |" % s["mean_change_m"])
	lines.append("| Error maximo | %.4f m |" % s["max_abs_m"])
	lines.append("| RMSE | %.4f m (%.4f%% del relieve) |" % [s["rmse_m"], s["rmse_relative"] * 100.0])
	lines.append("| Muestras con error < 1 cm | %.2f%% |" % (s["within_1cm"] * 100.0))
	lines.append("| Muestras con error < 10 cm | %.2f%% |" % (s["within_10cm"] * 100.0))
	lines.append("| Correlacion del cambio entre las dos versiones | %.6f |" % s["change_correlation"])
	if s.has("cpu_seconds"):
		lines.append("| Tiempo CPU / GPU (lavapipe o la GPU real) | %.1f s / %.1f s |" % [s["cpu_seconds"], s["gpu_seconds"]])


func _images(tag: String, input: PackedFloat32Array, cpu: PackedFloat32Array, gpu: PackedFloat32Array, n: int, cell: float) -> void:
	var size := 512
	var lo := INF
	var hi := -INF
	for v in cpu:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var opts := {"h_min": lo, "h_max": hi, "label": "CPU (erosion.cpp)"}
	var a := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, TerrainMesh.render_heightfield(cpu, n, cell, "mapa", size, size, opts))
	opts["label"] = "GPU (shaders oficiales)"
	var b := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, TerrainMesh.render_heightfield(gpu, n, cell, "mapa", size, size, opts))
	var both := Image.create(size * 2, size, false, Image.FORMAT_RGB8)
	both.blit_rect(a, Rect2i(0, 0, size, size), Vector2i.ZERO)
	both.blit_rect(b, Rect2i(0, 0, size, size), Vector2i(size, 0))
	both.save_png(out_dir.path_join("%s_cpu_gpu.png" % tag))
	var diff := PackedFloat32Array()
	diff.resize(cpu.size())
	var r := 0.0
	for i in cpu.size():
		diff[i] = cpu[i] - gpu[i]
		r = maxf(r, absf(diff[i]))
	r = maxf(r, 0.001)
	var d := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, TerrainMesh.render_heightfield(diff, n, cell, "escalar", size, size,
		{"min": -r, "max": r, "palette": 2, "label": "CPU - GPU (rojo +%.3f m, azul -%.3f m)" % [r, r]}))
	d.save_png(out_dir.path_join("%s_diferencia.png" % tag))


func _write_report() -> void:
	var f := FileAccess.open(out_dir.path_join("validacion_oficial.md"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	var j := FileAccess.open(out_dir.path_join("validacion_oficial.json"), FileAccess.WRITE)
	j.store_string(JSON.stringify(report, "\t"))
	print("\n".join(lines))
