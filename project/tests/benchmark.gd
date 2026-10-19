extends SceneTree

func _initialize() -> void:
	var field := TerrainField.new()
	var args := OS.get_cmdline_user_args()
	var scale := 1.0 if "--paper-iterations" in args else 0.03
	print("Inicio de benchmark 256 -> 512 -> 1024; escala de iteraciones: ", scale)
	var success := field.generate(68, 1024, 1.0, {"levels": 2, "iteration_scale": scale, "retarget_iterations": 200})
	if not success:
		quit(1)
		return
	for h: float in field.get_heights():
		if not is_finite(h):
			push_error("Alturas no finitas")
			quit(1)
			return
	var folder := ProjectSettings.globalize_path("res://../output")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder + "/benchmark_%s.json" % str(scale), FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed": 68, "grid_cells": 1024, "iteration_scale": scale, "timings_seconds": field.get_timings()}, "\t"))
	print("Benchmark completado: ", field.get_timings())
	quit()
