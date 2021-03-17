@tool
extends Resource

const static_storage: GDScript = preload("./static_storage.gd")
const asset_database_class: GDScript = preload("./asset_database.gd")
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
		scene_contents.name = "RootNode"

	var node_state: Object = object_adapter_class.create_node_state(pkgasset.parsed_meta.database, pkgasset.parsed_meta, scene_contents)

	arr.sort_custom(customComparison)
	for asset in arr:
		# print(str(asset) + " position " + str(asset.transform.godot_transform))
		var new_root: Node3D = asset.create_godot_node(node_state, scene_contents)
		if is_prefab:
			scene_contents = new_root

	var packed_scene: PackedScene = PackedScene.new()
	print(str(scene_contents.get_child_count()))
	packed_scene.pack(scene_contents)
	print(packed_scene)
	var pi = packed_scene.instance(PackedScene.GEN_EDIT_STATE_INSTANCE)
	print(pi.get_child_count())
	return packed_scene
