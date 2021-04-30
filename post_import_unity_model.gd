@tool
extends EditorScenePostImport

const asset_database_class: GDScript = preload("./asset_database.gd")
const unity_object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
# Use this as an example script for writing your own custom post-import scripts. The function requires you pass a table
# of valid animation names and parameters

var object_adapter = unity_object_adapter_class.new()

class ParseState:
	var scene: Node
	var toplevel_node: Node
	var metaobj: Resource
	var source_file_path: String
	var external_objects_by_id: Dictionary = {}.duplicate() # fileId -> UnityRef Array
	
	var saved_materials_by_name: Dictionary = {}.duplicate()
	var saved_meshes_by_name: Dictionary = {}.duplicate()
	var saved_skins_by_name: Dictionary = {}.duplicate()
	var saved_animations_by_name: Dictionary = {}.duplicate()
	var materials_by_name: Dictionary = {}.duplicate()
	var meshes_by_name: Dictionary = {}.duplicate()
	var animations_by_name: Dictionary = {}.duplicate()
	var nodes_by_name: Dictionary = {}.duplicate()
	var skeleton_bones_by_name: Dictionary = {}.duplicate()
	var objtype_to_name_to_id: Dictionary = {}.duplicate()
	
	var fileid_to_nodepath: Dictionary = {}.duplicate()
	var fileid_to_skeleton_bone: Dictionary = {}.duplicate()
	var fileid_to_utype: Dictionary = {}.duplicate()
	
	var scale_correction_factor: float = 1.0
	var is_obj: bool = false
	var use_scene_root: bool = true
	var mesh_is_toplevel: bool = false
	var extractLegacyMaterials: bool = false

	# Do we actually need this? Ordering?
	#var materials = [].duplicate()
	#var meshes = [].duplicate()
	#var animations = [].duplicate()
	#var nodes = [].duplicate()

	func get_resource_path(sanitized_name: String, extension: String) -> String:
		# return source_file_path.get_basename() + "." + str(fileId) + extension
		return source_file_path.get_basename() + "." + sanitized_name + extension

	func get_materials_path(material_name: String) -> String:
		# return source_file_path.get_basename() + "." + str(fileId) + extension
		return source_file_path.get_base_dir() + "/Materials/" + str(material_name) + ".mat.tres"

	func sanitize_bone_name(bone_name: String) -> String:
		# Note: Spaces do not add _, but captial characters do??? Let's just clean everything for now.
		print ("todo postimp bone replace " + str(bone_name))
		var xret = bone_name.replace("/", "").replace(":", "").replace(".", "").replace(" ", "_").replace("_", "").to_lower()
		print ("todone postimp bone replace " + str(xret))
		return xret

	func fold_transforms_into_mesh(node: Node3D, p_transform: Transform = Transform.IDENTITY) -> Node3D:
		var transform: Transform = p_transform * node.transform
		if node is VisualInstance3D:
			node.transform = transform
			return node
		node.transform = Transform.IDENTITY
		var result: Node3D = null
		for child in node.get_children():
			var ret: Node3D = fold_transforms_into_mesh(child, transform)
			if ret != null:
				result = ret
		return result

	func iterate(node: Node):
		var sm = StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if node != null:
			if scale_correction_factor != 1.0:
				if node is Node3D:
					node.translation *= scale_correction_factor
				if node is Skeleton3D:
					for i in range(node.get_bone_count()):
						var rest: Transform = node.get_bone_rest(i)
						node.set_bone_rest(i, Transform(rest.basis, scale_correction_factor * rest.origin))
			var path: NodePath = scene.get_path_to(node)
			# TODO: Nodes which should be part of a skeleton need to be remapped?
			var node_name: String = str(node.name)
			if node is MeshInstance3D:
				if is_obj and node.mesh != null:
					node_name = "default"
					node.name = "default" # Does this make sense?? For compatibility?
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
					push_error("Missing fileId for Animator " + str(node_name))
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
							push_error("Missing fileId for bone Transform " + str(bone_name))
						else:
							fileid_to_nodepath[fileId] = path
							fileid_to_skeleton_bone[fileId] = og_bone_name
						fileId = objtype_to_name_to_id.get("GameObject", {}).get(bone_name, 0)
						if fileId == 0:
							push_error("Missing fileId for bone GameObject " + str(bone_name))
						else:
							fileid_to_nodepath[fileId] = path
							fileid_to_skeleton_bone[fileId] = og_bone_name
			elif path == NodePath("RootNode"):
				pass
			elif node_name not in nodes_by_name and (node != toplevel_node or use_scene_root):
				if node == toplevel_node:
					node_name = ""
				if node is BoneAttachment3D:
					node_name = sanitize_bone_name(node.bone_name)
				if node_name in skeleton_bones_by_name:
					skeleton_bones_by_name.erase(node_name)
				print("Found node " + str(node_name) + " : " + str(scene.get_path_to(node)))
				nodes_by_name[node_name] = node
				fileId = objtype_to_name_to_id.get("Transform", {}).get(node_name, 0)
				if node == toplevel_node:
					pass # Transform nodes always point to the toplevel node.
				elif fileId == 0:
					push_error("Missing fileId for Transform " + str(node_name))
				else:
					fileid_to_nodepath[fileId] = path
					if fileId in fileid_to_skeleton_bone:
						fileid_to_skeleton_bone.erase(fileId)
				fileId = objtype_to_name_to_id.get("GameObject", {}).get(node_name, 0)
				if node == toplevel_node:
					pass # GameObject nodes always point to the toplevel node.
				elif fileId == 0:
					push_error("Missing fileId for GameObject " + str(node_name))
				else:
					fileid_to_nodepath[fileId] = path
					if fileId in fileid_to_skeleton_bone:
						fileid_to_skeleton_bone.erase(fileId)
			if node is MeshInstance3D and node.mesh != null:
				fileId = objtype_to_name_to_id.get("SkinnedMeshRenderer", {}).get(node_name, 0)
				var fileId_mr: int = objtype_to_name_to_id.get("MeshRenderer", {}).get(node_name, 0)
				var fileId_mf: int = objtype_to_name_to_id.get("MeshFilter", {}).get(node_name, 0)
				if fileId == 0 and (fileId_mf == 0 or fileId_mr == 0):
					push_error("Missing fileId for MeshRenderer " + str(node_name))
				elif fileId == 0:
					fileId = fileId_mr
					fileid_to_nodepath[fileId_mr] = path
					fileid_to_nodepath[fileId_mf] = path
					if node.skeleton != NodePath():
						push_error("A Skeleton exists for MeshRenderer " + str(node_name))
				else:
					fileid_to_nodepath[fileId] = path
					if node.skeleton == NodePath():
						push_error("No Skeleton exists for SkinnedMeshRenderer " + str(node_name))
				var mesh: Mesh = node.mesh
				# FIXME: mesh_name is broken on master branch, maybe 3.2 as well.
				var mesh_name: String = str(mesh.resource_name)
				if mesh_name.begins_with("Root Scene_"):
					mesh_name = mesh_name.substr(11)
				if is_obj:
					mesh_name = "default"
				if  meshes_by_name.has(mesh_name):
					mesh = saved_meshes_by_name.get(mesh_name)
					if mesh != null:
						node.mesh = mesh
					if node.skin != null:
						node.skin = saved_skins_by_name.get(mesh_name)
				else:
					meshes_by_name[mesh_name] = mesh
					for i in range(mesh.get_surface_count()):
						var mat: Material = mesh.surface_get_material(i)
						if mat == null:
							continue
						var mat_name: String = mat.resource_name
						if mat_name == "DefaultMaterial":
							mat_name = "No Name"
						if is_obj:
							mat_name = "default"
						if materials_by_name.has(mat_name):
							mat = saved_materials_by_name.get(mat_name)
							if mat != null:
								mesh.surface_set_material(i, mat)
							continue
						materials_by_name[mat_name] = mat
						fileId = objtype_to_name_to_id.get("Material", {}).get(mat_name, 0)
						if not extractLegacyMaterials and fileId == 0:
							push_error("Missing fileId for Material " + str(mat_name))
						else:
							if extractLegacyMaterials:
								mat = load(get_materials_path(mat_name))
							elif external_objects_by_id.has(fileId):
								mat = metaobj.get_godot_resource(external_objects_by_id.get(fileId))
							else:
								var respath: String = get_resource_path(mat_name, ".res")
								ResourceSaver.save(respath, mat)
								mat = load(respath)
							if mat != null:
								mesh.surface_set_material(i, mat)
								saved_materials_by_name[mat_name] = mat
								metaobj.insert_resource(fileId, mat)
						print("MeshInstance " + str(scene.get_path_to(node)) + " / Mesh " + str(mesh.resource_name if mesh != null else "NULL")+ " Material " + str(i) + " name " + str(mat.resource_name if mat != null else "NULL"))
					fileId = objtype_to_name_to_id.get("Mesh", {}).get(mesh_name, 0)
					if fileId == 0:
						push_error("Missing fileId for Mesh " + str(mesh_name))
					else:
						var skin: Skin = node.skin
						if external_objects_by_id.has(fileId):
							mesh = metaobj.get_godot_resource(external_objects_by_id.get(fileId))
							if skin != null:
								skin = metaobj.get_godot_resource(external_objects_by_id.get(-fileId))
						else:
							if mesh != null:
								adjust_mesh_scale(mesh)
								var respath: String = get_resource_path(mesh_name, ".res")
								ResourceSaver.save(respath, mesh)
								mesh = load(respath)
							if skin != null:
								skin = skin.duplicate()
								adjust_skin_scale(skin)
								var respath: String = get_resource_path(mesh_name, ".skin.tres")
								ResourceSaver.save(respath, skin)
								skin = load(respath)
						if mesh != null:
							node.mesh = mesh
							saved_meshes_by_name[mesh_name] = mesh
							metaobj.insert_resource(fileId, mesh)
							if skin != null:
								node.skin = skin
								saved_skins_by_name[mesh_name] = skin
								metaobj.insert_resource(-fileId, skin)
				is_obj = false
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
						push_error("Missing fileId for Animation " + str(anim_name))
					else:
						if external_objects_by_id.has(fileId):
							anim = metaobj.get_godot_resource(external_objects_by_id.get(fileId))
						else:
							if anim != null:
								adjust_animation(anim)
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

	
	func adjust_skin_scale(skin: Skin):
		if scale_correction_factor == 1.0:
			return
		# MESH and SKIN data divide, to compensate for object position multiplying.
		for i in range(skin.get_bind_count()):
			var transform = skin.get_bind_pose(i)
			skin.set_bind_pose(i, Transform(transform.basis, transform.origin * scale_correction_factor))

	func adjust_mesh_scale(mesh: ArrayMesh, is_shadow: bool = false):
		if scale_correction_factor == 1.0:
			return
		# MESH and SKIN data divide, to compensate for object position multiplying.
		var surf_count: int = mesh.get_surface_count()
		var surf_data_by_mesh = [].duplicate()
		for surf_idx in range(surf_count):
			var prim: int = mesh.surface_get_primitive_type(surf_idx)
			var fmt_compress_flags: int = mesh.surface_get_format(surf_idx)
			var arr: Array = mesh.surface_get_arrays(surf_idx) 
			var name: String = mesh.surface_get_name(surf_idx)
			var bsarr: Array = mesh.surface_get_blend_shape_arrays(surf_idx)
			var lods: Dictionary = {} # mesh.surface_get_lods(surf_idx) # get_lods(mesh, surf_idx)
			var mat: Material = mesh.surface_get_material(surf_idx)
			print("About to multiply mesh vertices by " + str(scale_correction_factor) + ": " + str(arr[ArrayMesh.ARRAY_VERTEX][0]))
			for i in range(len(arr[ArrayMesh.ARRAY_VERTEX])):
				arr[ArrayMesh.ARRAY_VERTEX][i] = arr[ArrayMesh.ARRAY_VERTEX][i] * scale_correction_factor
			print("Done multiplying mesh vertices by " + str(scale_correction_factor) + ": " + str(arr[ArrayMesh.ARRAY_VERTEX][0]))
			for bsidx in range(len(bsarr)):
				for i in range(len(bsarr[bsidx][ArrayMesh.ARRAY_VERTEX])):
					bsarr[bsidx][ArrayMesh.ARRAY_VERTEX][i] = bsarr[bsidx][ArrayMesh.ARRAY_VERTEX][i] * scale_correction_factor
				bsarr[bsidx].resize(len(arr))
				print("Len arr " + str(len(arr)) + " bsidx " + str(bsidx) + " len bsarr[bsidx] " + str(len(bsarr[bsidx])))
				for i in range(len(arr)):
					if i >= ArrayMesh.ARRAY_INDEX or typeof(arr[i]) == TYPE_NIL:
						bsarr[bsidx][i] = null
					elif typeof(bsarr[bsidx][i]) == TYPE_NIL or len(bsarr[bsidx][i]) == 0:
						bsarr[bsidx][i] = arr[i].duplicate()
						bsarr[bsidx][i].resize(0)
						bsarr[bsidx][i].resize(len(arr[i]))

			surf_data_by_mesh.push_back({
				"prim": prim,
				"arr": arr,
				"bsarr": bsarr,
				"lods": lods,
				"fmt_compress_flags": fmt_compress_flags,
				"name": name,
				"mat": mat
			})
		mesh.clear_surfaces()
		for surf_idx in range(surf_count):
			var prim: int = surf_data_by_mesh[surf_idx].get("prim")
			var arr: Array = surf_data_by_mesh[surf_idx].get("arr")
			var bsarr: Array = surf_data_by_mesh[surf_idx].get("bsarr")
			var lods: Dictionary = surf_data_by_mesh[surf_idx].get("lods")
			var fmt_compress_flags: int = surf_data_by_mesh[surf_idx].get("fmt_compress_flags")
			var name: String = surf_data_by_mesh[surf_idx].get("name")
			var mat: Material = surf_data_by_mesh[surf_idx].get("mat")
			print("Adding mesh vertices by " + str(scale_correction_factor) + ": " + str(arr[ArrayMesh.ARRAY_VERTEX][0]))
			mesh.add_surface_from_arrays(prim, arr, bsarr, lods, fmt_compress_flags)
			mesh.surface_set_name(surf_idx, name)
			mesh.surface_set_material(surf_idx, mat)
			print("Get mesh vertices by " + str(scale_correction_factor) + ": " + str(mesh.surface_get_arrays(surf_idx)[ArrayMesh.ARRAY_VERTEX][0]))
		if not is_shadow and mesh.shadow_mesh != mesh and mesh.shadow_mesh != null:
			adjust_mesh_scale(mesh.shadow_mesh, true)

	func adjust_animation_scale(anim: Animation):
		if scale_correction_factor == 1.0:
			return
		# ANIMATION and NODES multiply by scale
		for trackidx in range(anim.get_track_count()):
			var path: String = anim.get("tracks/" + str(trackidx) + "/path")
			if path.ends_with(":x") or path.ends_with(":y") or path.ends_with(":z"):
				path = path.substr(0, len(path) - 2) # To make matching easier.
			match anim.get("tracks/" + str(trackidx) + "/type"):
				"transform":
					var xform_keys: PackedFloat32Array = anim.get("tracks/" + str(trackidx) + "/keys")
					for i in range(0, len(xform_keys), 12):
						xform_keys[i + 2] *= scale_correction_factor
						xform_keys[i + 3] *= scale_correction_factor
						xform_keys[i + 4] *= scale_correction_factor
					anim.set("tracks/" + str(trackidx) + "/keys", xform_keys)
				"value":
					if path.ends_with(":translation") or path.ends_with(":transform"):
						var track_dict: Dictionary = anim.get("tracks/" + str(trackidx) + "/keys")
						var track_values: Array = track_dict.get("values")
						if path.ends_with(":transform"):
							for i in range(len(track_values)):
								track_values[i] = Transform(track_values[i].basis, track_values[i].origin * scale_correction_factor)
						else:
							for i in range(len(track_values)):
								track_values[i] *= scale_correction_factor
						track_dict["values"] = track_values
						anim.set("tracks/" + str(trackidx) + "/keys", track_dict)
				"bezier":
					if path.ends_with(":translation") or path.ends_with(":transform"):
						var track_dict: Dictionary = anim.get("tracks/" + str(trackidx) + "/keys")
						var track_values: Variant = track_dict.get("points") # Some sort of packed array?
						# VALUE, inX, inY, outX, outY
						if path.ends_with(":transform"):
							for i in range(len(track_values)):
								if ((i % 5) % 2) != 1:
									track_values[i] = Transform(track_values[i].basis, track_values[i].origin * scale_correction_factor)
						else:
							for i in range(len(track_values)):
								if ((i % 5) % 2) != 1:
									track_values[i] *= scale_correction_factor
						track_dict["points"] = track_values
						anim.set("tracks/" + str(trackidx) + "/keys", track_dict)

	func adjust_animation(anim: Animation):
		adjust_animation_scale(anim)
		# Root motion?
		# Splitting up animation?

func post_import(p_scene: Node) -> Object:
	var source_file_path: String = get_source_file()
	print ("todo post import replace " + str(source_file_path))
	var rel_path = source_file_path.replace("res://", "")
	print("Parsing meta at " + source_file_path)
	var asset_database = asset_database_class.get_singleton()
	var is_obj: bool = source_file_path.ends_with(".obj")
	var is_dae: bool = source_file_path.ends_with(".dae")

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
	ps.scale_correction_factor = metaobj.internal_data.get("scale_correction_factor", 1.0)
	ps.extractLegacyMaterials = metaobj.importer.keys.get("materials").get("materialLocation", 0) == 0
	ps.is_obj = is_obj
	print("Path " + str(source_file_path) + " correcting scale by " + str(ps.scale_correction_factor))
	#### Setting root_scale through the .import ConfigFile doesn't seem to be working foro me. ## p_scene.scale /= ps.scale_correction_factor
	var external_objects: Dictionary = metaobj.importer.get_external_objects()

	var recycles: Dictionary = metaobj.importer.fileIDToRecycleName
	for fileIdStr in recycles:
		var og_obj_name: String = recycles[fileIdStr]
		var obj_name: String = og_obj_name
		if obj_name.begins_with("//"):
			# Not sure why, but Unity uses //RootNode
			# Maybe it indicates that the node will be hidden???
			obj_name = ""
			ps.use_scene_root = true
			#if is_obj or is_dae:
			#else:
			#	obj_name = obj_name.substr(2)
		var fileId: int = int(str(fileIdStr).to_int())
		var type: String = str(object_adapter.to_classname(fileId / 100000))
		if (type == "Transform" or type == "GameObject" or type == "Animator"):
			################# FIXME THIS WILL BE CHANGED SOON IN GODOT
			obj_name = ps.sanitize_bone_name(obj_name)
		elif (type == "MeshRenderer" or type == "MeshFilter" or type == "SkinnedMeshRenderer"):
			if obj_name.is_empty():
				ps.mesh_is_toplevel = true
			################# FIXME THIS WILL BE CHANGED SOON IN GODOT
			obj_name = ps.sanitize_bone_name(obj_name)
		if not ps.objtype_to_name_to_id.has(type):
			ps.objtype_to_name_to_id[type] = {}.duplicate()
		#print("Adding recycle id " + str(fileId) + " and type " + str(type) + " and utype " + str(fileId / 100000) + ": " + str(obj_name))
		ps.objtype_to_name_to_id[type][obj_name] = fileId
		if external_objects.get(type, {}).has(og_obj_name):
			ps.external_objects_by_id[fileId] = external_objects.get(type).get(og_obj_name)

	print("Ext objs by id: "+ str(ps.external_objects_by_id))
	print("objtype name by id: "+ str(ps.objtype_to_name_to_id))
	ps.toplevel_node = p_scene
	p_scene.name = source_file_path.get_file().get_basename()
	if ps.mesh_is_toplevel:
		var new_toplevel: Node3D = ps.fold_transforms_into_mesh(ps.toplevel_node)
		if new_toplevel != null:
			ps.toplevel_node.transform = new_toplevel.transform
			new_toplevel.transform = Transform.IDENTITY
			ps.toplevel_node = new_toplevel

	# GameObject references always point to the toplevel node:
	ps.fileid_to_nodepath[ps.objtype_to_name_to_id.get("GameObject", {}).get("", 0)] = NodePath(".")
	ps.fileid_to_nodepath[ps.objtype_to_name_to_id.get("Transform", {}).get("", 0)] = NodePath(".")
	ps.iterate(ps.toplevel_node)

	for fileId in ps.fileid_to_nodepath:
		# Guaranteed for imported files
		var utype: int = fileId / 100000
		ps.fileid_to_utype[fileId] = utype

	metaobj.fileid_to_nodepath = ps.fileid_to_nodepath
	metaobj.fileid_to_skeleton_bone = ps.fileid_to_skeleton_bone
	metaobj.fileid_to_utype = ps.fileid_to_utype

	asset_database.save()

	return p_scene
