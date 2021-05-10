@tool
extends Resource

const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")

func customComparison(a, b):
	if typeof(a) != typeof(b):
		return typeof(a) < typeof(b)
	elif a.transform != null && b.transform != null:
		return a.transform.rootOrder < b.transform.rootOrder
	else:
		return b.fileID < a.fileID

func smallestTransform(a, b):
	if typeof(a) != typeof(b):
		return typeof(a) < typeof(b)
	elif a.transform != null && b.transform != null:
		return a.transform.fileID < b.transform.fileID
	else:
		return b.fileID < a.fileID

func recursive_print(node:Node, indent:String=""):
	var fnstr = "" if str(node.filename) == "" else (" (" + str(node.filename) + ")")
	print(indent + str(node.name) + ": owner=" + str(node.owner.name if node.owner != null else "") + fnstr)
	#print(indent + str(node.name) + str(node) + ": owner=" + str(node.owner.name if node.owner != null else "") + str(node.owner) + fnstr)
	var new_indent: String = indent + "  "
	for c in node.get_children():
		recursive_print(c, new_indent)

func pack_scene(pkgasset, is_prefab) -> PackedScene:
	#for asset in pkgasset.parsed_asset.assets.values():
	#	if asset.type == "GameObject" and asset.toplevel:
	#		pass

	var arr: Array = [].duplicate()

	for asset in pkgasset.parsed_asset.assets.values():
		if (asset.type == "GameObject" or asset.type == "PrefabInstance") and asset.toplevel:
			if asset.is_stripped:
				push_error("Stripped object " + asset.type + " would be added to arr " + str(asset.meta.guid) + "/" + str(asset.fileID))
			arr.push_back(asset)

	if arr.is_empty():
		push_error("Scene " + pkgasset.pathname + " has no nodes.")
		return
	var env: Environment = null
	var bakedlm: BakedLightmap = null
	var navregion: NavigationRegion3D = null
	var occlusion: OccluderInstance3D = null
	var dirlight: DirectionalLight3D = null
	var scene_contents: Node3D = null
	var main_camera: Reference = null # unity object
	if is_prefab:
		if len(arr) > 1:
			push_error("Prefab " + pkgasset.pathname + " has multiple roots. picking lowest.")
		arr.sort_custom(smallestTransform)
		arr = [arr[0]]
	else:
		scene_contents = Node3D.new()
		scene_contents.name = "RootNode3D"
		var world_env = WorldEnvironment.new()
		env = Environment.new()
		world_env.environment = env
		# TODO: We need to convert all PostProcessingProfile assets into godot Environment objects
		# Then, store an array of list of node path, weight, asset and layer_id.
		# Then, in prefab logic, concat the paths into the outer scene.
		# finally, the actual scene will loop through all environments and add them by wieght
		# then, we can assign the final world environment from all this.
		scene_contents.add_child(world_env)
		world_env.owner = scene_contents
		bakedlm = BakedLightmap.new()
		scene_contents.add_child(bakedlm)
		bakedlm.owner = scene_contents
		navregion = NavigationRegion3D.new()
		scene_contents.add_child(navregion)
		navregion.owner = scene_contents
		occlusion = OccluderInstance3D.new()
		scene_contents.add_child(occlusion)
		occlusion.owner = scene_contents
		dirlight = DirectionalLight3D.new()
		scene_contents.add_child(dirlight)
		dirlight.owner = scene_contents
		dirlight.visible = false

	pkgasset.parsed_meta.calculate_prefab_nodepaths_recursive()

	var node_state: Object = object_adapter_class.create_node_state(pkgasset.parsed_meta.get_database(), pkgasset.parsed_meta, scene_contents)

	var ps: Reference = node_state.prefab_state
	for asset in pkgasset.parsed_asset.assets.values():
		var parent: Reference = null # UnityTransform
		if asset.is_stripped:
			pass # Ignore stripped components.
		elif asset.type == "Transform" or asset.type == "PrefabInstance":
			parent = asset.parent
			if parent != null and parent.is_prefab_reference:
				var prefab_instance_id: int = parent.prefab_instance[1]
				var prefab_source_object: int = parent.prefab_source_object[1]
				if not ps.transforms_by_parented_prefab.has(prefab_instance_id):
					ps.transforms_by_parented_prefab[prefab_instance_id] = {}.duplicate()
				if not ps.child_transforms_by_stripped_id.has(parent.fileID):
					ps.child_transforms_by_stripped_id[parent.fileID] = [].duplicate()
				ps.transforms_by_parented_prefab.get(prefab_instance_id)[parent.fileID] = parent
				#ps.transforms_by_parented_prefab_source_obj[str(prefab_instance_id) + "/" + str(prefab_source_object)] = parent
				ps.child_transforms_by_stripped_id[parent.fileID].push_back(asset)
			#elif parent != null and asset.type == "PrefabInstance":
			#	var uk: String = asset.parent.uniq_key
			#	if not ps.prefab_parents.has(uk):
			#		ps.prefab_parents[uk] = []
			#	ps.prefab_parents[uk].append(asset)
		elif asset.type == "RenderSettings":
			env.fog_enabled = (asset.keys.get("m_Fog", 0) == 1)
			var c: Color = asset.keys.get("m_FogColor", Color.white)
			var max_c: float = max(c.r, max(c.g, c.b))
			if max_c > 1.0:
				c /= max_c
			else:
				max_c = 1.0
			env.fog_light_color = c
			env.fog_light_energy = max_c
			if asset.keys.get("m_FogMode", 3) == 1: # Linear
				const TARGET_FOG_DENSITY = 0.05
				env.fog_density = -log(TARGET_FOG_DENSITY) / asset.keys.get("m_LinearFogEnd", 0.0)
			else:
				env.fog_density = asset.keys.get("m_FogDensity", 0.0)
		elif asset.type == "LightmapSettings":
			pass
		elif asset.type == "NavMeshSettings":
			pass
		elif asset.type == "OcclusionCullingSettings":
			pass
		elif asset.type != "GameObject":
			if asset.type == "Camera":
				main_camera = asset
			# alternatively, is it a subclass of UnityComponent?
			parent = asset.gameObject
			if parent != null and parent.is_prefab_reference:
				var prefab_instance_id: int = parent.prefab_instance[1]
				var prefab_source_object: int = parent.prefab_source_object[1]
				if not ps.gameobjects_by_parented_prefab.has(prefab_instance_id):
					ps.gameobjects_by_parented_prefab[prefab_instance_id] = {}.duplicate()
				if not ps.components_by_stripped_id.has(parent.fileID):
					ps.components_by_stripped_id[parent.fileID] = [].duplicate()
				ps.gameobjects_by_parented_prefab.get(prefab_instance_id)[parent.fileID] = parent
				#ps.gameobjects_by_parented_prefab_source_obj[str(prefab_instance_id) + "/" + str(prefab_source_object)] = parent
				ps.components_by_stripped_id[parent.fileID].push_back(asset)

	var skelleys_with_no_parent: Array = node_state.initialize_skelleys(pkgasset.parsed_asset.assets.values())

	if len(skelleys_with_no_parent) == 1:
		scene_contents = skelleys_with_no_parent[0].godot_skeleton
		scene_contents.name = "RootSkeleton"
		node_state = node_state.state_with_owner(scene_contents)
	elif len(skelleys_with_no_parent) > 1:
		assert(not is_prefab)
	#var fileid_to_prefab_nodepath = {}.duplicate()
	#var fileid_to_prefab_ref = {}.duplicate()
	#pkgasset.parsed_meta.fileid_to_prefab_nodepath = {}
	#pkgasset.parsed_meta.fileid_to_prefab_ref = {}

	arr.sort_custom(customComparison)
	for asset in arr:
		if asset.is_stripped:
			push_error("Stripped object " + asset.type + " added to arr " + str(asset.meta.guid) + "/" + str(asset.fileID))
		var skel: Reference = null
		# FIXME: PrefabInstances pointing to a scene whose root node is a Skeleton may not work.
		if asset.transform != null:
			skel = node_state.uniq_key_to_skelley.get(asset.transform.uniq_key, null)
		if skel != null:
			if len(skelleys_with_no_parent) > 1:
				# If a toplevel node is part of a skeleton, insert the skeleton between the actual root and the toplevel node.
				scene_contents.add_child(skel.godot_skeleton)
				skel.owner = scene_contents
			asset.create_skeleton_bone(node_state, skel)
		else:
			# print(str(asset) + " position " + str(asset.transform.godot_transform))
			var new_root: Node3D = asset.create_godot_node(node_state, scene_contents)
			if scene_contents == null:
				assert(is_prefab)
				scene_contents = new_root
				node_state = node_state.state_with_owner(scene_contents)
			else:
				assert(not is_prefab)

	for asset in pkgasset.parsed_asset.assets.values():
		if str(asset.type) == "SkinnedMeshRenderer":
			var ret: Node = asset.create_skinned_mesh(node_state)
			if ret != null:
				print("Finally added SkinnedMeshRenderer " + str(asset.uniq_key) + " into Skeleton" + str(scene_contents.get_path_to(ret)))

	# scene_contents = node_state.owner
	if scene_contents == null:
		push_error("Failed to parse scene " + pkgasset.pathname)
		return null
	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(scene_contents)
	print("Finished packing " + pkgasset.pathname + " with " + str(scene_contents.get_child_count()) + " nodes.")
	recursive_print(scene_contents)
	var editable_hack: Dictionary = packed_scene._bundled
	for ecpath in ps.prefab_instance_paths:
		print(str(editable_hack.keys()))
		editable_hack.get("editable_instances").push_back(str(ecpath))
	packed_scene._bundled = editable_hack
	packed_scene.pack(scene_contents)
	#print(packed_scene)
	#var pi = packed_scene.instance(PackedScene.GEN_EDIT_STATE_INSTANCE)
	#print(pi.get_child_count())
	return packed_scene
