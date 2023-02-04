@tool
extends Resource

const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
const scene_node_state_class: GDScript = preload("./scene_node_state.gd")


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


func recursive_print(node: Node, indent: String = ""):
	var fnstr = "" if str(node.scene_file_path) == "" else (" (" + str(node.scene_file_path) + ")")
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
			if asset.is_non_stripped_prefab_reference:
				continue  # We don't want these.
			if asset.is_stripped:
				push_error(
					(
						"Stripped object "
						+ asset.type
						+ " would be added to arr "
						+ str(asset.meta.guid)
						+ "/"
						+ str(asset.fileID)
					)
				)
			if is_prefab:
				if asset.type == "PrefabInstance":
					var target_prefab_meta = asset.meta.lookup_meta(asset.source_prefab)
					asset.meta.prefab_main_gameobject_id = target_prefab_meta.prefab_main_gameobject_id ^ asset.fileID
					asset.meta.prefab_main_transform_id = target_prefab_meta.prefab_main_transform_id ^ asset.fileID
				else:
					asset.meta.prefab_main_gameobject_id = asset.fileID
					asset.meta.prefab_main_transform_id = asset.transform.fileID
			arr.push_back(asset)

	if arr.is_empty():
		push_error("Scene " + pkgasset.pathname + " has no nodes.")
		return
	var env: Environment = null
	var bakedlm: LightmapGI = null
	var navregion: NavigationRegion3D = null
	var occlusion: OccluderInstance3D = null
	var dirlight: DirectionalLight3D = null
	var scene_contents: Node3D = null
	var node_map: Dictionary = {}
	if is_prefab:
		if len(arr) > 1:
			push_error("Prefab " + pkgasset.pathname + " has multiple roots. picking lowest.")
		arr.sort_custom(smallestTransform)
		arr = [arr[0]]
	else:
		scene_contents = Node3D.new()
		scene_contents.name = "RootNode3D"
		var world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		env = Environment.new()
		world_env.environment = env
		# TODO: We need to convert all PostProcessingProfile assets into godot Environment objects
		# Then, store an array of list of node path, weight, asset and layer_id.
		# Then, in prefab logic, concat the paths into the outer scene.
		# finally, the actual scene will loop through all environments and add them by wieght
		# then, we can assign the final world environment from all this.
		scene_contents.add_child(world_env, true)
		world_env.owner = scene_contents
		bakedlm = LightmapGI.new()
		bakedlm.name = "LightmapGI"
		scene_contents.add_child(bakedlm, true)
		bakedlm.owner = scene_contents
		navregion = NavigationRegion3D.new()
		navregion.name = "NavigationRegion3D"
		scene_contents.add_child(navregion, true)
		navregion.owner = scene_contents
		occlusion = OccluderInstance3D.new()
		occlusion.name = "OccluderInstance3D"
		scene_contents.add_child(occlusion, true)
		occlusion.owner = scene_contents
		dirlight = DirectionalLight3D.new()
		dirlight.name = "DirectionalLight3D"
		scene_contents.add_child(dirlight, true)
		dirlight.owner = scene_contents
		dirlight.visible = false

	pkgasset.parsed_meta.calculate_prefab_nodepaths_recursive()

	var node_state: Object = scene_node_state_class.new(
		pkgasset.parsed_meta.get_database(), pkgasset.parsed_meta, scene_contents
	)

	var ps: RefCounted = node_state.prefab_state
	for asset in pkgasset.parsed_asset.assets.values():
		var parent: RefCounted = null  # UnityTransform
		if asset.is_stripped:
			pass  # Ignore stripped components.
		elif asset.is_non_stripped_prefab_reference:
			var prefab_instance_id: int = asset.prefab_instance[1]
			var prefab_source_object: int = asset.prefab_source_object[1]
			if not ps.non_stripped_prefab_references.has(prefab_instance_id):
				ps.non_stripped_prefab_references[prefab_instance_id] = [].duplicate()
			ps.non_stripped_prefab_references[prefab_instance_id].push_back(asset)
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
			var c: Color = asset.keys.get("m_FogColor", Color.WHITE)
			var max_c: float = max(c.r, max(c.g, c.b))
			if max_c > 1.0:
				c /= max_c
			else:
				max_c = 1.0
			env.fog_light_color = c
			env.fog_light_energy = max_c
			if asset.keys.get("m_FogMode", 3) == 1:  # Linear
				const TARGET_FOG_DENSITY = 0.05
				env.fog_density = -log(TARGET_FOG_DENSITY) / asset.keys.get("m_LinearFogEnd", 0.0)
			else:
				env.fog_density = asset.keys.get("m_FogDensity", 0.0)
			var sun: Array = asset.keys.get("m_Sun", [null, 0, null, null])
			if sun[1] != 0:
				scene_contents.remove_child(dirlight)
				dirlight = null
			var sky_material: Variant = pkgasset.parsed_meta.get_godot_resource(asset.keys.get("m_SkyboxMaterial"))
			if sky_material == null:
				# Just use a default skybox for now...
				sky_material = ProceduralSkyMaterial.new()
				sky_material.sky_top_color = Color(0.454902, 0.678431, 0.87451, 1)
				sky_material.sky_horizon_color = Color(0.894118, 0.952941, 1, 1)
				sky_material.sky_curve = 0.0731028
				sky_material.ground_bottom_color = Color(0.454902, 0.470588, 0.490196, 1)
				sky_material.ground_horizon_color = Color(1, 1, 1, 1)
			var ambient_mode: int = asset.keys.get("m_AmbientMode", 0)
			if sky_material != null:
				env.background_mode = Environment.BG_SKY
				env.sky = Sky.new()
				env.sky.sky_material = sky_material
			if ambient_mode == 0 and sky_material == null:
				env.background_mode = Environment.BG_COLOR
				var ccol: Color = asset.keys.get("m_AmbientSkyColor", Color.BLACK)
				var eng: float = max(ccol.r, max(ccol.g, ccol.b))
				if eng > 1:
					ccol /= eng
				else:
					eng = 1
				env.background_color = ccol
				env.background_energy = eng
				env.ambient_light_color = ccol
				env.ambient_light_energy = eng
				env.ambient_light_sky_contribution = 0
			elif ambient_mode == 1 or ambient_mode == 2 or ambient_mode == 3:
				# modes 1 or 2 are technically a gradient (2 is blank dropdown)
				# mode 3 is solid color (same as 0 + null skybox material)
				var ccol: Color = asset.keys.get("m_AmbientSkyColor", Color.BLACK)
				var eng: float = max(ccol.r, max(ccol.g, ccol.b))
				if eng > 1:
					ccol /= eng
				else:
					eng = 1
				env.ambient_light_color = ccol
				env.ambient_light_energy = eng
				env.ambient_light_sky_contribution = 0
		elif asset.type == "LightmapSettings":
			var lda: Array = asset.keys.get("m_LightingDataAsset", [null, 0, null, null])
			if lda[1] == 0:
				scene_contents.remove_child(bakedlm)
				bakedlm = null
		elif asset.type == "NavMeshSettings":
			var nmd: Array = asset.keys.get("m_NavMeshData", [null, 0, null, null])
			if nmd[1] == 0:
				scene_contents.remove_child(navregion)
				navregion = null
			else:
				navregion.navmesh = NavigationMesh.new()
		elif asset.type == "OcclusionCullingSettings":
			var ocd: Array = asset.keys.get("m_OcclusionCullingData", [null, 0, null, null])
			if ocd[1] == 0:
				scene_contents.remove_child(occlusion)
				occlusion = null
			else:
				occlusion.occluder = Occluder3D.new()
		elif asset.type != "GameObject":
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
		# assert(not is_prefab)
		if scene_contents == null:
			push_error("Not able to handle multiple skeletons with no parent in a prefab")
		else:
			for noparskel in skelleys_with_no_parent:
				scene_contents.add_child(noparskel.godot_skeleton, true)
	#var fileid_to_prefab_nodepath = {}.duplicate()
	#var fileid_to_prefab_ref = {}.duplicate()
	#pkgasset.parsed_meta.fileid_to_prefab_nodepath = {}
	#pkgasset.parsed_meta.fileid_to_prefab_ref = {}

	node_state.env = env
	node_state.set_main_name_map(
		node_state.prefab_state.gameobject_name_map, node_state.prefab_state.prefab_gameobject_name_map
	)

	arr.sort_custom(customComparison)
	for asset in arr:
		if asset.is_stripped:
			push_error(
				"Stripped object " + asset.type + " added to arr " + str(asset.meta.guid) + "/" + str(asset.fileID)
			)
		var skel: RefCounted = null
		# FIXME: PrefabInstances pointing to a scene whose root node is a Skeleton may not work.
		if asset.transform != null:
			skel = node_state.uniq_key_to_skelley.get(asset.transform.uniq_key, null)
		if skel != null:
			if len(skelleys_with_no_parent) > 1:
				# If a toplevel node is part of a skeleton, insert the skeleton between the actual root and the toplevel node.
				scene_contents.add_child(skel.godot_skeleton, true)
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
				if is_prefab:
					push_warning("May be a prefab with multiple roots, or hit unusual case.")
				pass
				# assert(not is_prefab)
			if asset.type == "PrefabInstance":
				node_state.add_prefab_to_parent_transform(0, asset.fileID)

	# scene_contents = node_state.owner
	if scene_contents == null:
		push_error("Failed to parse scene " + pkgasset.pathname)
		return null

	for asset in pkgasset.parsed_asset.assets.values():
		if str(asset.type) == "SkinnedMeshRenderer":
			var ret: Node = asset.create_skinned_mesh(node_state)
			if ret != null:
				print(
					(
						"Finally added SkinnedMeshRenderer "
						+ str(asset.uniq_key)
						+ " into Skeleton"
						+ str(scene_contents.get_path_to(ret))
					)
				)

	for animtree in node_state.prefab_state.animator_node_to_object:
		var obj: RefCounted = node_state.prefab_state.animator_node_to_object[animtree]  # UnityAnimator
		# var controller_object = pkgasset.parsed_meta.lookup(obj.keys["m_Controller"])
		# If not found, we can't recreate the animationLibrary
		obj.setup_post_children(animtree)

	if not is_prefab:
		# Remove redundant directional light.
		if dirlight != null:
			var x: LightmapGI = null
			var fileids: Array = [].duplicate()
			for light in node_state.find_objects_of_type("Light"):
				if light.lightType == 1:  # Directional
					scene_contents.remove_child(dirlight)
					dirlight = null
		var main_camera: Camera3D = null
		var pp_layer_bits: int = 0
		for camera_obj in node_state.find_objects_of_type("Camera"):
			#if not (camera.get_parent() is Viewport) and camera.visible:
			var go: RefCounted = node_state.get_gameobject(camera_obj)
			var camera: Camera3D = null
			if camera_obj.enabled and go.enabled:
				# This is a main camera
				camera = node_state.get_godot_node(camera_obj)
			if camera != null:
				main_camera = camera
				if camera.environment != null:
					env.background_mode = camera.environment.background_mode
					env.background_color = camera.environment.background_color
					env.background_energy = camera.environment.background_energy
				for mono in node_state.get_components(camera_obj, "MonoBehaviour"):
					if str(mono.monoscript[2]) == "948f4100a11a5c24981795d21301da5c":  # PostProcessingLayer
						pp_layer_bits = mono.keys.get(
							"volumeLayer.m_Bits", mono.keys.get("volumeLayer", {}).get("m_Bits", 0)
						)
						break
				break
		for mono in node_state.find_objects_of_type("MonoBehaviour"):
			if str(mono.monoscript[2]) == "8b9a305e18de0c04dbd257a21cd47087":  # PostProcessingVolume
				var go: RefCounted = node_state.get_gameobject(mono)
				if not mono.enabled or not go.enabled:
					continue
				if ((1 << go.keys.get("m_Layer")) & pp_layer_bits) != 0:
					# Enabled PostProcessingVolume with matching layer.
					if mono.keys.get("isGlobal", 0) == 1 and mono.keys.get("weight", 0) > 0.0:
						print("Would merge PostProcessingVolume profile " + str(mono.keys.get("sharedProfile")))

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
