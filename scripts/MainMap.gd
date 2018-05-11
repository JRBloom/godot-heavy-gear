extends Node

onready var context_panel = $HUDLayer/LowerLeftPanel/ContextPanel
onready var camera = $Camera
onready var world = $WorldMap

onready var move_marker = $MoveMarker

var ui_contexts = {
	dev_spawn_unit = preload("res://scripts/UIContext/SpawnUnitTool.tscn"),
	dev_delete_unit = preload("res://scripts/UIContext/DeleteUnitTool.tscn"),
	activate_unit = preload("res://scripts/UIContext/ActivateUnit.tscn"),
	move_unit = preload("res://scripts/UIContext/MoveUnit.tscn"),
}

func _ready():
	## set camera limits
	var map_rect = world.get_bounding_rect()
	camera.set_limit_rect(map_rect)
	
	## load and register UI Contexts
	for context_name in ui_contexts:
		var instance = ui_contexts[context_name].instance()
		context_panel.register(instance, context_name)
	
	## load the initial context
	context_panel.activate("activate_unit")

## capture any input events related to map objects and forward them to the context_panel
func _unhandled_input(event):
	if event is InputEventMouse:
		var mouse_pos = world.get_global_mouse_position()
		context_panel.position_input_event(self, mouse_pos, event)
		
		## TODO - terrain events
		
		var selected = []
		for selectable in get_tree().get_nodes_in_group("selectable_objects"):
			if selectable.has_mouse:
				selected.push_back(selectable)
		if not selected.empty():
			context_panel.objects_input_event(self, selected, event)