@tool
extends EditorPlugin

# --- UI refs ---
var _dock: PanelContainer
var _start_number: SpinBox
var _selected_count_label: Label
var _apply_btn: Button
var _preview_list: VBoxContainer

func _enter_tree() -> void:
	_build_ui()
	add_control_to_dock(DOCK_SLOT_RIGHT_BR, _dock)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	_update_selection_info()

func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.free()

# ---------------- UI ----------------

func _build_ui() -> void:
	_dock = PanelContainer.new()
	_dock.name = "AutoObjId"
	_dock.custom_minimum_size = Vector2(250, 0)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_dock.add_child(root)

	# Title
	var title := Label.new()
	title.text = "Auto ObjId"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# Selection count display
	var count_row := HBoxContainer.new()
	count_row.add_child(_mk_label("Selected objects:"))
	_selected_count_label = Label.new()
	_selected_count_label.text = "0"
	_selected_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selected_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_row.add_child(_selected_count_label)
	root.add_child(count_row)

	# Starting number input
	var start_row := HBoxContainer.new()
	start_row.add_child(_mk_label("Starting ObjId:"))
	_start_number = SpinBox.new()
	_start_number.min_value = 0
	_start_number.max_value = 999999
	_start_number.step = 1
	_start_number.value = 1
	_start_number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_row.add_child(_start_number)
	root.add_child(start_row)

	# Apply button
	_apply_btn = Button.new()
	_apply_btn.text = "Apply ObjId to Selection"
	_apply_btn.disabled = true
	_apply_btn.pressed.connect(_on_apply_pressed)
	root.add_child(_apply_btn)

	# Preview list title
	var preview_title := Label.new()
	preview_title.text = "Selected Objects Preview:"
	preview_title.add_theme_font_size_override("font_size", 12)
	preview_title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	root.add_child(preview_title)

	# Preview list container with scroll
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_list = VBoxContainer.new()
	_preview_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_preview_list)
	root.add_child(scroll)

	# Info text
	var info := Label.new()
	info.text = "Select objects with ObjId/ObjID properties\nto automatically assign sequential IDs."
	info.add_theme_font_size_override("font_size", 10)
	info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.9))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(info)

func _mk_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

# ---------------- Selection handling ----------------

func _on_selection_changed() -> void:
	_update_selection_info()

func _update_selection_info() -> void:
	var sel := EditorInterface.get_selection()
	var selected_nodes := sel.get_selected_nodes()
	var valid_objects := _get_valid_objects(selected_nodes)
	
	_selected_count_label.text = str(valid_objects.size())
	_apply_btn.disabled = valid_objects.size() == 0
	
	_update_preview_list(valid_objects)

func _update_preview_list(valid_objects: Array[Node]) -> void:
	"""Update the preview list showing the first 10 selected objects with their current ObjId"""
	# Clear existing items
	for child in _preview_list.get_children():
		child.queue_free()
	
	if valid_objects.size() == 0:
		var no_selection := Label.new()
		no_selection.text = "No objects with ObjId properties selected"
		no_selection.add_theme_font_size_override("font_size", 12)
		no_selection.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
		no_selection.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_preview_list.add_child(no_selection)
		return
	
	# Sort by position for top-down view: top to bottom (Z), then left to right (X)
	var sorted_objects := valid_objects.duplicate()
	sorted_objects.sort_custom(_sort_by_position)
	
	# Show first 10 objects
	var max_show: int = min(10, sorted_objects.size())
	for i in range(max_show):
		var node: Node = sorted_objects[i]
		var current_objid := _get_objid_from_node(node)
		
		var item_container := HBoxContainer.new()
		
		# Object name
		var name_label := Label.new()
		name_label.text = node.name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		item_container.add_child(name_label)
		
		# Current ObjId
		var objid_label := Label.new()
		objid_label.text = "ObjId: %d" % current_objid
		objid_label.add_theme_font_size_override("font_size", 12)
		objid_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 1.0))
		objid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		item_container.add_child(objid_label)
		
		_preview_list.add_child(item_container)
	
	# Show "and X more..." if there are more than 10
	if sorted_objects.size() > 10:
		var more_label := Label.new()
		more_label.text = "... and %d more objects" % (sorted_objects.size() - 10)
		more_label.add_theme_font_size_override("font_size", 11)
		more_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
		more_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_preview_list.add_child(more_label)

func _get_valid_objects(nodes: Array) -> Array[Node]:
	"""Get all selected nodes that have ObjId or ObjID properties"""
	var valid: Array[Node] = []
	for node in nodes:
		if _has_objid_property(node):
			valid.append(node)
	return valid

func _has_objid_property(node: Node) -> bool:
	"""Check if a node has ObjId or ObjID property"""
	return "ObjId" in node or "ObjID" in node

func _sort_by_position(a: Node, b: Node) -> bool:
	"""Sort nodes by position for top-down view: top to bottom (Z), then left to right (X)"""
	# Only sort Node3D objects by position, fall back to name for others
	if a is Node3D and b is Node3D:
		var pos_a: Vector3 = (a as Node3D).global_position
		var pos_b: Vector3 = (b as Node3D).global_position
		
		# First sort by Z (top to bottom in top-down view)
		# Smaller Z values are "up" (north), larger Z values are "down" (south)
		if abs(pos_a.z - pos_b.z) > 0.01:  # Small tolerance for floating point comparison
			return pos_a.z < pos_b.z
		
		# If Z positions are very similar, sort by X (left to right)
		# Smaller X values are "left" (west), larger X values are "right" (east)
		return pos_a.x < pos_b.x
	else:
		# Fall back to name sorting for non-Node3D objects
		return a.name < b.name

func _get_objid_from_node(node: Node) -> int:
	"""Get the current ObjId/ObjID value from a node, returns -1 if not found or invalid"""
	if "ObjID" in node:
		var val = node.get("ObjID")
		if typeof(val) == TYPE_INT:
			return val as int
	elif "ObjId" in node:
		var val = node.get("ObjId")
		if typeof(val) == TYPE_INT:
			return val as int
	return -1

func _set_objid_on_node(node: Node, objid: int) -> void:
	"""Set ObjID/ObjId on a node"""
	if "ObjID" in node:
		node.set("ObjID", objid)
	elif "ObjId" in node:
		node.set("ObjId", objid)

# ---------------- Core functionality ----------------

func _on_apply_pressed() -> void:
	var sel := EditorInterface.get_selection()
	var selected_nodes := sel.get_selected_nodes()
	var valid_objects := _get_valid_objects(selected_nodes)
	
	if valid_objects.size() == 0:
		push_warning("AutoObjId: No objects with ObjId/ObjID properties selected.")
		return
	
	var starting_id := int(_start_number.value)
	var current_id := starting_id
	
	# Sort by position for top-down view: top to bottom (Z), then left to right (X)
	valid_objects.sort_custom(_sort_by_position)
	
	for node in valid_objects:
		_set_objid_on_node(node, current_id)
		print("AutoObjId: Set %s.ObjId = %d" % [node.name, current_id])
		current_id += 1
	
	print("AutoObjId: Applied ObjId to %d objects (starting from %d)" % [valid_objects.size(), starting_id])
	
	# Refresh the preview list to show updated values
	_update_preview_list(valid_objects)