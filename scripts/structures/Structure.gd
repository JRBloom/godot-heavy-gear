extends Sprite

const Constants = preload("res://scripts/Constants.gd")

var _info

var world_map
var cell_position

func _ready():
	z_as_relative = false
	z_index = Constants.STRUCTURE_ZLAYER

func set_structure_info(info):
	_info = info
	
	## info.offset specifies the LL corner, but sprites are placed at the UL corner
	texture = info.texture
	offset = Vector2(0, -texture.get_size().y)
	centered = false

func get_footprint():
	return _info.footprint

func get_position_offset(): return _info.position_offset #offset from the centre of the grid cell
func get_structure_id(): return _info.structure_id
func exclude_scatters(): return _info.exclude_scatters
func get_terrain_info(): return _info.terrain_info