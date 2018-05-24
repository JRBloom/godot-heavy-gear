extends Node2D

const Constants = preload("res://scripts/Constants.gd")
const HexUtils = preload("res://scripts/helpers/HexUtils.gd")
const ArrayMap = preload("res://scripts/helpers/ArrayMap.gd")

const MapLoader = preload("res://scripts/MapLoader.gd")
const ElevationMap = preload("res://scripts/terrain/ElevationMap.gd")
const ElevationOverlay = preload("res://scripts/terrain/ElevationOverlay.tscn")

## dimensions of terrain hexes
## it is important that these are all multiples of 16, due to the geometry of hex grids
## and the fact that the unit grid must fit exactly into the terrain grid
## note that for regular hexagons, w = sqrt(3)/2 * h
const TERRAIN_WIDTH  = 16*16 #256
const TERRAIN_HEIGHT = 18*16 #288

const UNITGRID_WIDTH = TERRAIN_WIDTH/4 #64
const UNITGRID_HEIGHT = TERRAIN_HEIGHT/4 #72

const UNITGRID_SIZE = UNITGRID_WIDTH/HexUtils.UNIT_DISTANCE # grid spacing in distance units

export(PackedScene) var source_map

onready var terrain_grid = $TerrainGrid
onready var terrain_tilemap = $TerrainGrid/TileMap
onready var unit_grid = $UnitGrid

## maps axial terrain cells -> offset terrain cells used by terrain_tilemap
var terrain_tiles = {}

## These are all Rect2s in world coordinates (i.e. pixels)
var map_extents #describes the terrain hexes used by the map, in offset coords
var map_rect  #the displayable boundary of the map
var unit_bounds #the "game" boundary of the map

## data structures to map position -> object
var structure_locs = {} #1-to-1
var road_cells = {}
var unit_locs = ArrayMap.new() #1-to-many

## elevation map object
var elevation

func _ready():
	terrain_grid.cell_size = Vector2(TERRAIN_WIDTH, TERRAIN_HEIGHT)
	unit_grid.cell_size = Vector2(UNITGRID_WIDTH, UNITGRID_HEIGHT)
	
	#terrain_grid.position = terrain_grid.cell_size/2
	#unit_grid.position = unit_grid.cell_size/2
	
	## load the source map
	var map_loader = MapLoader.new()
	map_loader.load_map(self, source_map)
	
	modulate = map_loader.global_lighting
	
	## setup terrain tiles
	terrain_tilemap.z_as_relative = false
	terrain_tilemap.z_index = Constants.TERRAIN_ZLAYER
	terrain_tilemap.cell_size = terrain_grid.cell_spacing
	terrain_tilemap.position = -terrain_grid.cell_spacing/2 #center tiles on grid points
	terrain_tilemap.cell_half_offset = TileMap.HALF_OFFSET_X
	terrain_tilemap.tile_set = map_loader.terrain_tileset
	
	for offset_cell in map_loader.terrain_indexes:
		var axial_cell = terrain_grid.offset_to_axial(offset_cell)
		terrain_tiles[axial_cell] = offset_cell

		var idx = map_loader.terrain_indexes[offset_cell]
		terrain_tilemap.set_cellv(offset_cell, idx)
	
	## determine the map bounds
	map_extents = map_loader.map_extents
	
	var vertical_margin = Vector2(0, TERRAIN_HEIGHT/4) #extend the margin so that only the point parts are cut off
	var map_ul = terrain_grid.offset_to_world(map_extents.position) - vertical_margin
	var map_lr = terrain_grid.offset_to_world(map_extents.end) + vertical_margin
	map_rect = Rect2(map_ul, map_lr - map_ul)
	
	#unit cells must be entirely contained within the map bounds
	var unit_margins = unit_grid.cell_size
	unit_bounds = Rect2(map_rect.position + unit_margins, map_rect.size - unit_margins*2)
	
	## setup terrain elevation 
	## TODO move this into MapLoader, should just pull them out and add them
#	elevation = ElevationMap.new(self)
#	elevation.load_hex_map(map_loader.terrain_elevation)
#
#	for cell_pos in get_rect_cells(map_rect):
#		var info = elevation.get_info(cell_pos)
#		if info:
#			var overlay = ElevationOverlay.instance()
#			add_child(overlay)
#
#			var elevation_info = elevation.get_info(cell_pos)
#			if elevation_info:
#				overlay.setup(elevation_info)
	
	## setup structures
	for cell_pos in map_loader.structures:
		var structure = map_loader.structures[cell_pos]
		_setup_structure(structure, cell_pos)
	
	## setup roads
#	for road_segment in map_loader.road_segments:
#		add_child(road_segment)
#		for cell_pos in road_segment.footprint:
#			road_cells[cell_pos] = true
	
	## setup scatters
#	for hex_pos in map_loader.scatter_spawners:
#		var spawner = map_loader.scatter_spawners[hex_pos]
#		spawner.position = get_terrain_pos(hex_pos)
#		add_child(spawner)
#
#		for scatter in spawner.create_scatters(self):
#			add_child(scatter)
#
#		spawner.queue_free()

## Initialization

## returns the bounding rectangle in offset cell coords
func get_map_extents():
	return map_extents

## returns the bounding rectangle in world coords
func get_bounding_rect():
	return map_rect

func get_grid_rect():
	return unit_bounds

func all_terrain_cells():
	return terrain_tiles.values()

func _setup_structure(structure, cell_pos):
	structure.world_map = self
	structure.cell_position = cell_pos
	
	var footprint_cells = []
	for rect in structure.get_footprint():
		for cell in HexUtils.get_rect(rect):
			footprint_cells.push_back(cell)
			if !grid_cell_on_map(cell):
				print("WARNING: structure extends off map at ", cell)
				return
			
			if structure_locs.has(cell):
				print("WARNING: structure already present at cell ", cell)
				structure.queue_free()
				return
	
	_update_object_position(structure, cell_pos)
	add_child(structure)
	for cell in footprint_cells:
		structure_locs[cell] = structure

## Terrain Cells

func raw_terrain_info(terrain_cell):
	var offset_cell = terrain_tiles[terrain_cell]
	var tile_idx = terrain_tilemap.get_cellv(offset_cell)
	
	if tile_idx < 0: return null #outside of map
	
	var tile_id = terrain_tilemap.tile_set.tile_get_name(tile_idx)
	return TerrainDefs.get_terrain_info(tile_id)

func get_terrain_at_world(world_pos):
	var grid_cell = unit_grid.get_axial_cell(world_pos)
	return get_terrain_at_cell(grid_cell)

var _terrain_cache = {}
func get_terrain_at_cell(grid_cell):
	if _terrain_cache.has(grid_cell):
		return _terrain_cache[grid_cell]
	
	var terrain_cell = get_terrain_cell(grid_cell)
	
	var info = raw_terrain_info(terrain_cell)
	if !info: return null
	
	info = info.duplicate()
	info.has_road = road_cells.has(grid_cell)
	info.elevation = elevation.get_info(grid_cell)
	
	if structure_locs.has(grid_cell):
		var s = structure_locs[grid_cell]
		var s_info = s.get_terrain_info()
		if s_info:
			for key in s_info:
				info[key] = s_info[key]
	
	_terrain_cache[grid_cell] = info
	return info

## should be called after anything that modifies terrain
func refresh_terrain(terrain_cell):
	_terrain_cache.erase(terrain_cell)

func point_on_map(world_pos):
	if !unit_bounds.has_point(world_pos):
		return false
	
	var offset_cell = terrain_grid.get_offset_cell(world_pos)
	var tile_id = terrain_tilemap.get_cellv(offset_cell)
	return tile_id >= 0

## Unit Grid Cells

## obtains the terrain cell that contains this grid cell
func get_terrain_cell(grid_cell):
	var world_pos = unit_grid.axial_to_world(grid_cell)
	return terrain_grid.get_axial_cell(world_pos)

## gets the complete position of a cell in distance units including elevation
func get_ground_location(cell_pos):
	var info = get_terrain_at_cell(cell_pos)
	return info.elevation.world_pos/HexUtils.UNIT_DISTANCE

func get_angle_to(cell_from, cell_to):
	var from_pos = unit_grid.axial_to_world(cell_from)
	var to_pos = unit_grid.axial_to_world(cell_to)
	return (to_pos - from_pos).angle()

## gets the closest direction to get from one cell to another
func get_dir_to(cell_from, cell_to):
	return HexUtils.nearest_dir(get_angle_to(cell_from, cell_to))

## returns the distance betwen the centres of two cells, in distance units
func distance_along_ground(cell1, cell2):
	var pos1 = get_ground_location(cell1)
	var pos2 = get_ground_location(cell2)
	return (pos1 - pos2).length()

func path_distance(cell_path):
	var distance = 0
	var last_cell = null
	for next_cell in cell_path:
		if last_cell:
			distance += distance_along_ground(last_cell, next_cell)
		last_cell = next_cell
	return distance

func grid_cell_on_map(cell_pos):
	var world_pos = unit_grid.axial_to_world(cell_pos)
	if !unit_bounds.has_point(world_pos):
		return false
	return point_on_map(world_pos)

func get_neighbors(cell_pos):
	var neighbors = []
	for other_pos in HexUtils.get_neighbors(cell_pos).values():
		if grid_cell_on_map(other_pos):
			neighbors.push_back(other_pos)
	return neighbors

## gets all grid cells overlapping a rectangle given in pixel coords
#func get_rect_cells(world_rect):
#	var ul = unit_grid.get_offset_cell(world_rect.position)
#	var lr = unit_grid.get_offset_cell(world_rect.end)
#	return HexUtils.get_rect(Rect2(ul, lr - ul))

## Map Objects

func add_unit(unit):
	unit.world_map = self
	unit.connect("cell_position_changed", self, "_unit_cell_position_changed", [unit])
	unit_locs.push_back(unit.cell_position, unit)
	_update_object_position(unit, unit.cell_position)
	add_child(unit)

func get_units_at_cell(cell_pos):
	if !unit_locs.has(cell_pos):
		return []
	return unit_locs.get_values(cell_pos)

func get_structure_at_cell(cell_pos):
	return structure_locs[cell_pos] if structure_locs.has(cell_pos) else null

func get_objects_at_cell(cell_pos):
	return get_units_at_cell(cell_pos)

func _unit_cell_position_changed(old_pos, new_pos, unit):
	unit_locs.move(old_pos, new_pos, unit)
	_update_object_position(unit, new_pos)

func _update_object_position(object, cell_pos):
	var world_pos = unit_grid.axial_to_world(cell_pos)
	if object.has_method("get_position_offset"):
		world_pos += object.get_position_offset()
	object.position = world_pos

## return true if a unit can pass from a given cell into another
func unit_can_pass(unit, movement_mode, from_cell, to_cell):
	## check that to_cell is actually on the map
	var to_world = unit_grid.axial_to_world(to_cell)
	var from_world = unit_grid.axial_to_world(from_cell)
	var midpoint = 0.5*(to_world + from_world)
	if !point_on_map(to_world) || !point_on_map(midpoint):
		return false
	
	## check that the terrain is passable
	var dest_info = get_terrain_at_cell(to_cell)
	if dest_info.impassable.has(movement_mode.type_id):
		return false
	
	var midpoint_info = get_terrain_at_world(midpoint)
	if midpoint_info.impassable.has(movement_mode.type_id):
		return false
	
	## make sure there are no objects that could block us
	for object in get_objects_at_cell(to_cell):
		if object != unit && !object.can_pass(unit):
			return false

	return true

## return true if a unit can stop (i.e. finish movement) in a given cell
func unit_can_place(unit, dest_cell):
	## check that dest_cell is actually on the map
	if !grid_cell_on_map(dest_cell):
		return false
	
	## check that the terrain is passable
	var allowed = false
	var terrain_info = get_terrain_at_cell(dest_cell)
	for movement_mode in unit.unit_info.get_movement_modes():
		if !terrain_info.impassable.has(movement_mode.type_id):
			allowed = true
			break
	
	if !allowed: return false
	
	## make sure there are no objects that could block us
	for object in get_objects_at_cell(dest_cell):
		if object != unit && !object.can_stack(unit):
			return false
	
	return true