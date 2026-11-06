class_name BoardState
extends RefCounted

const DEFAULT_WIDTH: int = 7
const DEFAULT_HEIGHT: int = 7
const PLAIN: String = "Plain"
const FOREST: String = "Forest"
const FORT: String = "Fort"
const MOUNTAIN: String = "Mountain"
const OBJECTIVE: String = "Objective"
static var WIDTH: int = DEFAULT_WIDTH
static var HEIGHT: int = DEFAULT_HEIGHT
static var OBJECTIVE_POSITIONS: Array[Vector2i] = []
static var COMMANDER_ROW: int = DEFAULT_HEIGHT / 2

var terrain: Dictionary = {}
var occupants: Dictionary = {}

const OBJECTIVE_LAYOUTS: Array[String] = ["column", "wide", "diagonal", "row", "contested", "contested_mid", "contested_front", "contested_flank", "contested_near"]
static var OBJECTIVE_LAYOUT: String = "column"
# Objective tile -> the player who cannot score it (the contested layout's home-side objectives).
static var OBJECTIVE_DENIED: Dictionary = {}

# True when holding this tile earns the player victory points.
static func objective_scores_for(tile: Vector2i, player_id: int) -> bool:
	return OBJECTIVE_POSITIONS.has(tile) and int(OBJECTIVE_DENIED.get(tile, -1)) != player_id

# Changes the board size for all later matches. Commanders sit on the middle row; layouts place the three objectives:
# column = adjacent in the middle column, wide = middle column spaced two apart,
# diagonal = one near each flank plus the centre, row = side by side along the commander row,
# contested = a neutral centre plus one in each home corner that does not score for the player whose side it is on.
static func configure(width: int, height: int, layout: String = "column") -> void:
	WIDTH = maxi(width, 5)
	HEIGHT = maxi(height, 3)
	COMMANDER_ROW = HEIGHT / 2
	OBJECTIVE_LAYOUT = layout
	var mid: int = WIDTH / 2
	var spacing: int = 2 if HEIGHT >= 5 else 1
	OBJECTIVE_POSITIONS = []
	OBJECTIVE_DENIED = {}
	match layout:
		"wide":
			for offset in [-spacing, 0, spacing]:
				OBJECTIVE_POSITIONS.append(Vector2i(mid, COMMANDER_ROW + offset))
		"diagonal":
			OBJECTIVE_POSITIONS.append(Vector2i(mid - 1, COMMANDER_ROW - spacing))
			OBJECTIVE_POSITIONS.append(Vector2i(mid, COMMANDER_ROW))
			OBJECTIVE_POSITIONS.append(Vector2i(mid + 1, COMMANDER_ROW + spacing))
		"row":
			for offset in range(-1, 2):
				OBJECTIVE_POSITIONS.append(Vector2i(mid + offset, COMMANDER_ROW))
		"contested", "contested_mid", "contested_front", "contested_flank", "contested_near":
			var home_x: int = {"contested": 1, "contested_mid": 2, "contested_front": mid - 1, "contested_flank": mid - 2, "contested_near": mid - 1}[layout]
			var home_y: int = {"contested": 0, "contested_mid": 1, "contested_front": 0, "contested_flank": 1, "contested_near": 2}[layout]
			var home_one := Vector2i(home_x, home_y)
			var home_two := Vector2i(WIDTH - 1 - home_x, HEIGHT - 1 - home_y)
			OBJECTIVE_POSITIONS.append(home_one)
			OBJECTIVE_POSITIONS.append(Vector2i(mid, COMMANDER_ROW))
			OBJECTIVE_POSITIONS.append(home_two)
			OBJECTIVE_DENIED[home_one] = 0
			OBJECTIVE_DENIED[home_two] = 1
		_:
			for offset in range(-1, 2):
				OBJECTIVE_POSITIONS.append(Vector2i(mid, COMMANDER_ROW + offset))

func _init() -> void:
	if OBJECTIVE_POSITIONS.is_empty():
		configure(WIDTH, HEIGHT, OBJECTIVE_LAYOUT)
	for y in range(HEIGHT):
		for x in range(WIDTH):
			terrain[Vector2i(x, y)] = PLAIN
	# Layout is symmetric under 180-degree rotation so neither side is favored.
	var center_x: int = WIDTH / 2
	for y_offset in [-2, -1, 1, 2]:
		for x_offset in [-1, 1]:
			var forest := Vector2i(center_x + x_offset, COMMANDER_ROW + y_offset)
			if is_valid_position(forest):
				terrain[forest] = FOREST
	terrain[Vector2i(0, 0)] = MOUNTAIN
	terrain[Vector2i(WIDTH - 1, HEIGHT - 1)] = MOUNTAIN
	terrain[Vector2i(0, HEIGHT - 1)] = FORT
	terrain[Vector2i(WIDTH - 1, 0)] = FORT
	for objective in OBJECTIVE_POSITIONS:
		terrain[objective] = OBJECTIVE

static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func is_valid_position(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < WIDTH and position.y >= 0 and position.y < HEIGHT

func unit_at(position: Vector2i) -> UnitState:
	return occupants.get(position) as UnitState

func terrain_at(position: Vector2i) -> String:
	return str(terrain.get(position, PLAIN))

func place_unit(unit: UnitState, position: Vector2i) -> bool:
	if not is_valid_position(position) or occupants.has(position):
		return false
	occupants[position] = unit
	unit.position = position
	return true

func move_unit(unit: UnitState, destination: Vector2i) -> bool:
	if not is_valid_position(destination) or occupants.has(destination):
		return false
	if occupants.get(unit.position) != unit:
		return false
	occupants.erase(unit.position)
	occupants[destination] = unit
	unit.position = destination
	return true

func remove_unit(unit: UnitState) -> void:
	if occupants.get(unit.position) == unit:
		occupants.erase(unit.position)

func defense_bonus(position: Vector2i) -> int:
	match terrain_at(position):
		FOREST:
			return 1
		FORT:
			return 2
	return 0

func movement_cost(position: Vector2i, movement_type: CardData.MovementType) -> int:
	var terrain_name: String = terrain_at(position)
	if terrain_name == MOUNTAIN and movement_type == CardData.MovementType.GROUND:
		return -1
	if terrain_name == FOREST and movement_type == CardData.MovementType.GROUND:
		return 2
	return 1

func deployment_column(player_id: int) -> int:
	return 0 if player_id == 0 else WIDTH - 1

# Terrain players may place before the match. Plain erases the default terrain on a tile.
const PLACEABLE: Array[String] = [FOREST, FORT, MOUNTAIN, PLAIN]
const PLACEMENT_CAPS: Dictionary = {MOUNTAIN: 1, FORT: 1}

# Objectives and both deployment columns are never editable.
func is_locked_tile(position: Vector2i) -> bool:
	return OBJECTIVE_POSITIONS.has(position) or position.x == 0 or position.x == WIDTH - 1

# True when ground units can walk from both commander tiles to every objective.
static func objectives_reachable(layout: Dictionary) -> bool:
	for player_id in range(2):
		var start := Vector2i(0 if player_id == 0 else WIDTH - 1, COMMANDER_ROW)
		var seen: Dictionary = {start: true}
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var current: Vector2i = queue.pop_back()
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = current + step
				if next.x < 0 or next.x >= WIDTH or next.y < 0 or next.y >= HEIGHT or seen.has(next):
					continue
				if str(layout.get(next, PLAIN)) == MOUNTAIN:
					continue
				seen[next] = true
				queue.append(next)
		for objective in OBJECTIVE_POSITIONS:
			if not seen.has(objective):
				return false
	return true
