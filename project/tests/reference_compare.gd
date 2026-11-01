extends SceneTree
## Run with Vulkan (not --headless / Compatibility). Official shader sources remain unmodified on disk.
var rd: RenderingDevice
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("Esta prueba necesita Vulkan y un dispositivo de compute disponible.")
		quit(2)
		return
	var field := TerrainField.new()
	field.generate(68, 256, 1.0, {"erosion_enabled": false, "retarget_enabled": false, "roads_enabled": false})
	var input := field.get_initial_heights()
	var minimum: float = input[0]
	for h: float in input: minimum = minf(minimum, h)
	var scale := 20000.0 / 256.0
	var scaled := input.duplicate()
	for i in range(scaled.size()): scaled[i] = (input[i] - minimum) * scale
	var results := {}
	for stage in ["fluvial", "thermal", "deposition"]:
		var cfg := {"fluvial": 0, "thermal": 0, "deposition": 0}
		var iterations := 12 if stage == "fluvial" else 4
		cfg[stage] = iterations
		var cpu := field.erode_input(input, 257, 1.0, cfg)
		var gpu := _gpu_run(stage, scaled, 257, iterations)
		if gpu.size() != input.size():
			failures += 1
			continue
		var maximum := 0.0
		var sum_squared := 0.0
		for i in range(cpu.size()):
			var gpu_height: float = gpu[i] / scale + minimum
			var difference := absf(cpu[i] - gpu_height)
			maximum = maxf(maximum, difference)
			sum_squared += difference * difference
		var passed := maximum < 0.02
		if not passed: failures += 1
		results[stage] = {"iterations": iterations, "max_error_world_units": maximum, "rmse": sqrt(sum_squared / cpu.size()), "tolerance": 0.02, "passed": passed}
		print(stage, ": ", results[stage])
	var folder := ProjectSettings.globalize_path("res://../output")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder + "/reference_comparison.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"source": "H-Schott/MultiScaleErosion data/shaders", "samples": 257, "seed": 68, "regional_maps": false, "results": results}, "\t"))
	rd.free()
	print("Comparacion oficial: %d errores" % failures)
	quit(0 if failures == 0 else 1)

func _gpu_run(stage: String, input: PackedFloat32Array, side: int, iterations: int) -> PackedFloat32Array:
	var source_name := "erosion" if stage == "fluvial" else stage
	var source := FileAccess.get_file_as_string("res://tests/reference/%s.glsl.txt" % source_name)
	source = source.replace("#version 450 core", "#version 450\n#define COMPUTE_SHADER")
	# Convert OpenGL uniforms to compile-time constants, same original default values.
	var expression := RegEx.new()
	expression.compile("uniform\\s+(int|float|vec2|bool)\\s+(\\w+)\\s*(?:=\\s*([^;]+))?;")
	var matches := expression.search_all(source)
	matches.reverse()
	for match: RegExMatch in matches:
		var type := match.get_string(1)
		var name := match.get_string(2)
		var value := match.get_string(3)
		if name == "nx" or name == "ny": value = str(side)
		# Como el repo oficial: Box2(Vector2::Null, 10 * 1000) = caja de -10 km a 10 km.
		if name == "a": value = "vec2(-10000.0)"
		if name == "b": value = "vec2(10000.0)"
		if name == "cellDiag": value = "vec2(%s)" % (20000.0 / (side - 1))
		source = source.substr(0, match.get_start()) + "const %s %s = %s;" % [type, name, value] + source.substr(match.get_end())
	# The official erosion shader declares a hardness buffer but never uses it.
	expression.compile("layout\\(binding = 4, std430\\) readonly  buffer Hardness[^;]+;[^;]+;")
	if stage == "fluvial":
		source = source.replace("layout(binding = 4, std430) readonly  buffer Hardness   { float in_hardness[]; };", "")
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = source
	var spirv := rd.shader_compile_spirv_from_source(shader_source)
	if not spirv.compile_error_compute.is_empty():
		push_error(spirv.compile_error_compute)
		return PackedFloat32Array()
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
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = binding
			uniform.add_id(buffers[binding ^ parity])
			uniforms.append(uniform)
		sets.append(rd.uniform_set_create(uniforms, shader, 0))
	var commands := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(commands, pipeline)
	for i in range(iterations):
		rd.compute_list_bind_uniform_set(commands, sets[i % 2], 0)
		rd.compute_list_dispatch(commands, ceili(side / 8.0), ceili(side / 8.0), 1)
		rd.compute_list_add_barrier(commands)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var output := rd.buffer_get_data(buffers[iterations % 2]).to_float32_array()
	for set_rid: RID in sets: rd.free_rid(set_rid)
	for buffer: RID in buffers: rd.free_rid(buffer)
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	return output
