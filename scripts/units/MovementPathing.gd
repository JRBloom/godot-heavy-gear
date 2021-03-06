## Generates all possible movement for a unit and stores this information for display and pathing.

extends Reference

const SortingUtils = preload("res://scripts/helpers/SortingUtils.gd")
const MovementPath = preload("res://scripts/units/MovementPath.gd")

static func calc_possible_moves(current_activation):
	var move_unit = current_activation.active_unit
	var last_path = current_activation.last_movement_path()
	
	## calculate pathing for each movement mode and then merge the results
	var possible_moves = {}
	for move_mode in current_activation.available_movement_modes():
		var init_path = MovementPath.new(move_unit, move_mode)
		if !last_path:
			init_path.start_movement(move_unit.cell_position, move_unit.facing)
		else:
			init_path.continue_movement(last_path)
		
		var movement = MovementSearch.new(init_path)
		for cell_pos in movement.possible_moves:
			var complete_path = movement.possible_moves[cell_pos]
			if !possible_moves.has(cell_pos) || _move_path_compare(possible_moves[cell_pos], complete_path):
				possible_moves[cell_pos] = complete_path

	return possible_moves

## compare movement modes to use for a given destination position
static func _move_path_compare(left, right):
	return SortingUtils.lexical_sort(_move_priority_lexical(left), _move_priority_lexical(right))

const UnitActivation = preload("res://scripts/units/UnitActivation.gd")

static func _move_priority_lexical(move_path):
	var move_unit = move_path.move_unit
	var move_mode = move_path.move_mode
	var moves_remaining = move_unit.max_movement_points() - move_path.moves_used
	var is_extended_move = moves_remaining < UnitActivation.EXTENDED_MOVE

	return [
		#1 if !move_info.hazard else -1, #non-hazardous over hazardous moves
		1 if move_mode.free_rotate else -1, #prefer free rotations
		1 if !is_extended_move else -1, #prefer to avoid extended movement
		-move_path.moves_used, #prefer fewer movement points used
		-move_path.turns_used, #prefer fewer turns used
		1 if !move_mode.reversed else -1, #prefer non-reversed movement, all else equal
		hash(move_path), #lastly, sort by hash to ensure determinism
	]


##### Movement Pathing Search #####

const HexUtils = preload("res://scripts/helpers/HexUtils.gd")
const PriorityQueue = preload("res://scripts/helpers/PriorityQueue.gd")

const MOVE_TOLERANCE = 0.025

class MovementSearch:
	## a dictionary of the grid positions this unit can reach from the start_loc
	## maps grid cells -> movement path ending in that cell.
	var possible_moves = {}
	var move_unit
	var move_mode
	var world_map

	func _init(starting_path):
		assert(starting_path.size() > 0) ## need a starting location
		self.move_unit = starting_path.move_unit
		self.move_mode = starting_path.move_mode
		self.world_map = move_unit.world_map
		
		var start_pos = starting_path.last_pos()
		var visited = _search_possible_moves(starting_path)
		for cell_pos in visited:
			if cell_pos != start_pos && world_map.unit_can_place(move_unit, cell_pos):
				possible_moves[cell_pos] = visited[cell_pos]

	## lower priority -> explored first
	func _priority(move_path):
		## TODO when implemented: avoid hazards
		return move_path.moves_used + move_path.turns_used/1000.0

	func _search_possible_moves(starting_path):
		var move_queue = PriorityQueue.new()
		move_queue.add(starting_path, _priority(starting_path))

		var visited = {}
		while !move_queue.empty():
			var move_path = move_queue.pop_min()
			var visit_pos = move_path.last_pos()
			if !visited.has(visit_pos):
				visited[visit_pos] = move_path
				_search_neighbors(move_path, visited, move_queue)
		
		return visited

	func _search_neighbors(cur_path, visited, move_queue):
		var cur_pos = cur_path.last_pos()
		var neighbors = HexUtils.get_axial_neighbors(cur_pos)
		for move_dir in neighbors:
			var next_pos = neighbors[move_dir]
			
			if visited.has(next_pos):
				continue ## already visited
			
			if !world_map.unit_can_pass(move_unit, move_mode, cur_pos, next_pos):
				continue ## can't go here
			
			## create a new move path that branches to the next_pos
			var next_path = cur_path.extended(next_pos, move_dir)

			## can we afford this move?
			if next_path.moves_used <= move_unit.max_movement_points() + MOVE_TOLERANCE:
				move_queue.add(next_path, _priority(next_path))
