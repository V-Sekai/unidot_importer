@tool
extends EditorSceneImporter

# Steps to achieve UNITY within the UNITED states
# 
# 1. Export unitypackage with the data we want.
# 2. For every FBX, we wish to export a GLB using UnityGLTF!! ALTERNATIVELY, a pipeline can be created using fbx2gltf. I'm open to trying this as well.
# 2b. We still care about the .fbx.meta and its mapping ModelImporter: fileIDToRecycleName: 
# 3. 
# 


const yaml_parser_class: GDScript = preload("./unity_object_parser.gd")
const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
const asset_database_class: GDScript = preload("./asset_database.gd")

func _get_extensions():
	return ["unity", "prefab"]


func _get_import_flags():
	return EditorSceneImporter.IMPORT_SCENE


func _import_animation(path: String, flags: int, bake_fps: int) -> Animation:
	return Animation.new()


func customComparison(a, b):
	if typeof(a) != typeof(b):
		return typeof(a) < typeof(b)
	elif a.transform != null && b.transform != null:
		return a.transform.rootOrder < b.transform.rootOrder
	else:
		return b.fileID < a.fileID


func _import_scene(path: String, flags: int, bake_fps: int):
	var rel_path = path.replace("res://", "")
	print("Parsing scene at " + path)
	var asset_database = asset_database_class.get_singleton()

	var metaobj: Resource = asset_database.get_meta_at_path(rel_path)
	var f: File
	if metaobj == null:
		f = File.new()
		if f.open(path + ".meta", File.READ) != OK:
			metaobj = asset_database.create_dummy_meta(rel_path)
		else:
			metaobj = asset_database.parse_meta(f, rel_path)
			f.close()
		asset_database.insert_meta(metaobj)

	f = File.new()
	var e = f.open(path, File.READ)
	if e != OK:
		return e
	var parsed: Reference = metaobj.parse_asset(f)
	f.close()
	if e != OK:
		return e
	
	var arr: Array = [].duplicate()

	for asset in parsed.assets.values():
		if asset.type == "GameObject" and asset.toplevel:
			arr.push_back(asset)

	var scene_contents: Node3D = Node3D.new()
	scene_contents.name = "RootNode"
	#scene_contents.owner = scene_contents 

	var scene_contents2: Node3D = Node3D.new()
	scene_contents2.name = "SubNode"
	scene_contents.add_child(scene_contents2)
	scene_contents2.owner = scene_contents

	var node_state: Object = object_adapter_class.create_node_state(asset_database, metaobj, scene_contents)

	arr.sort_custom(customComparison)
	for asset in arr:
		# print(str(asset) + " position " + str(asset.transform.godot_transform))
		asset.create_godot_node(node_state, scene_contents)
		#var new_node: Node3D = Node3D.new()
		#scene_contents.add_child(new_node)
		
	# var f: File = File.new()
	# if f.open(path, File.READ) != OK:
	# 	return FAILED

	# var magic = f.get_line()
	# print("Hello, World! " + magic)
	# if not magic.begins_with("%YAML"):
	# 	return ERR_FILE_UNRECOGNIZED

	# var yaml_parser = yaml_parser_class.new()
	# var i = 0
	# var guid = ""
	# while true:
	# 	i += 1
	# 	var lin = f.get_line()
	# 	var output_obj = yaml_parser.parse_line(lin, guid, false)
	# 	if output_obj != null:
	# 		pass#print(output_obj.to_string())
	# 	if f.get_error() == ERR_FILE_EOF:
	# 		break

	#var yaml_version = magic.substr(5)
	#print("YAML version " + yaml_version.substr(5))
	#if yaml_version != " 1.1":
	#	return ERR_PARSE_ERROR

	# f.close()

	#if ResourceLoader.exists(path + ".res") == false:
	#	ResourceSaver.save(path + ".res", gstate)
	# Remove references

	var packed_scene: PackedScene = PackedScene.new()
	print(str(scene_contents.get_child_count()))
	packed_scene.pack(scene_contents)
	print(packed_scene)
	var pi = packed_scene.instance(PackedScene.GEN_EDIT_STATE_INSTANCE)
	print(pi.get_child_count())
	return pi # packed_scene


func import_animation_from_other_importer(path: String, flags: int, bake_fps: int):
	return self._import_animation(path, flags, bake_fps)


func import_scene_from_other_importer(path: String, flags: int, bake_fps: int):
	return self._import_scene(path, flags, bake_fps)
