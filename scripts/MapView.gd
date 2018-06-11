extends Node2D

const Constants = preload("res://scripts/Constants.gd")
const HexGrid = preload("res://scripts/helpers/HexGrid.gd")
const ElevationOverlay = preload("res://scripts/terrain/ElevationOverlay.tscn")

onready var terrain_tilemap = $Terrain
onready var elevation_overlays = $Elevation
onready var map_objects = $MapObjects

var world_map setget set_world_map
var terrain_grid
var unit_grid
var display_rect

func setup(world_map, map_loader):
	self.world_map = world_map
	modulate = map_loader.global_lighting

	_setup_terrain(map_loader.terrain_tileset, map_loader.terrain_indexes)
	_setup_elevation_overlays(world_map.elevation, map_loader.overlay_colors)
	_setup_scatters(map_loader.scatter_spawners)

	for structure in world_map.structures:
		map_objects.add_child(structure)
	
	for road in world_map.roads:
		map_objects.add_child(road)

	## setup clouds overlay
	var clouds = map_loader.clouds_overlay.new()
	clouds.randomize_scroll()
	
	add_child(clouds)
	clouds.set_display_rect(display_rect)

## setup terrain tiles
func _setup_terrain(terrain_tileset, terrain_indexes):
	terrain_tilemap.z_as_relative = false
	terrain_tilemap.z_index = Constants.TERRAIN_ZLAYER
	terrain_tilemap.cell_half_offset = TileMap.HALF_OFFSET_X
	terrain_tilemap.tile_set = terrain_tileset

	terrain_tilemap.cell_size = terrain_grid.cell_spacing
	terrain_tilemap.position = terrain_grid.position - terrain_grid.cell_spacing/2 #center tiles on grid points

	for offset_cell in terrain_indexes:
		var idx = terrain_indexes[offset_cell]
		terrain_tilemap.set_cellv(offset_cell, idx)

## setup elevation overlays
func _setup_elevation_overlays(elevation, overlay_colors):
	var terrain_tiles = world_map.terrain_tiles

	for offset_cell in world_map.get_rect_cells(display_rect):
		var grid_cell = unit_grid.offset_to_axial(offset_cell)
		var elevation_info = elevation.get_info(grid_cell)
		var terrain_cell = world_map.get_terrain_cell(grid_cell)
		
		if elevation_info && terrain_tiles.has(terrain_cell):
			var terrain_tile = terrain_tiles[terrain_cell]
			var offset_terrain = terrain_grid.axial_to_offset(terrain_cell)
			var overlay_color = overlay_colors[offset_terrain] if overlay_colors.has(offset_terrain) else null

			var overlay = ElevationOverlay.instance()
			overlay.set_color(overlay_color)
			overlay.setup(elevation_info)
			elevation_overlays.add_child(overlay)

## setup scatters
func _setup_scatters(scatter_spawners):
	var terrain_grid = world_map.terrain_grid

	var scatter_grid = HexGrid.new()
	scatter_grid.cell_size = terrain_grid.cell_size
	for hex_pos in scatter_spawners:
		scatter_grid.position = terrain_grid.offset_to_world(hex_pos)
		var spawner = scatter_spawners[hex_pos]
		for scatter in spawner.create_scatters(world_map, scatter_grid, terrain_grid.cell_spacing.x/2.0):
			map_objects.add_child(scatter)
	scatter_grid.queue_free()

func set_world_map(map):
	world_map = map
	terrain_grid = map.terrain_grid
	unit_grid = map.unit_grid
	display_rect = map.display_rect