class_name UnidotTextMesh extends UnidotRenderer

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	var text: String = keys.get("m_Text", "")

	var label := Label3D.new()
	label.text = text
	label.name = text.get_slice("\n", 0).strip_edges().validate_node_name().substr(50).strip_edges()
	state.add_child(label, new_parent, self)
	label.outline_size = 4
	return label

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = super.convert_properties(node, uprops) # UnidotRenderer
	var color: Color
	if uprops.has("m_Color"):
		var v: Variant = uprops.get("m_Color", Color())
		if typeof(v) == TYPE_COLOR:
			color = uprops.get("m_Color", Color())
		elif typeof(v) == TYPE_DICTIONARY:
			var color32: int = v.get("rgba")
			color = Color(((color32 & 0xff000000) >> 24) / 255.0, ((color32 & 0xff0000) >> 16) / 255.0, ((color32 & 0xff00) >> 8) / 255.0, (color32 & 0xff) / 255.0)
		outdict["modulate"] = color
	if uprops.has("m_Alignment"):
		match uprops.get("m_Alignment", 0):
			0:
				outdict["horizontal_alignment"] = HORIZONTAL_ALIGNMENT_LEFT
			1:
				outdict["horizontal_alignment"] = HORIZONTAL_ALIGNMENT_CENTER
			2:
				outdict["horizontal_alignment"] = HORIZONTAL_ALIGNMENT_RIGHT
	var font_size: int = 13
	if node as Label3D != null:
		font_size = node.font_size
	if uprops.has("m_FontSize"):
		font_size = uprops.get("m_FontSize", 0)
		if font_size <= 0:
			font_size = 13 # ?? default Arial?
		outdict["font_size"] = font_size
	if uprops.has("m_LineSpacing"):
		var line_spacing: float = uprops.get("m_LineSpacing")
		outdict["line_spacing"] = (line_spacing - 1.0) * font_size * 1.5 # Not sure why the 1.5 but it seems to be.
	if uprops.has("m_Font"):
		outdict["font"] = meta.get_godot_resource(uprops.get("m_Font", [null, 0, "", 0]))
	if uprops.has("m_CharacterSize"):
		outdict["pixel_size"] = 0.005 * uprops.get("m_CharacterSize", 1)
	if uprops.has("m_OffsetZ"):
		outdict["position"] = Vector3(0, 0, uprops.get("m_OffsetZ", 0))
	if uprops.has("m_Anchor"):
		var anchor: int = uprops.get("m_Anchor", 0)
		if anchor >= 0 and anchor <= 2:
			outdict["vertical_alignment"] = VERTICAL_ALIGNMENT_TOP
		if anchor >= 3 and anchor <= 5:
			outdict["vertical_alignment"] = VERTICAL_ALIGNMENT_CENTER
		if anchor >= 6 and anchor <= 8:
			outdict["vertical_alignment"] = VERTICAL_ALIGNMENT_BOTTOM
		# In Godot, Horizontal alignment is tied to left/right anchor.
	return outdict
