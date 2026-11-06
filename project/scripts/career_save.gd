class_name CareerSave
extends RefCounted
## Progreso del jugador en user://carrera.cfg (en Windows: %APPDATA%/Godot/app_userdata/<proyecto>/).
##
## Dos niveles:
##   - Carrera (sección "carrera", se conserva siempre): mototaxis compradas, la mototaxi en
##     uso y la mejor jornada.
##   - Partida (sección "partida", se borra al perder o al empezar otra): el estado guardado
##     (mundo, día, reloj, posición) y los ahorros de esa partida, con los que se compran
##     mototaxis en el garaje. Lo comprado se queda aunque se pierda la partida.

const PATH := "user://carrera.cfg"
## Mototaxi con la que se empieza (gratis).
const STARTER := 2

## Archivo de las pruebas (scripts con -s): así nunca tocan la partida del jugador.
const TEST_PATH := "user://carrera_pruebas.cfg"

## Ruta del archivo; las pruebas pueden cambiarla.
static var path := _default_path()

## Escenario con el que Main arranca al recargar la escena, sin pasar por la portada (cambiar
## de escenario al terminar el día, al perder o al reiniciar). {} = mostrar la portada.
## Vive solo en memoria: se usa una vez y se borra.
static var launch := {}


static func _default_path() -> String:
	var args := OS.get_cmdline_args()
	return TEST_PATH if args.has("-s") or args.has("--script") else PATH


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)  # Si no existe, queda vacío.
	# Versiones anteriores guardaban los ahorros en la carrera: pasan a la partida guardada.
	if cfg.has_section_key("carrera", "ahorros"):
		var old := float(cfg.get_value("carrera", "ahorros", 0.0))
		cfg.erase_section_key("carrera", "ahorros")
		if cfg.has_section_key("partida", "estado"):
			cfg.set_value("partida", "ahorros", snappedf(float(cfg.get_value("partida", "ahorros", 0.0)) + old, 0.01))
		_save(cfg)
	return cfg


static func _save(cfg: ConfigFile) -> void:
	var err := cfg.save(path)
	if err != OK:
		push_warning("CareerSave: no se pudo guardar %s (%s)" % [path, error_string(err)])


## Ahorros de la partida en curso (0 si no hay partida).
static func get_savings() -> float:
	return float(_load().get_value("partida", "ahorros", 0.0))


static func add_savings(amount: float) -> float:
	var cfg := _load()
	var total := maxf(float(cfg.get_value("partida", "ahorros", 0.0)) + amount, 0.0)
	cfg.set_value("partida", "ahorros", snappedf(total, 0.01))
	_save(cfg)
	return total


static func get_owned() -> Array:
	var owned: Array = _load().get_value("carrera", "mototaxis", [STARTER])
	if not owned.has(STARTER):
		owned.append(STARTER)
	return owned


static func is_owned(index: int) -> bool:
	return get_owned().has(index)


## Compra la mototaxi con los ahorros de la partida y la deja en uso. true si se compró
## (o ya era tuya).
static func buy(index: int) -> bool:
	if is_owned(index):
		return true
	var price := float(VehicleCatalog.entry(index).get("price", 0.0))
	var cfg := _load()
	var savings := float(cfg.get_value("partida", "ahorros", 0.0))
	if savings < price:
		return false
	var owned := get_owned()
	owned.append(index)
	cfg.set_value("partida", "ahorros", snappedf(savings - price, 0.01))
	cfg.set_value("carrera", "mototaxis", owned)
	cfg.set_value("carrera", "activa", index)
	_save(cfg)
	return true


## Mototaxi en uso (la elegida en el garaje); siempre una comprada.
static func get_active() -> int:
	var cfg := _load()
	var index := int(cfg.get_value("carrera", "activa", STARTER))
	var owned: Array = cfg.get_value("carrera", "mototaxis", [STARTER])
	return index if index == STARTER or owned.has(index) else STARTER


## Elige la mototaxi en uso. false si no es tuya.
static func set_active(index: int) -> bool:
	if not is_owned(index):
		return false
	var cfg := _load()
	cfg.set_value("carrera", "activa", index)
	_save(cfg)
	return true


static func get_best_day() -> int:
	return int(_load().get_value("carrera", "mejor_dia", 0))


## Guarda el día completado si es el mejor. true si es récord.
static func record_day(day: int) -> bool:
	var cfg := _load()
	if day <= int(cfg.get_value("carrera", "mejor_dia", 0)):
		return false
	cfg.set_value("carrera", "mejor_dia", day)
	_save(cfg)
	return true


## Borra todo el progreso (pruebas).
static func reset() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Partida guardada (menú de pausa "Guardar partida" y al completar cada día): el mundo
## elegido, el día, el reloj, lo ganado hoy y dónde estaba la mototaxi. {} si no hay.
static func load_game() -> Dictionary:
	var data: Variant = _load().get_value("partida", "estado", {})
	return data if data is Dictionary else {}


static func has_game() -> bool:
	return not load_game().is_empty()


static func save_game(data: Dictionary) -> void:
	var cfg := _load()
	cfg.set_value("partida", "estado", data)
	_save(cfg)


## Termina la partida (al perder o al empezar otra): se borran su estado y sus ahorros.
static func clear_game() -> void:
	var cfg := _load()
	if cfg.has_section("partida"):
		cfg.erase_section("partida")
		_save(cfg)
