extends "ContextBase.gd"

func map_markers_input(map, map_markers, event):
	if event.is_action_pressed("click_select"):
		var marker = map_markers.front()
		var map_object = marker.get_parent()
		map_object.queue_free()