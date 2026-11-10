class_name Difficulty
extends RefCounted
## Dificultad de la partida (pendiente 13): se elige al empezar una partida y se mantiene en
## toda ella (para cambiarla hay que empezar otra). Viaja en el escenario elegido
## (choice["difficulty"]) y se guarda con la partida.
##
## La dificultad sale sobre todo de lo que hay en el camino (obstáculos fijos, animales,
## tráfico); el tiempo límite solo da algo de aire en Fácil. Más difícil, mejor pagado.

const FACIL := 0
const NORMAL := 1
const DIFICIL := 2

## Por nivel:
##   name: nombre en los menús; hint: una línea para el jugador.
##   obstacles: nivel de RoadObstacles.LEVELS.
##   time: multiplica el tiempo límite de cada viaje.
##   fare: multiplica la tarifa.
##   animals, traffic: cantidad relativa de animales y vehículos (RoadAnimals, RoadTraffic).
##   oncoming: fracción de los vehículos que vienen de frente (hacen peligroso adelantar).
const LEVELS := [
	{"name": "Fácil", "hint": "Pocos obstáculos y más tiempo para cada viaje.",
		"obstacles": 1, "time": 1.2, "fare": 0.9, "animals": 0.5, "traffic": 0.4, "oncoming": 0.1},
	{"name": "Normal", "hint": "Obstáculos y tiempo justos. Tarifa normal.",
		"obstacles": 2, "time": 1.0, "fare": 1.0, "animals": 1.0, "traffic": 1.0, "oncoming": 0.35},
	{"name": "Difícil", "hint": "Muchos obstáculos en el camino: llegar a tiempo cuesta. Pagan 25 % más.",
		"obstacles": 3, "time": 1.0, "fare": 1.25, "animals": 1.8, "traffic": 1.7, "oncoming": 0.5},
]


static func clamp_level(level: int) -> int:
	return clampi(level, 0, LEVELS.size() - 1)


## Nivel de un escenario elegido (Normal si no trae).
static func of(choice: Dictionary) -> int:
	return clamp_level(int(choice.get("difficulty", NORMAL)))


static func get_value(level: int, key: String) -> Variant:
	return LEVELS[clamp_level(level)][key]


static func level_name(level: int) -> String:
	return LEVELS[clamp_level(level)]["name"]
