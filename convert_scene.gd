# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
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


func get_global_transform(node: Node):
	if not (node is Node3D):
		return Transform3D.IDENTITY
	var n3d = node as Node3D
	if node.get_parent() == null or n3d.top_level:
		return n3d.transform
	return get_global_transform(node.get_parent()) * n3d.transform


func recursive_print(pkgasset, node: Node, indent: String = ""):
	var fnstr = "" if str(node.scene_file_path) == "" else (" (" + str(node.scene_file_path) + ")")
	pkgasset.log_debug(indent + str(node.name) + ": owner=" + str(node.owner.name if node.owner != null else "") + fnstr)
	#pkgasset.log_debug(indent + str(node.name) + str(node) + ": owner=" + str(node.owner.name if node.owner != null else "") + str(node.owner) + fnstr)
	var new_indent: String = indent + "  "
	for c in node.get_children():
		recursive_print(pkgasset, c, new_indent)


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
				asset.log_fail("Stripped object " + asset.type + " would be added to arr " + str(asset.meta.guid) + "/" + str(asset.fileID))
			if is_prefab:
				if asset.type == "PrefabInstance":
					var target_prefab_meta = asset.meta.lookup_meta(asset.source_prefab)
					asset.meta.prefab_main_gameobject_id = pkgasset.parsed_meta.xor_or_stripped(target_prefab_meta.prefab_main_gameobject_id, asset.fileID)
					asset.meta.prefab_main_transform_id = pkgasset.parsed_meta.xor_or_stripped(target_prefab_meta.prefab_main_transform_id, asset.fileID)
				else:
					asset.meta.prefab_main_gameobject_id = asset.fileID
					asset.meta.prefab_main_transform_id = asset.transform.fileID
			arr.push_back(asset)

	if arr.is_empty():
		pkgasset.log_fail("Scene " + pkgasset.pathname + " has no nodes.")
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
			pkgasset.log_warn("Prefab " + pkgasset.pathname + " has multiple roots. picking lowest.")
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

	var node_state: Object = scene_node_state_class.new(pkgasset.parsed_meta.get_database(), pkgasset.parsed_meta, scene_contents)

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
				env.background_energy_multiplier = eng
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
				occlusion.occluder = SphereOccluder3D.new()  # wrong type
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
			pkgasset.log_fail("Not able to handle multiple skeletons with no parent in a prefab")
		else:
			for noparskel in skelleys_with_no_parent:
				scene_contents.add_child(noparskel.godot_skeleton, true)
	#var fileid_to_prefab_nodepath = {}.duplicate()
	#var fileid_to_prefab_ref = {}.duplicate()
	#pkgasset.parsed_meta.fileid_to_prefab_nodepath = {}
	#pkgasset.parsed_meta.fileid_to_prefab_ref = {}

	for asset in pkgasset.parsed_asset.assets.values():
		if str(asset.type) == "SkinnedMeshRenderer":
			var skelley: RefCounted = asset.get_skelley(node_state)
			if skelley != null:
				skelley.skinned_mesh_renderers.append(asset)
	for skelley in skelleys_with_no_parent:
		for smr in skelley.skinned_mesh_renderers:
			var ret: Node = smr.create_skinned_mesh(node_state)
			if ret != null:
				smr.log_debug("Finally added SkinnedMeshRenderer " + str(smr.uniq_key) + " into top-level Skeleton " + str(scene_contents.get_path_to(ret)))

	node_state.env = env
	node_state.set_main_name_map(node_state.prefab_state.gameobject_name_map, node_state.prefab_state.prefab_gameobject_name_map)

	arr.sort_custom(customComparison)
	for asset in arr:
		if asset.is_stripped:
			asset.log_fail("Stripped object " + asset.type + " added to arr " + str(asset.meta.guid) + "/" + str(asset.fileID))
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
			# asset.log_debug(str(asset) + " position " + str(asset.transform.godot_transform))
			var new_root: Node3D = asset.create_godot_node(node_state, scene_contents)
			if scene_contents == null:
				assert(is_prefab)
				scene_contents = new_root
				node_state = node_state.state_with_owner(scene_contents)
			else:
				if is_prefab:
					asset.log_fail("May be a prefab with multiple roots, or hit unusual case.")
				pass
				# assert(not is_prefab)
			if asset.type == "PrefabInstance":
				node_state.add_prefab_to_parent_transform(0, asset.fileID)

	# scene_contents = node_state.owner
	if scene_contents == null:
		pkgasset.log_fail("Failed to parse scene " + pkgasset.pathname)
		return null

	process_lod_groups(scene_contents, ps)

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
					env.background_energy_multiplier = camera.environment.background_energy_multiplier
				for mono in node_state.get_components(camera_obj, "MonoBehaviour"):
					if str(mono.monoscript[2]) == "948f4100a11a5c24981795d21301da5c":  # PostProcessingLayer
						pp_layer_bits = mono.keys.get("volumeLayer.m_Bits", mono.keys.get("volumeLayer", {}).get("m_Bits", 0))
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
						mono.log_debug("Would merge PostProcessingVolume profile " + str(mono.keys.get("sharedProfile")))

	var light_probes: Array[Node] = scene_contents.find_children("*", "LightmapProbe")
	var heights = []

	for probe in light_probes:
		heights.append(get_global_transform(probe).origin.y)
	# LightmapProbe operations are non-linear.
	# Godot becomes very slow if you have 2600 probes, and it crashes with "Out of memory" if you have more than 2700
	# (Out of memory due to resizing an array over 1 billion elements, not due to actual memory consumption)
	# So we will limit probes scene-wide to 2500.
	var did_warn_too_many: bool = false
	const max_probe_before_sampling: int = 1500
	const max_probe_after_sampling: int = 300
	const probe_sample_denom: int = 13
	var max_height: float = 1000.0
	if len(heights) > max_probe_before_sampling:
		heights.sort()
		max_height = heights[max_probe_before_sampling]
	if len(heights) > max_probe_after_sampling:
		var min_x: int = min(len(heights), max_probe_before_sampling)
		var probe_sample_num: int = max_probe_after_sampling * probe_sample_denom / min_x
		pkgasset.log_warn("Deleting " + str(len(heights) - max_probe_before_sampling) + " light probes above y=" + str(max_height) + " to prevent engine bug.")
		pkgasset.log_warn("Sampling " + str(min_x * probe_sample_num / probe_sample_denom) + " remaining light probes to prevent engine bug.")
		var i: int = 0
		for probe in light_probes:
			var delete_probe: bool = get_global_transform(probe).origin.y >= max_height
			if delete_probe:
				pkgasset.log_debug("Deleting probe " + str(probe.get_parent().name + "/" + str(probe.name)) + " at " + str(probe.transform.origin))
			else:
				i += 1
				if (i % probe_sample_denom) >= probe_sample_num:
					delete_probe = true
					pkgasset.log_debug("Deleting/sampling probe " + str(probe.get_parent().name + "/" + str(probe.name)) + " at " + str(probe.transform.origin))
			if delete_probe:
				if probe.owner != scene_contents:
					pkgasset.log_fail("Unable to delete light probe at " + str(probe.transform.origin) + " because of scene instance. Please modify " + str(probe.owner.scene_file_path))
				probe.owner = null
				probe.get_parent().remove_child(probe)
				probe.queue_free()

	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(scene_contents)
	pkgasset.log_debug("Finished packing " + pkgasset.pathname + " with " + str(scene_contents.get_child_count()) + " nodes.")
	recursive_print(pkgasset, scene_contents)
	var editable_hack: Dictionary = packed_scene._bundled
	for ecpath in ps.prefab_instance_paths:
		pkgasset.log_debug(str(editable_hack.keys()))
		editable_hack.get("editable_instances").push_back(str(ecpath))
	packed_scene._bundled = editable_hack
	packed_scene.pack(scene_contents)
	#pkgasset.log_debug(packed_scene)
	#var pi = packed_scene.instance(PackedScene.GEN_EDIT_STATE_INSTANCE)
	#pkgasset.log_debug(pi.get_child_count())
	return packed_scene


func process_lod_groups(scene_contents: Node, ps: RefCounted):

	for lod_group in ps.lod_groups:
		var prev_distance_m: float = 0.0
		var prev_fade_m: float = 0.0
		# Formula: 0.65 / screenRelativeHeight * m_Size = distance_in_meters
		# For example, 0.65 / 0.8125 * 5 = 4.0
		# or 0.65 / 0.216 * 1 = 3.0
		# Unity's scale factor is confusingly aspect ratio dependent.
		# We scale by another factor or 2 to account for 16:9 aspect ratio.
		# It seems to make LOD switches less noticeable.
		var size_m = lod_group.keys.get("m_Size", 1.0)
		var animate_crossfade: bool = lod_group.keys.get("m_AnimateCrossFading", 0) == 1
		for lod in lod_group.keys.get("m_LODs", []):
			var screen_relative_height: float = lod.get("screenRelativeHeight", 1.0)
			var distance_m = 2.0 * 0.65 / screen_relative_height * size_m
			var fade_width: float = lod.get("fadeTransitionWidth", 0.0)
			if animate_crossfade:
				fade_width = 0.5 # Hardcode half a meter of fade overlap. No idea...
			else:
				fade_width = fade_width * (distance_m - prev_distance_m) # fraction of the length of this LOD.
			for renderer_ref_dict in lod.get("renderers", []):
				var renderer_ref: Array
				if typeof(renderer_ref_dict) == TYPE_DICTIONARY:
					renderer_ref = renderer_ref_dict["renderer"]
				var np: NodePath = lod_group.meta.fileid_to_nodepath.get(renderer_ref[1], lod_group.meta.prefab_fileid_to_nodepath.get(renderer_ref[1], NodePath()))
				if not np.is_empty():
					var node: Node = scene_contents.get_node(np)
					var visual_inst: VisualInstance3D = node as VisualInstance3D
					if node != null and visual_inst == null:
						visual_inst = node.get_child(0) as VisualInstance3D
					if visual_inst != null:
						visual_inst.visibility_range_begin = prev_distance_m
						visual_inst.visibility_range_begin_margin = prev_fade_m
						visual_inst.visibility_range_end = distance_m
						visual_inst.visibility_range_end_margin = fade_width
						# Dependencies seems buggy, so we use Self and don't set the visibility parent.
						#visual_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
						# Self is really hard to work with as it has overlap...
						# So we'll use DISABLED for now... which should act like low-water mark / high-water mark.
						visual_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			prev_distance_m = distance_m
			prev_fade_m = fade_width
