class_name UnidotCamera extends UnidotBehaviour

func get_godot_type() -> String:
	return "Camera3D"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	var par: Node = new_parent
	var texref: Array = keys.get("m_TargetTexture", [null, 0, null, null])
	var rendertex: UnidotObject = null
	if texref[1] != 0:
		rendertex = meta.lookup(texref)  # FIXME: This might not find separate assets.
	if rendertex != null:
		var viewport: SubViewport = SubViewport.new()
		viewport.name = "SubViewport"
		new_parent.add_child(viewport, true)
		viewport.owner = state.owner
		viewport.size = Vector2(rendertex.keys.get("m_Width"), rendertex.keys.get("m_Height"))
		if keys.get("m_AllowMSAA", 0) == 1:
			if rendertex.keys.get("m_AntiAliasing", 0) == 1:
				viewport.msaa = Viewport.MSAA_8X
		viewport.use_occlusion_culling = keys.get("m_OcclusionCulling", 0)
		viewport.clear_mode = (SubViewport.CLEAR_MODE_ALWAYS if keys.get("m_ClearFlags") < 3 else SubViewport.CLEAR_MODE_NEVER)
		# Godot is always HDR? if keys.get("m_AllowHDR", 0) == 1
		par = viewport
	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera"
	if keys.get("m_ClearFlags") == 2:
		var cenv: Environment = Environment.new() if state.env == null else state.env.duplicate()
		cam.environment = cenv
		cenv.background_mode = Environment.BG_COLOR
		var ccol: Color = keys.get("m_BackGroundColor", Color.BLACK)
		var eng = max(ccol.r, max(ccol.g, ccol.b))
		if eng > 1:
			ccol /= eng
		else:
			eng = 1
		cenv.background_color = ccol
		cenv.background_energy_multiplier = eng
	assign_object_meta(cam)
	state.add_child(cam, par, self)
	cam.transform = Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)))
	return cam

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	if uprops.has("m_CullingMask"):
		# Bits 24-31 seem to be reserved in Godot. Merge layers 24-31 into 16-23.
		# Otherwise, reflection probes and lightmaps will see gizmos.
		# If this is causing problems for you, submit an issue so we can figure out a good setting
		var layer: int = uprops.get("m_CullingMask").get("m_Bits")
		outdict["cull_mask"] = (layer & ~(255 << 24)) | ((layer >> 8) & (255 << 16))
	elif uprops.has("m_CullingMask.m_Bits"):
		var layer: int = uprops.get("m_CullingMask").get("m_Bits")
		outdict["cull_mask"] = (layer & ~(255 << 24)) | ((layer >> 8) & (255 << 16))
	if uprops.has("far clip plane"):
		outdict["far"] = uprops.get("far clip plane")
	if uprops.has("near clip plane"):
		outdict["near"] = uprops.get("near clip plane")
	if uprops.has("field of view"):
		outdict["fov"] = uprops.get("field of view")
	if uprops.has("m_TagString"):
		outdict["current"] = uprops["m_TagString"] == "MainCamera"
	if uprops.has("orthographic"):
		outdict["projection"] = Camera3D.PROJECTION_ORTHOGONAL if uprops.get("orthographic") else Camera3D.PROJECTION_PERSPECTIVE
	if uprops.has("orthographic size"):
		if uprops.get("orthographic", 0):
			outdict["size"] = min(0.000011, uprops.get("orthographic size"))
	return outdict
