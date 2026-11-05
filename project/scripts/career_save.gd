class_name CareerSave
extends RefCounted
## Progreso entre partidas: ahorros (lo que sobra de cada jornada después de pagar la cuota),
## mototaxis compradas en el garaje y mejor jornada. Se guarda en user://carrera.cfg.

const PATH := "user://carrera.cfg"
## Mototaxi con la que se empieza (gratis).
const STARTER := 2

## Ruta del archivo; las pruebas la cambian para no tocar la partida del jugador.
static var path := PATH


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)  # Si no existe, queda vacío.
	return cfg


static func _save(cfg: ConfigFile) -> void:
	var err := cfg.save(path)
	if err != OK:
		push_warning("CareerSave: no se pudo guardar %s (%s)" % [path, error_string(err)])


static func get_savings() -> float:
	return float(_load().get_value("carrera", "ahorros", 0.0))


static func add_savings(amount: float) -> float:
	var cfg := _load()
	var total := maxf(float(cfg.get_value("carrera", "ahorros", 0.0)) + amount, 0.0)
	cfg.set_value("carrera", "ahorros", snappedf(total, 0.01))
	_save(cfg)
	return total


static func get_owned() -> Array:
	var owned: Array = _load().get_value("carrera", "mototaxis", [STARTER])
	if not owned.has(STARTER):
		owned.append(STARTER)
	return owned


static func is_owned(index: int) -> bool:
	return get_owned().has(index)


## Compra la mototaxi si alcanzan los ahorros. true si se compró (o ya era tuya).
static func buy(index: int) -> bool:
	if is_owned(index):
		return true
	var price := float(VehicleCatalog.entry(index).get("price", 0.0))
	var cfg := _load()
	var savings := float(cfg.get_value("carrera", "ahorros", 0.0))
	if savings < price:
		return false
	var owned := get_owned()
	owned.append(index)
	cfg.set_value("carrera", "ahorros", snappedf(savings - price, 0.01))
	cfg.set_value("carrera", "mototaxis", owned)
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


## Borra el progreso (pruebas o "empezar de cero").
static func reset() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
