class_name MovementResolver
extends RefCounted

static func reachable_tiles(board: BoardState, unit: UnitState) -> Dictionary:
	var distances: Dictionary = {unit.position: 0}
	var frontier: Array[Vector2i] = [unit.position]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		var current_cost: int = int(distances[current])
		for offset: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var neighbor: Vector2i = current + offset
			if not board.is_valid_position(neighbor):
				continue
			if neighbor != unit.position and board.occupants.has(neighbor):
				continue
			var step_cost: int = FactionRules.move_cost(board, unit, neighbor)
			if step_cost < 0:
				continue
			var new_cost: int = current_cost + step_cost
			if new_cost > unit.movement():
				continue
			if not distances.has(neighbor) or new_cost < int(distances[neighbor]):
				distances[neighbor] = new_cost
				frontier.append(neighbor)
	return distances

static func can_reach(board: BoardState, unit: UnitState, destination: Vector2i) -> bool:
	var destinations: Dictionary = reachable_tiles(board, unit)
	return destinations.has(destination) and destination != unit.position
