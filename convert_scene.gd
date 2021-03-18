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


func pack_scene(pkgasset, is_prefab) -> PackedScene:
	#for asset in pkgasset.parsed_asset.assets.values():
	#	if asset.type == "GameObject" and asset.toplevel:
	#		pass

	var arr: Array = [].duplicate()

	for asset in pkgasset.parsed_asset.assets.values():
		if asset.type == "GameObject" and asset.toplevel:
			arr.push_back(asset)

	if arr.is_empty():
		printerr("Scene " + pkgasset.pathname + " has no nodes.")
		return
	var scene_contents: Node3D = null
	if is_prefab:
		if len(arr) > 1:
			printerr("Prefab " + pkgasset.pathname + " has multiple roots. picking lowest.")
		arr.sort_custom(smallestTransform)
		arr = [arr[0]]
	else:
		scene_contents = Node3D.new()
		scene_contents.name = "RootNode3D"

	var node_state: Object = object_adapter_class.create_node_state(pkgasset.parsed_meta.database, pkgasset.parsed_meta, scene_contents)
	var skelleys_with_no_parent: Array = object_adapter_class.initialize_skelleys(pkgasset.parsed_asset.assets.values(), node_state)

	if len(skelleys_with_no_parent) == 1:
		scene_contents = skelleys_with_no_parent[0].godot_skeleton
		scene_contents.name = "RootSkeleton"
		node_state = node_state.state_with_owner(scene_contents)
	elif len(skelleys_with_no_parent) > 1:
		assert(not is_prefab)

	arr.sort_custom(customComparison)
	for asset in arr:
		var skel: Reference = node_state.uniq_key_to_skelley.get(asset.transform.uniq_key, null)
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

	var packed_scene: PackedScene = PackedScene.new()
	print("Finished packing " + pkgasset.pathname + " with " + str(scene_contents.get_child_count()) + " nodes.")
	packed_scene.pack(scene_contents)
	#print(packed_scene)
	#var pi = packed_scene.instance(PackedScene.GEN_EDIT_STATE_INSTANCE)
	#print(pi.get_child_count())
	return packed_scene
