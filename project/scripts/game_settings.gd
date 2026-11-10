class_name GameSettings
extends RefCounted
## Preferencias del jugador que no son de la partida (se guardan en user://settings.cfg).

const PATH := "user://settings.cfg"
static var path := PATH

## Obstáculos en las vías: 0 ninguno, 1 pocos, 2 normal, 3 muchos (ver RoadObstacles.LEVELS).
static func get_obstacle_level() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return 2
	return clampi(int(cfg.get_value("juego", "obstaculos", 2)), 0, RoadObstacles.LEVELS.size() - 1)


static func set_obstacle_level(level: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # Si no existe, se crea.
	cfg.set_value("juego", "obstaculos", clampi(level, 0, RoadObstacles.LEVELS.size() - 1))
	cfg.save(path)


static func get_option(key: String, fallback: Variant) -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg.get_value("expansion",key,fallback)

static func set_option(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("expansion",key,value)
	cfg.save(path)
