@tool
extends EditorScenePostImport

const asset_database_class: GDScript = preload("./asset_database.gd")
const unity_object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
# Use this as an example script for writing your own custom post-import scripts. The function requires you pass a table
# of valid animation names and parameters

var object_adapter = unity_object_adapter_class.new()

class ParseState:
	var scene: Node
	var metaobj: Resource
	var source_file_path: String
	var external_objects_by_id: Dictionary = {}.duplicate() # fileId -> UnityRef Array
	
	var saved_materials_by_name: Dictionary = {}.duplicate()
	var saved_meshes_by_name: Dictionary = {}.duplicate()
	var saved_animations_by_name: Dictionary = {}.duplicate()
	var materials_by_name: Dictionary = {}.duplicate()
	var meshes_by_name: Dictionary = {}.duplicate()
	var animations_by_name: Dictionary = {}.duplicate()
	var nodes_by_name: Dictionary = {}.duplicate()
	var skeleton_bones_by_name: Dictionary = {}.duplicate()
	var objtype_to_name_to_id: Dictionary = {}.duplicate()
	
	var fileid_to_nodepath: Dictionary = {}.duplicate()
	var fileid_to_skeleton_bone: Dictionary = {}.duplicate()
	
	# Do we actually need this? Ordering?
	#var materials = [].duplicate()
	#var meshes = [].duplicate()
	#var animations = [].duplicate()
	#var nodes = [].duplicate()

	func get_resource_path(sanitized_name: String, extension: String) -> String:
		# return source_file_path.get_basename() + "." + str(fileId) + extension
		return source_file_path.get_basename() + "." + sanitized_name + extension

	func sanitize_bone_name(bone_name: String) -> String:
		# Note: Spaces do not add _, but captial characters do??? Let's just clean everything for now.
		return bone_name.replace("/", "").replace(".", "").replace(" ", "_").replace("_", "").to_lower()

	func iterate(node):
		if node != null:
			# TODO: Nodes which should be part of a skeleton need to be remapped?
			var path: NodePath = scene.get_path_to(node)
			var node_name: String = str(node.name)
			var fileId: int
			################# FIXME THIS WILL BE CHANGED SOON IN GODOT
			node_name = sanitize_bone_name(node_name)
			if node is AnimationPlayer:
				var parent_node: Node3D = node.get_parent()
				if scene.get_path_to(parent_node) == NodePath("."):
					parent_node = parent_node.get_child(0)
				node_name = sanitize_bone_name(str(parent_node.name))
				fileId = objtype_to_name_to_id.get("Animator", {}).get(node_name, 0)
				if fileId == 0:
					printerr("Missing fileId for Animator " + str(node_name))
				else:
					fileid_to_nodepath[fileId] = path
			elif node is Skeleton3D:
				for i in range(node.get_bone_count()):
					var og_bone_name: String = node.get_bone_name(i)
					################# FIXME THIS WILL BE CHANGED SOON IN GODOT
					var bone_name: String = sanitize_bone_name(og_bone_name)
					if bone_name not in nodes_by_name and bone_name not in skeleton_bones_by_name:
						print("Found bone " + str(bone_name) + " : " + str(scene.get_path_to(node)))
						fileId = objtype_to_name_to_id.get("Transform", {}).get(bone_name, 0)
						skeleton_bones_by_name[node_name] = node
						if fileId == 0:
							printerr("Missing fileId for bone Transform " + str(bone_name))
						else:
							fileid_to_nodepath[fileId] = path
							fileid_to_skeleton_bone[fileId] = og_bone_name
						fileId = objtype_to_name_to_id.get("GameObject", {}).get(bone_name, 0)
						if fileId == 0:
							printerr("Missing fileId for bone GameObject " + str(bone_name))
						else:
							fileid_to_nodepath[fileId] = path
							fileid_to_skeleton_bone[fileId] = og_bone_name
			elif node_name not in nodes_by_name and path != NodePath("."):
				if node_name in skeleton_bones_by_name:
					skeleton_bones_by_name.erase(node_name)
				print("Found node " + str(node_name) + " : " + str(scene.get_path_to(node)))
				nodes_by_name[node_name] = node
				fileId = objtype_to_name_to_id.get("Transform", {}).get(node_name, 0)
				if fileId == 0:
					printerr("Missing fileId for Transform " + str(node_name))
				else:
					fileid_to_nodepath[fileId] = path
					if fileId in fileid_to_skeleton_bone:
						fileid_to_skeleton_bone.erase(fileId)
				fileId = objtype_to_name_to_id.get("GameObject", {}).get(node_name, 0)
				if fileId == 0:
					printerr("Missing fileId for GameObject " + str(node_name))
				else:
					fileid_to_nodepath[fileId] = path
					if fileId in fileid_to_skeleton_bone:
						fileid_to_skeleton_bone.erase(fileId)
			if node is MeshInstance3D:
				fileId = objtype_to_name_to_id.get("SkinnedMeshRenderer", {}).get(node_name, 0)
				var fileId_mr: int = objtype_to_name_to_id.get("MeshRenderer", {}).get(node_name, 0)
				var fileId_mf: int = objtype_to_name_to_id.get("MeshFilter", {}).get(node_name, 0)
				if fileId == 0 and (fileId_mf == 0 or fileId_mr == 0):
					printerr("Missing fileId for MeshRenderer " + str(node_name))
				elif fileId == 0:
					fileId = fileId_mr
					fileid_to_nodepath[fileId_mr] = path
					fileid_to_nodepath[fileId_mf] = path
					if node.skeleton != NodePath():
						printerr("A Skeleton exists for MeshRenderer " + str(node_name))
				else:
					fileid_to_nodepath[fileId] = path
					if node.skeleton == NodePath():
						printerr("No Skeleton exists for SkinnedMeshRenderer " + str(node_name))
				var mesh: Mesh = node.mesh
				# FIXME: mesh_name is broken on master branch, maybe 3.2 as well.
				var mesh_name: String = mesh.resource_name
				if  meshes_by_name.has(mesh_name):
					mesh = saved_meshes_by_name.get(mesh_name)
					if mesh != null:
						node.mesh = mesh
				else:
					meshes_by_name[mesh_name] = mesh
					for i in range(mesh.get_surface_count()):
						var mat: Material = mesh.surface_get_material(i)
						var mat_name: String = mat.resource_name
						if materials_by_name.has(mat_name):
							mat = saved_materials_by_name.get(mat_name)
							if mat != null:
								mesh.surface_set_material(i, mat)
							continue
						materials_by_name[mat_name] = mat
						fileId = objtype_to_name_to_id.get("Material", {}).get(mat_name, 0)
						if fileId == 0:
							printerr("Missing fileId for Material " + str(mat_name))
						else:
							if external_objects_by_id.has(fileId):
								mat = metaobj.get_godot_resource(external_objects_by_id.get(fileId))
							else:
								var respath: String = get_resource_path(mat_name, ".tres")
								ResourceSaver.save(respath, mat)
								mat = load(respath)
							if mat != null:
								mesh.surface_set_material(i, mat)
								saved_materials_by_name[mat_name] = mat
								metaobj.insert_resource(fileId, mat)
						print("MeshInstance " + str(scene.get_path_to(node)) + " / Mesh " + str(mesh.resource_name if mesh != null else "NULL")+ " Material " + str(i) + " name " + str(mat.resource_name if mat != null else "NULL"))
					fileId = objtype_to_name_to_id.get("Mesh", {}).get(mesh_name, 0)
					if fileId == 0:
						printerr("Missing fileId for Mesh " + str(mesh_name))
					else:
						if external_objects_by_id.has(fileId):
							mesh = metaobj.get_godot_resource(external_objects_by_id.get(fileId))
						else:
							var respath: String = get_resource_path(mesh_name, ".res")
							ResourceSaver.save(respath, mesh)
							mesh = load(respath)
						if mesh != null:
							node.mesh = mesh
							saved_meshes_by_name[mesh_name] = mesh
							metaobj.insert_resource(fileId, mesh)
			elif node is AnimationPlayer:
				var i = 0
				for anim_name in node.get_animation_list():
					var anim: Animation = node.get_animation(anim_name)
					if animations_by_name.has(anim_name):
						anim = saved_animations_by_name.get(anim_name)
						if anim != null:
							node.remove_animation(anim_name)
							node.add_animation(anim_name, anim)
						continue
					animations_by_name[anim_name] = anim
					fileId = objtype_to_name_to_id.get("AnimationClip", {}).get(anim_name, 0)
					if fileId == 0:
						printerr("Missing fileId for Animation " + str(anim_name))
					else:
						if external_objects_by_id.has(fileId):
							anim = metaobj.get_godot_resource(external_objects_by_id.get(fileId))
						else:
							var respath: String = get_resource_path(anim_name, ".tres")
							ResourceSaver.save(respath, anim)
							anim = load(respath)
						if anim != null:
							node.remove_animation(anim_name)
							node.add_animation(anim_name, anim)
							saved_animations_by_name[anim_name] = anim
							metaobj.insert_resource(fileId, anim)
					print("AnimationPlayer " + str(scene.get_path_to(node)) + " / Anim " + str(i) + " anim_name: " + anim_name + " resource_name: " + str(anim.resource_name))
					i += 1
			for child in node.get_children():
				iterate(child)

func post_import(p_scene: Node) -> Object:
	var source_file_path: String = get_source_file()
	var rel_path = source_file_path.replace("res://", "")
	print("Parsing meta at " + source_file_path)
	var asset_database = asset_database_class.get_singleton()

	var metaobj: Resource = asset_database.get_meta_at_path(rel_path)
	var f: File
	if metaobj == null:
		f = File.new()
		if f.open(source_file_path + ".meta", File.READ) != OK:
			metaobj = asset_database.create_dummy_meta(rel_path)
		else:
			metaobj = asset_database.parse_meta(f, rel_path)
			f.close()
		asset_database.insert_meta(metaobj)

	# For now, we assume all data is available in the asset database resource.
	# var metafile = source_file_path + ".meta"
	var ps: ParseState = ParseState.new()
	ps.scene = p_scene
	ps.source_file_path = source_file_path
	ps.metaobj = metaobj
	var external_objects: Dictionary = metaobj.importer.get_external_objects()

	var recycles: Dictionary = metaobj.importer.fileIDToRecycleName
	for fileIdStr in recycles:
		var og_obj_name: String = recycles[fileIdStr]
		var obj_name: String = og_obj_name
		if obj_name.begins_with("//"):
			# Not sure why, but Unity uses //RootNode
			# Maybe it indicates that the node will be hidden???
			obj_name = obj_name.substr(2)
		var fileId: int = int(str(fileIdStr).to_int())
		var type: String = str(object_adapter.to_classname(fileId / 100000))
		if (type == "Transform" or type == "GameObject" or type == "MeshRenderer"
				or type == "MeshFilter" or type == "SkinnedMeshRenderer" or type == "Animator"):
			################# FIXME THIS WILL BE CHANGED SOON IN GODOT
			obj_name = ps.sanitize_bone_name(obj_name)
		if not ps.objtype_to_name_to_id.has(type):
			ps.objtype_to_name_to_id[type] = {}.duplicate()
		#print("Adding recycle id " + str(fileId) + " and type " + str(type) + " and utype " + str(fileId / 100000) + ": " + str(obj_name))
		ps.objtype_to_name_to_id[type][obj_name] = fileId
		if external_objects.get(type, {}).has(og_obj_name):
			ps.external_objects_by_id[fileId] = external_objects.get(type).get(og_obj_name)

	ps.iterate(p_scene)
	
	metaobj.fileid_to_nodepath = ps.fileid_to_nodepath
	metaobj.fileid_to_skeleton_bone = ps.fileid_to_skeleton_bone

	asset_database.save()

	return p_scene
