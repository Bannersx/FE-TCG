class_name BoardState
extends RefCounted

const DEFAULT_WIDTH: int = 7
const DEFAULT_HEIGHT: int = 7
const PLAIN: String = "Plain"
const FOREST: String = "Forest"
const FORT: String = "Fort"
const MOUNTAIN: String = "Mountain"
const OBJECTIVE: String = "Objective"
const ROAD: String = "Road"
const RIVER: String = "River"
const BRIDGE: String = "Bridge"
const HIGH_GROUND: String = "High Ground"
const RUINS: String = "Ruins"
const LAVA: String = "Lava"
const SHRINE: String = "Shrine"
const TERRAIN_DESCRIPTIONS: Dictionary = {
	PLAIN: "Normal movement; no bonus.",
	FOREST: "+1 DEF; ground movement costs 2. Verdant ground units pay 1; Verdant units heal 1 at turn start.",
	FORT: "+2 DEF; heal 1 at the start of the owner's turn.",
	MOUNTAIN: "Ground units cannot enter; flying units can.",
	OBJECTIVE: "Eligible occupants score 1 VP at the start of their turn.",
	ROAD: "Starting an activation here grants +1 movement.",
	RIVER: "Ground movement costs 2; flying movement costs 1.",
	BRIDGE: "Normal movement; provides a crossing through river tiles.",
	HIGH_GROUND: "+1 attack damage from more than one tile away.",
	RUINS: "+1 DEF against attacks from more than one tile away.",
	LAVA: "Ground units take 1 damage at the end of their owner's turn; flying units are immune.",
	SHRINE: "Once per shrine each turn, landing grants 1 supply, up to 6.",
}
static var WIDTH: int = DEFAULT_WIDTH
static var HEIGHT: int = DEFAULT_HEIGHT
static var OBJECTIVE_POSITIONS: Array[Vector2i] = []
static var COMMANDER_ROW: int = DEFAULT_HEIGHT / 2

var terrain: Dictionary = {}
var occupants: Dictionary = {}
var width: int
var height: int
var objective_layout: String
var objective_positions: Array[Vector2i] = []
var objective_denied: Dictionary = {}

const OBJECTIVE_LAYOUTS: Array[String] = ["column", "wide", "diagonal", "row", "contested", "contested_mid", "contested_front", "contested_flank", "contested_near", "four_corners"]
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
	var data: Dictionary = _objective_data(WIDTH, HEIGHT, layout)
	OBJECTIVE_POSITIONS.assign(data["positions"])
	OBJECTIVE_DENIED = data["denied"]

static func _objective_data(board_width: int, board_height: int, layout: String) -> Dictionary:
	var mid: int = board_width / 2
	var row: int = board_height / 2
	var spacing: int = 2 if board_height >= 5 else 1
	var positions: Array[Vector2i] = []
	var denied: Dictionary = {}
	match layout:
		"wide":
			for offset in [-spacing, 0, spacing]:
				positions.append(Vector2i(mid, row + offset))
		"diagonal":
			positions.append(Vector2i(mid - 1, row - spacing))
			positions.append(Vector2i(mid, row))
			positions.append(Vector2i(mid + 1, row + spacing))
		"row":
			for offset in range(-1, 2):
				positions.append(Vector2i(mid + offset, row))
		"contested", "contested_mid", "contested_front", "contested_flank", "contested_near":
			var home_x: int = {"contested": 1, "contested_mid": 2, "contested_front": mid - 1, "contested_flank": mid - 2, "contested_near": mid - 1}[layout]
			var home_y: int = {"contested": 0, "contested_mid": 1, "contested_front": 0, "contested_flank": 1, "contested_near": 2}[layout]
			var home_one := Vector2i(home_x, home_y)
			var home_two := Vector2i(board_width - 1 - home_x, board_height - 1 - home_y)
			positions.append(home_one)
			positions.append(Vector2i(mid, row))
			positions.append(home_two)
			denied[home_one] = 0
			denied[home_two] = 1
		"four_corners":
			positions.assign([Vector2i(mid, row), Vector2i(mid - 2, row), Vector2i(mid + 2, row), Vector2i(mid, row - 2), Vector2i(mid, row + 2)])
		_:
			for offset in range(-1, 2):
				positions.append(Vector2i(mid, row + offset))
	return {"positions": positions, "denied": denied}

func _init(board_width: int = 0, board_height: int = 0, layout: String = "") -> void:
	if OBJECTIVE_POSITIONS.is_empty():
		configure(WIDTH, HEIGHT, OBJECTIVE_LAYOUT)
	width = WIDTH if board_width == 0 else board_width
	height = HEIGHT if board_height == 0 else board_height
	objective_layout = OBJECTIVE_LAYOUT if layout.is_empty() else layout
	var data: Dictionary = _objective_data(width, height, objective_layout)
	objective_positions.assign(data["positions"])
	objective_denied = data["denied"]
	for y in range(height):
		for x in range(width):
			terrain[Vector2i(x, y)] = PLAIN
	if objective_layout == "four_corners":
		for tile in [Vector2i(3, 3), Vector2i(5, 3), Vector2i(5, 5), Vector2i(3, 5)]:
			terrain[tile] = FOREST
		for objective in objective_positions:
			terrain[objective] = OBJECTIVE
		return
	# Layout is symmetric under 180-degree rotation so neither side is favored.
	var center_x: int = width / 2
	for y_offset in [-2, -1, 1, 2]:
		for x_offset in [-1, 1]:
			var forest := Vector2i(center_x + x_offset, height / 2 + y_offset)
			if is_valid_position(forest):
				terrain[forest] = FOREST
	terrain[Vector2i(0, 0)] = MOUNTAIN
	terrain[Vector2i(width - 1, height - 1)] = MOUNTAIN
	terrain[Vector2i(0, height - 1)] = FORT
	terrain[Vector2i(width - 1, 0)] = FORT
	for objective in objective_positions:
		terrain[objective] = OBJECTIVE

static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func is_valid_position(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < width and position.y >= 0 and position.y < height

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
	if terrain_name in [FOREST, RIVER] and movement_type == CardData.MovementType.GROUND:
		return 2
	return 1

func deployment_column(player_id: int) -> int:
	return 0 if player_id == 0 else width - 1

func commander_position(player_id: int) -> Vector2i:
	if objective_layout == "four_corners":
		return [Vector2i(0, 0), Vector2i(width - 1, 0), Vector2i(width - 1, height - 1), Vector2i(0, height - 1)][player_id]
	return Vector2i(deployment_column(player_id), height / 2)

func is_deployment_tile(player_id: int, tile: Vector2i) -> bool:
	if not is_valid_position(tile):
		return false
	if objective_layout != "four_corners":
		return tile.x == deployment_column(player_id)
	var home: Vector2i = commander_position(player_id)
	return absi(tile.x - home.x) <= 2 and absi(tile.y - home.y) <= 2

func scores_for(tile: Vector2i, player_id: int) -> bool:
	return objective_positions.has(tile) and int(objective_denied.get(tile, -1)) != player_id

# Terrain players may place before the match. Plain erases the default terrain on a tile.
const PLACEABLE: Array[String] = [FOREST, FORT, MOUNTAIN, ROAD, RIVER, BRIDGE, HIGH_GROUND, RUINS, LAVA, SHRINE, PLAIN]
const PLACEMENT_CAPS: Dictionary = {MOUNTAIN: 1, FORT: 1}

# Objectives and both deployment columns are never editable.
func is_locked_tile(position: Vector2i) -> bool:
	if objective_positions.has(position):
		return true
	for player_id in range(4 if objective_layout == "four_corners" else 2):
		if is_deployment_tile(player_id, position):
			return true
	return false

# True when ground units can walk from both commander tiles to every objective.
static func objectives_reachable(layout: Dictionary) -> bool:
	var board := BoardState.new()
	return board.can_reach_objectives(layout)

func can_reach_objectives(layout: Dictionary) -> bool:
	for player_id in range(4 if objective_layout == "four_corners" else 2):
		var start: Vector2i = commander_position(player_id)
		var seen: Dictionary = {start: true}
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var current: Vector2i = queue.pop_back()
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = current + step
				if not is_valid_position(next) or seen.has(next):
					continue
				if str(layout.get(next, PLAIN)) == MOUNTAIN:
					continue
				seen[next] = true
				queue.append(next)
		for objective in objective_positions:
			if not seen.has(objective):
				return false
	return true
