@tool
extends EditorScenePostImport

const asset_database_class: GDScript = preload("./asset_database.gd")
const unity_object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
# Use this as an example script for writing your own custom post-import scripts. The function requires you pass a table
# of valid animation names and parameters

# Todo: Secondary UV Sets.
# Note: bakery has its own data for this:
# https://forum.unity.com/threads/bakery-gpu-lightmapper-v1-8-rtpreview-released.536008/page-39#post-4077463
# animations:
#   extraUserProperties:
#   - '#BAKERY{"meshName":["Mesh1","Mesh2","Mesh3","Mesh4","Mesh5","Mesh6","Mesh7","Mesh8","Mesh9","Mesh10"],
#              "padding":[239,59,202,202,202,202,94,94,94,94],"unwrapper":[0,0,0,0,0,0,0,0,0,0]}'

var object_adapter = unity_object_adapter_class.new()
var default_material: Material = null

class ParseState:
	var object_adapter: Object
	var scene: Node
	var toplevel_node: Node
	var metaobj: Resource
	var source_file_path: String
	var goname_to_unity_name: Dictionary = {}.duplicate()
	var external_objects_by_id: Dictionary = {}.duplicate() # fileId -> UnityRef Array
	var external_objects_by_type_name: Dictionary = {}.duplicate() # type -> name -> UnityRef Array
	var material_to_texture_name: Dictionary = {}.duplicate() # for Extract Legacy Materials / By Base Texture Name
	
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
	var objtype_to_next_id: Dictionary = {}.duplicate()
	var used_ids: Dictionary = {}.duplicate()
	
	var fileid_to_nodepath: Dictionary = {}.duplicate()
	var fileid_to_skeleton_bone: Dictionary = {}.duplicate()
	var fileid_to_utype: Dictionary = {}.duplicate()
	var fileid_to_gameobject_fileid: Dictionary = {}.duplicate()

	var scale_correction_factor: float = 1.0
	var is_obj: bool = false
	var use_scene_root: bool = true
	var mesh_is_toplevel: bool = false
	var extractLegacyMaterials: bool = false
	var importMaterials: bool = true
	var materialSearch: int = 1
	var legacy_material_name_setting: int = 1
	var default_material: Material = null
	var asset_database: Resource = null

	# Do we actually need this? Ordering?
	#var materials = [].duplicate()
	#var meshes = [].duplicate()
	#var animations = [].duplicate()
	#var nodes = [].duplicate()

	func has_obj_id(type: String, name: String) -> bool:
		return objtype_to_name_to_id.get(type, {}).has(name)

	func get_obj_id(type: String, name: String) -> int:
		if objtype_to_name_to_id.get(type, {}).has(name):
			return objtype_to_name_to_id.get(type, {}).get(name, 0)
		else:
			var next_obj_id: int = objtype_to_next_id.get(type, object_adapter.to_utype(type) * 100000)
			while used_ids.has(next_obj_id):
				next_obj_id += 2
			objtype_to_next_id[type] = next_obj_id + 2
			used_ids[next_obj_id] = true
			if type != "Material":
				push_error("Generating id " + str(next_obj_id) + " for " + str(name) + " type " + str(type))
			return next_obj_id

	func get_resource_path(sanitized_name: String, extension: String) -> String:
		# return source_file_path.get_basename() + "." + str(fileId) + extension
		return source_file_path.get_basename() + "." + sanitize_filename(sanitized_name) + extension

	func get_parent_materials_paths(material_name: String) -> Array:
		# return source_file_path.get_basename() + "." + str(fileId) + extension
		var retlist: Array = []
		var basedir: String = source_file_path.get_base_dir()
		while basedir != "res://" and basedir != "/" and basedir != "" and basedir != ".":
			retlist.append(get_materials_path_base(material_name, basedir))
			basedir = basedir.get_base_dir()
		retlist.append(get_materials_path_base(material_name, "res://"))
		print("Looking in directories " + str(retlist))
		return retlist

	func get_materials_path_base(material_name: String, base_dir: String) -> String:
		# return source_file_path.get_basename() + "." + str(fileId) + extension
		return base_dir + "/Materials/" + str(material_name) + ".mat.tres"

	func get_materials_path(material_name: String) -> String:
		return get_materials_path_base(material_name, source_file_path.get_base_dir())

	func sanitize_filename(sanitized_name: String) -> String:
		return sanitize_unique_name(sanitized_name).replace("<", "").replace(">", "").replace("*", "").replace("|", "").replace("?", "")

	func sanitize_bone_name(bone_name: String) -> String:
		var xret = sanitize_unique_name(bone_name).replace("_", "")
		return xret

	func sanitize_unique_name(bone_name: String) -> String:
		var xret = bone_name.replace("/", "").replace(":", "").replace(".", "").replace("@", "").replace("\"", "")
		return xret

	func sanitize_anim_name(anim_name: String) -> String:
		return sanitize_unique_name(anim_name).replace("[", "").replace(",", "")

	func count_meshes(node: Node) -> int:
		var result: int = 0
		if node is VisualInstance3D:
			result += 1
		for child in node.get_children():
			result += count_meshes(child)
		return result

	func fold_transforms_into_mesh(node: Node3D, p_transform: Transform3D = Transform3D.IDENTITY) -> Node3D:
		var transform: Transform3D = p_transform * node.transform
		if node is VisualInstance3D:
			node.transform = transform
			return node
		node.transform = Transform3D.IDENTITY
		var result: Node3D = null
		for child in node.get_children():
			if child is Node3D:
				var ret: Node3D = fold_transforms_into_mesh(child, transform)
				if ret != null:
					result = ret
		return result

	func fold_root_transforms_into_root(node: Node3D) -> Node3D:
		var is_foldable: bool = node.get_child_count() == 1
		var wanted_child: int = 0
		if node.get_child_count() == 2 and node.get_child(0) is AnimationPlayer:
			wanted_child = 1
			is_foldable = true
		elif node.get_child_count() == 2 and node.get_child(1) is AnimationPlayer:
			is_foldable = true
		if is_foldable and node.get_child(wanted_child) is Node3D:
			var child_node: Node3D = node.get_child(wanted_child)
			if child_node.get_child_count() == 1 and child_node.get_child(0) is Node3D:
				var grandchild_node: Node3D = child_node.get_child(0)
				grandchild_node.transform = node.transform * child_node.transform * grandchild_node.transform
				node.transform = Transform3D.IDENTITY
				child_node.transform = Transform3D.IDENTITY
				return grandchild_node
			else:
				child_node.transform = node.transform * child_node.transform
				node.transform = Transform3D.IDENTITY
				return child_node
		return null

	func iterate(node: Node):
		var sm = StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if node != null:
			if scale_correction_factor != 1.0:
				if node is Node3D:
					node.position *= scale_correction_factor
				if node is Skeleton3D:
					for i in range(node.get_bone_count()):
						var rest: Transform3D = node.get_bone_rest(i)
						node.set_bone_rest(i, Transform3D(rest.basis, scale_correction_factor * rest.origin))
						node.set_bone_pose_position(i, scale_correction_factor * rest.origin)
			var path: NodePath = scene.get_path_to(node)
			# TODO: Nodes which should be part of a skeleton need to be remapped?
			var node_name: String = str(node.name)
			if node is MeshInstance3D:
				if is_obj and node.mesh != null:
					node_name = "default"
					node.name = "default" # Does this make sense?? For compatibility?
			var fileId: int
			var root_gameobject_fileId: int = get_obj_id("GameObject", "")
			var goFileId: int = root_gameobject_fileId
			################# FIXME THIS WILL BE CHANGED SOON IN GODOT
			node_name = sanitize_bone_name(node_name)
			if node is AnimationPlayer:
				var parent_node: Node3D = node.get_parent()
				if scene.get_path_to(parent_node) == NodePath("."):
					parent_node = parent_node.get_child(0)
				node_name = sanitize_bone_name(str(parent_node.name))
				fileId = get_obj_id("Animator", node_name)
				if fileId == 0:
					push_error("Missing fileId for Animator " + str(node_name))
				else:
					fileid_to_nodepath[fileId] = path
					fileid_to_gameobject_fileid[fileId] = root_gameobject_fileId
			elif node is Skeleton3D:
				for i in range(node.get_bone_count()):
					var og_bone_name: String = node.get_bone_name(i)
					################# FIXME THIS WILL BE CHANGED SOON IN GODOT
					var bone_name: String = sanitize_bone_name(og_bone_name)
					if bone_name not in nodes_by_name and bone_name not in skeleton_bones_by_name:
						# print("Found bone " + str(bone_name) + " : " + str(scene.get_path_to(node)))
						fileId = get_obj_id("Transform", bone_name)
						skeleton_bones_by_name[node_name] = node
						if fileId == 0:
							push_error("Missing fileId for bone Transform " + str(bone_name))
						else:
							fileid_to_nodepath[fileId] = path
							fileid_to_skeleton_bone[fileId] = og_bone_name
						goFileId = get_obj_id("GameObject", bone_name)
						fileid_to_gameobject_fileid[fileId] = goFileId
						fileId = goFileId
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
				# print("Found node " + str(node_name) + " : " + str(scene.get_path_to(node)))
				nodes_by_name[node_name] = node
				fileId = get_obj_id("Transform", node_name)
				if node == toplevel_node:
					pass # Transform nodes always point to the toplevel node.
				elif fileId == 0:
					push_error("Missing fileId for Transform " + str(node_name))
				else:
					# print("Add " + str(fileId) + " name " + str(node_name) + " actual name " + str(node.name) + " path " + str(path))
					fileid_to_nodepath[fileId] = path
					if fileId in fileid_to_skeleton_bone:
						fileid_to_skeleton_bone.erase(fileId)
				goFileId = get_obj_id("GameObject", node_name)
				fileid_to_gameobject_fileid[fileId] = goFileId
				fileId = goFileId
				if node == toplevel_node:
					pass # GameObject nodes always point to the toplevel node.
				elif fileId == 0:
					push_error("Missing fileId for GameObject " + str(node_name))
				else:
					# print("Add " + str(fileId) + " name " + str(node_name) + " actual name " + str(node.name) + " path " + str(path))
					fileid_to_nodepath[fileId] = path
					if fileId in fileid_to_skeleton_bone:
						fileid_to_skeleton_bone.erase(fileId)
			if node is Light3D:
				fileId = get_obj_id("Light", node_name)
				fileid_to_nodepath[fileId] = path
				fileid_to_gameobject_fileid[fileId] = goFileId
			if node is Camera3D:
				fileId = get_obj_id("Camera", node_name)
				fileid_to_nodepath[fileId] = path
				fileid_to_gameobject_fileid[fileId] = goFileId
			if node is MeshInstance3D and node.mesh != null:
				#if fileId == 0 and (fileId_mf == 0 or fileId_mr == 0):
				#	push_error("Missing fileId for MeshRenderer " + str(node_name))
				#if fileId == 0 and (fileId_mf == 0 or fileId_mr == 0):
				#	push_error("Missing fileId for MeshRenderer " + str(node_name))
				if not has_obj_id("SkinnedMeshRenderer", node_name):
					var fileId_mr: int = get_obj_id("MeshRenderer", node_name)
					var fileId_mf: int = get_obj_id("MeshFilter", node_name)
					fileId = fileId_mr
					fileid_to_nodepath[fileId_mr] = path
					fileid_to_nodepath[fileId_mf] = path
					fileid_to_gameobject_fileid[fileId_mr] = goFileId
					fileid_to_gameobject_fileid[fileId_mf] = goFileId
					if node.skeleton != NodePath():
						push_error("A Skeleton exists for MeshRenderer " + str(node_name))
				else:
					fileId = get_obj_id("SkinnedMeshRenderer", node_name)
					fileid_to_nodepath[fileId] = path
					fileid_to_gameobject_fileid[fileId] = goFileId
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
						fileId = get_obj_id("Material", sanitize_unique_name(mat_name))
						print("Materials " + str(importMaterials) + " legacy " + str(extractLegacyMaterials) + " fileId " + str(fileId))
						if not importMaterials:
							mat = default_material
						elif not extractLegacyMaterials and fileId == 0:
							push_error("Missing fileId for Material " + str(mat_name))
						else:
							var new_mat: Material = null
							if external_objects_by_id.has(fileId):
								new_mat = metaobj.get_godot_resource(external_objects_by_id.get(fileId))
							elif external_objects_by_type_name.get("Material", {}).has(sanitize_unique_name(mat_name)):
								new_mat = metaobj.get_godot_resource(external_objects_by_type_name.get("Material").get(sanitize_unique_name(mat_name)))
							if new_mat != null:
								mat = new_mat
								print("External material object " + str(fileId) + "/" + str(mat_name) + " " + str(new_mat.resource_name) + "@" + str(new_mat.resource_path))
							elif extractLegacyMaterials:
								var legacy_material_name: String = mat_name
								if legacy_material_name_setting == 0:
									legacy_material_name = material_to_texture_name.get(mat_name, mat_name)
								if legacy_material_name_setting == 2:
									legacy_material_name = source_file_path.get_file().get_basename() + "-" + mat_name

								print("Extract legacy material " + mat_name + ": " + get_materials_path(legacy_material_name))
								var d = Directory.new()
								d.open("res://")
								mat = null
								if materialSearch == 0:
									# only current dir
									legacy_material_name = get_materials_path(legacy_material_name)
									mat = load(legacy_material_name)
								elif materialSearch >= 1:
									# same dir and parents
									var mat_paths: Array = get_parent_materials_paths(legacy_material_name)
									for mp in mat_paths:
										if d.file_exists(mp):
											legacy_material_name = mp
											mat = load(mp)
											if mat != null:
												break
									if mat == null and materialSearch >= 2:
										# and material in the whole project with this name!!
										for pathname in asset_database.path_to_meta:
											if pathname.get_file() == legacy_material_name + ".material" or pathname.get_file() == mat_name + ".mat.tres" or pathname.get_file() == mat_name + ".mat.res":
												legacy_material_name = pathname
												mat = load(pathname)
												break
								if mat == null:
									print("Material " + str(legacy_material_name) + " was not found. using default")
									mat = default_material
							else:
								var respath: String = get_resource_path(mat_name, ".material")
								print("Before save " + str(mat_name) + " " + str(mat.resource_name) + "@" + str(respath) + " from " + str(mat.resource_path))
								if mat.albedo_texture != null:
									print("    albedo = " + str(mat.albedo_texture.resource_name) + " / " + str(mat.albedo_texture.resource_path))
								if mat.normal_texture != null:
									print("    normal = " + str(mat.normal_texture.resource_name) + " / " + str(mat.normal_texture.resource_path))
								ResourceSaver.save(respath, mat)
								mat = load(respath)
								print("Save-and-load material object " + str(mat_name) + " " + str(mat.resource_name) + "@" + str(mat.resource_path))
								if mat.albedo_texture != null:
									print("    albedo = " + str(mat.albedo_texture.resource_name) + " / " + str(mat.albedo_texture.resource_path))
								if mat.normal_texture != null:
									print("    normal = " + str(mat.normal_texture.resource_name) + " / " + str(mat.normal_texture.resource_path))
							print("Mat for " + str(i) + " is " + str(mat))
							if mat != null:
								mesh.surface_set_material(i, mat)
								saved_materials_by_name[mat_name] = mat
								metaobj.insert_resource(fileId, mat)
						# print("MeshInstance " + str(scene.get_path_to(node)) + " / Mesh " + str(mesh.resource_name if mesh != null else "NULL")+ " Material " + str(i) + " name " + str(mat.resource_name if mat != null else "NULL"))
					# print("Looking up " + str(mesh_name) + " in " + str(objtype_to_name_to_id.get("Mesh", {})))
					fileId = get_obj_id("Mesh", sanitize_unique_name(mesh_name))
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
								var respath: String = get_resource_path(mesh_name, ".mesh")
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
					fileId = get_obj_id("AnimationClip", sanitize_anim_name(anim_name))
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
					# print("AnimationPlayer " + str(scene.get_path_to(node)) + " / Anim " + str(i) + " anim_name: " + anim_name + " resource_name: " + str(anim.resource_name))
					i += 1
			for child in node.get_children():
				iterate(child)

	func adjust_skin_scale(skin: Skin):
		if scale_correction_factor == 1.0:
			return
		# MESH and SKIN data divide, to compensate for object position multiplying.
		for i in range(skin.get_bind_count()):
			var transform = skin.get_bind_pose(i)
			skin.set_bind_pose(i, Transform3D(transform.basis, transform.origin * scale_correction_factor))

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
			#print("About to multiply mesh vertices by " + str(scale_correction_factor) + ": " + str(arr[ArrayMesh.ARRAY_VERTEX][0]))
			var vert_arr_len: int = (len(arr[ArrayMesh.ARRAY_VERTEX]))
			var i: int = 0
			while i < vert_arr_len:
				arr[ArrayMesh.ARRAY_VERTEX][i] = arr[ArrayMesh.ARRAY_VERTEX][i] * scale_correction_factor
				i += 1
			#print("Done multiplying mesh vertices by " + str(scale_correction_factor) + ": " + str(arr[ArrayMesh.ARRAY_VERTEX][0]))
			for bsidx in range(len(bsarr)):
				i = 0
				var ilen: int = (len(bsarr[bsidx][ArrayMesh.ARRAY_VERTEX]))
				while i < ilen:
					bsarr[bsidx][ArrayMesh.ARRAY_VERTEX][i] = bsarr[bsidx][ArrayMesh.ARRAY_VERTEX][i] * scale_correction_factor
					i += 1
				bsarr[bsidx].resize(3)
				#print("format flags: " + str(fmt_compress_flags & 7) + "|" + str(typeof(bsarr[bsidx][0]))+"|"+str(typeof(bsarr[bsidx][0]))+"|"+str(typeof(bsarr[bsidx][0])))
				#print("Len arr " + str(len(arr)) + " bsidx " + str(bsidx) + " len bsarr[bsidx] " + str(len(bsarr[bsidx])))
				#for i in range(len(arr)):
				#	if i >= ArrayMesh.ARRAY_INDEX or typeof(arr[i]) == TYPE_NIL:
				#		bsarr[bsidx][i] = null
				#	elif typeof(bsarr[bsidx][i]) == TYPE_NIL or len(bsarr[bsidx][i]) == 0:
				#		bsarr[bsidx][i] = arr[i].duplicate()
				#		bsarr[bsidx][i].resize(0)
				#		bsarr[bsidx][i].resize(len(arr[i]))

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
			#print("Adding mesh vertices by " + str(scale_correction_factor) + ": " + str(arr[ArrayMesh.ARRAY_VERTEX][0]))
			mesh.add_surface_from_arrays(prim, arr, bsarr, lods, fmt_compress_flags)
			mesh.surface_set_name(surf_idx, name)
			mesh.surface_set_material(surf_idx, mat)
			#print("Get mesh vertices by " + str(scale_correction_factor) + ": " + str(mesh.surface_get_arrays(surf_idx)[ArrayMesh.ARRAY_VERTEX][0]))
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
					var i: int = 0
					var ilen: int = len(xform_keys)
					while i < ilen:
						xform_keys[i + 2] *= scale_correction_factor
						xform_keys[i + 3] *= scale_correction_factor
						xform_keys[i + 4] *= scale_correction_factor
						i += 12
					anim.set("tracks/" + str(trackidx) + "/keys", xform_keys)
				"value":
					if path.ends_with(":position") or path.ends_with(":transform"):
						var track_dict: Dictionary = anim.get("tracks/" + str(trackidx) + "/keys")
						var track_values: Array = track_dict.get("values")
						var i: int = 0
						var ilen: int = len(track_values)
						if path.ends_with(":transform"):
							while i < ilen:
								track_values[i] = Transform3D(track_values[i].basis, track_values[i].origin * scale_correction_factor)
								i += 1
						else:
							while i < ilen:
								track_values[i] *= scale_correction_factor
								i += 1
						track_dict["values"] = track_values
						anim.set("tracks/" + str(trackidx) + "/keys", track_dict)
				"bezier":
					if path.ends_with(":position") or path.ends_with(":transform"):
						var track_dict: Dictionary = anim.get("tracks/" + str(trackidx) + "/keys")
						var track_values: Variant = track_dict.get("points") # Some sort of packed array?
						var i: int = 0
						var ilen: int = len(track_values)
						# VALUE, inX, inY, outX, outY
						if path.ends_with(":transform"):
							while i < ilen:
								if ((i % 5) % 2) != 1:
									track_values[i] = Transform3D(track_values[i].basis, track_values[i].origin * scale_correction_factor)
								i += 1
						else:
							while i < ilen:
								if ((i % 5) % 2) != 1:
									track_values[i] *= scale_correction_factor
								i += 1
						track_dict["points"] = track_values
						anim.set("tracks/" + str(trackidx) + "/keys", track_dict)

	func adjust_animation(anim: Animation):
		adjust_animation_scale(anim)
		# Root motion?
		# Splitting up animation?

	func lookup_unity_name(node_or_bone_name: StringName):
		var sanitized = sanitize_bone_name(node_or_bone_name)
		if goname_to_unity_name.has(sanitized):
			return goname_to_unity_name[sanitized]
		return node_or_bone_name

	var all_name_map: Dictionary = {}
	func build_name_map_recursive(skinned_parents: Dictionary, node: Node, p_skel_bone=-1, attachments_by_bone_name={}, from_skinned_parent=false) -> int:
		var children_to_recurse = []
		var name_map = {}
		if node is Skeleton3D:
			var skel_bone: int = p_skel_bone
			assert(skel_bone != -1)
			for child_bone in node.get_bone_children(skel_bone):
				var new_id = self.build_name_map_recursive(skinned_parents, node, child_bone, attachments_by_bone_name)
				if new_id != 0:
					name_map[lookup_unity_name(node.get_bone_name(child_bone))] = new_id
			var bone_name = node.get_bone_name(skel_bone)
			bone_name = self.sanitize_bone_name(bone_name)
			var fileId_go: int = get_obj_id("GameObject", bone_name)
			var fileId_trans: int = get_obj_id("Transform", bone_name)
			name_map[1] = fileId_go
			name_map[4] = fileId_trans
			for p_attachment in attachments_by_bone_name.get(bone_name, []):
				var attachment_node: Node = p_attachment
				for child in attachment_node.get_children():
					if child is MeshInstance3D:
						if has_obj_id("SkinnedMeshRenderer", bone_name): #child.get_blend_shape_count() > 0:
							var fileId_smr: int = get_obj_id("SkinnedMeshRenderer", bone_name)
							name_map[137] = fileId_smr
						else:
							var fileId_mr: int = get_obj_id("MeshRenderer", bone_name)
							var fileId_mf: int = get_obj_id("MeshFilter", bone_name)
							name_map[23] = fileId_mr
							name_map[33] = fileId_mf
					elif child is Camera3D:
						var fileId_cam: int = get_obj_id("Camera", bone_name)
						name_map[20] = fileId_cam
					elif child is Light3D:
						var fileId_light: int = get_obj_id("Light", bone_name)
						name_map[108] = fileId_light
					elif child is Skeleton3D:
						var new_attachments_by_bone_name = {}
						for possible_attach in child.get_children():
							if possible_attach is BoneAttachment3D:
								var bn = possible_attach.bone_name
								if not new_attachments_by_bone_name.has(bn):
									new_attachments_by_bone_name[bn] = [].duplicate()
								new_attachments_by_bone_name[bn].append(possible_attach)
						for child_child_bone in child.get_parentless_bones():
							var new_id = self.build_name_map_recursive(skinned_parents, child, child_child_bone, new_attachments_by_bone_name)
							if new_id != 0:
								name_map[self.lookup_unity_name(child.get_bone_name(child_child_bone))] = new_id
					else:
						var new_id = self.build_name_map_recursive(skinned_parents, child)
						if new_id != 0:
							name_map[self.lookup_unity_name(child.name)] = new_id
			self.all_name_map[fileId_go] = name_map
			return fileId_go
		else:
			var node_name = self.sanitize_bone_name(node.name)
			var fileId_go: int = get_obj_id("GameObject", node_name)
			var fileId_trans: int = get_obj_id("Transform", node_name)
			name_map[1] = fileId_go
			name_map[4] = fileId_trans
			if node is MeshInstance3D:
				if node.skin != null and not skinned_parents.is_empty() and not from_skinned_parent:
					return 0 # We already recursed into this skinned mesh.
				if has_obj_id("SkinnedMeshRenderer", node_name): #child.get_blend_shape_count() > 0:
					var fileId_smr: int = get_obj_id("SkinnedMeshRenderer", node_name)
					name_map[137] = fileId_smr
				else:
					var fileId_mr: int = get_obj_id("MeshRenderer", node_name)
					var fileId_mf: int = get_obj_id("MeshFilter", node_name)
					name_map[23] = fileId_mr
					name_map[33] = fileId_mf
			elif node is Camera3D:
				var fileId_cam: int = get_obj_id("Camera", node_name)
				name_map[20] = fileId_cam
			elif node is Light3D:
				var fileId_light: int = get_obj_id("Light", node_name)
				name_map[108] = fileId_light
			for child in node.get_children():
				if child is Skeleton3D:
					var new_attachments_by_bone_name = {}
					for possible_attach in child.get_children():
						if possible_attach is BoneAttachment3D:
							var bn = possible_attach.bone_name
							if not new_attachments_by_bone_name.has(bn):
								new_attachments_by_bone_name[bn] = [].duplicate()
							new_attachments_by_bone_name[bn].append(possible_attach)
					for child_child_bone in child.get_parentless_bones():
						var new_id = self.build_name_map_recursive(skinned_parents, child, child_child_bone, new_attachments_by_bone_name, false)
						if new_id != 0:
							name_map[self.lookup_unity_name(child.get_bone_name(child_child_bone))] = new_id
				else:
					var new_id = self.build_name_map_recursive(skinned_parents, child)
					if new_id != 0:
						name_map[self.lookup_unity_name(child.name)] = new_id
			for child in skinned_parents.get(node.name, {}):
				var new_id = self.build_name_map_recursive(skinned_parents, child, -1, {}, true)
				if new_id != 0:
					name_map[self.lookup_unity_name(child.name)] = new_id
			self.all_name_map[fileId_go] = name_map
			return fileId_go


func _post_import(p_scene: Node) -> Object:
	var source_file_path: String = get_source_file()
	#print ("todo post import replace " + str(source_file_path))
	var rel_path = source_file_path.replace("res://", "")
	print("Parsing meta at " + source_file_path)
	var asset_database = asset_database_class.new().get_singleton()
	default_material = asset_database.default_material_reference
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
	metaobj.initialize(asset_database)
	print(str(metaobj.importer))

	# For now, we assume all data is available in the asset database resource.
	# var metafile = source_file_path + ".meta"
	var ps: ParseState = ParseState.new()
	ps.object_adapter = object_adapter
	ps.scene = p_scene
	ps.source_file_path = source_file_path
	ps.metaobj = metaobj
	ps.asset_database = asset_database
	ps.material_to_texture_name = metaobj.internal_data.get("material_to_texture_name", {})
	ps.scale_correction_factor = metaobj.internal_data.get("scale_correction_factor", 1.0)
	ps.extractLegacyMaterials = metaobj.importer.keys.get("materials", {}).get("materialLocation", 0) == 0
	ps.importMaterials = metaobj.importer.keys.get("materials", {}).get("materialImportMode", metaobj.importer.keys.get("materials", {}).get("importMaterials", 1)) == 1
	ps.materialSearch = metaobj.importer.keys.get("materials", {}).get("materialSearch", 1)
	ps.legacy_material_name_setting = metaobj.importer.keys.get("materials", {}).get("materialName", 0)
	ps.default_material = default_material
	ps.is_obj = is_obj
	print("Path " + str(source_file_path) + " correcting scale by " + str(ps.scale_correction_factor))
	#### Setting root_scale through the .import ConfigFile doesn't seem to be working foro me. ## p_scene.scale /= ps.scale_correction_factor
	var external_objects: Dictionary = metaobj.importer.get_external_objects()
	ps.external_objects_by_type_name = external_objects
	var mesh_count: int = ps.count_meshes(p_scene)

	var internalIdMapping: Array = []
	if metaobj.importer != null and typeof(metaobj.importer.get("internalIDToNameTable")) != TYPE_NIL:
		internalIdMapping = metaobj.importer.get("internalIDToNameTable")
	if metaobj.importer != null and typeof(metaobj.importer.get("fileIDToRecycleName")) != TYPE_NIL:
		var recycles: Dictionary = metaobj.importer.fileIDToRecycleName
		for fileIdStr in recycles:
			var obj_name: String = recycles[fileIdStr]
			var fileId: int = int(str(fileIdStr).to_int())
			var utype: int = fileId / 100000
			internalIdMapping.append({"first": {utype: fileId}, "second": obj_name})
#  fileIDToRecycleName:
#    100000: //RootNode
#    100002: Box023
#  internalIDToNameTable:
#  - first:
#      1: 100000
#    second: //RootNode
#  - first:
#      1: 100002
#    second: Armature
	var used_names_by_type: Dictionary = {}.duplicate()
	# defaults:
	metaobj.prefab_main_gameobject_id = 100000
	metaobj.prefab_main_transform_id = 400000
	var animator_fileid = 0
	for id_mapping in internalIdMapping:
		var og_obj_name: String = id_mapping.get("second")
		for utypestr in id_mapping.get("first"):
			var fileId: int = int(id_mapping.get("first").get(utypestr))
			var utype: int = int(utypestr)
			var obj_name: String = og_obj_name
			var type: String = str(object_adapter.to_classname(fileId / 100000))
			if obj_name.begins_with("//"):
				# Not sure why, but Unity uses //RootNode
				# Maybe it indicates that the node will be hidden???
				obj_name = ""
				ps.use_scene_root = true
				if type == "GameObject":
					metaobj.prefab_main_gameobject_id = fileId
				if type == "Transform":
					metaobj.prefab_main_transform_id = fileId
				#if is_obj or is_dae:
				#else:
				#	obj_name = obj_name.substr(2)
			if (type == "Transform" or type == "GameObject" or type == "Animator" or type == "Light" or type == "Camera"):
				obj_name = ps.sanitize_bone_name(obj_name)
			elif type == "AnimationClip":
				obj_name = ps.sanitize_anim_name(obj_name)
			elif (type == "MeshRenderer" or type == "MeshFilter" or type == "SkinnedMeshRenderer"):
				obj_name = ps.sanitize_bone_name(obj_name)
				if obj_name.is_empty() and mesh_count == 1:
					print("Found empty obj " + str(og_obj_name) + " tpye " + type)
					ps.mesh_is_toplevel = true
			else:
				obj_name = ps.sanitize_unique_name(obj_name)
			if not ps.objtype_to_name_to_id.has(type):
				ps.objtype_to_name_to_id[type] = {}.duplicate()
				used_names_by_type[type] = {}.duplicate()
			var orig_obj_name: String = obj_name
			var next_num: int = used_names_by_type.get(type).get(orig_obj_name, 1)
			while used_names_by_type[type].has(obj_name):
				obj_name = "%s%d" % [orig_obj_name, next_num] # No space is deliberate, from sanitization rules.
				next_num += 1
			if type == "GameObject":
				ps.goname_to_unity_name[obj_name] = og_obj_name
			if type == "Animator":
				animator_fileid = fileId
			used_names_by_type[type][orig_obj_name] = next_num
			used_names_by_type[type][obj_name] = 1
			#print("Adding recycle id " + str(fileId) + " and type " + str(type) + " and utype " + str(fileId / 100000) + ": " + str(obj_name))
			ps.objtype_to_name_to_id[type][obj_name] = fileId
			ps.used_ids[fileId] = true
			ps.objtype_to_next_id[type] = utype * 100000
			if external_objects.get(type, {}).has(og_obj_name):
				ps.external_objects_by_id[fileId] = external_objects.get(type).get(og_obj_name)

	#print("Ext objs by id: "+ str(ps.external_objects_by_id))
	#print("objtype name by id: "+ str(ps.objtype_to_name_to_id))
	ps.toplevel_node = p_scene
	p_scene.name = source_file_path.get_file().get_basename()
	var new_toplevel: Node3D = null
	if ps.mesh_is_toplevel:
		print("Mesh is toplevel for " + str(source_file_path))
		new_toplevel = ps.fold_transforms_into_mesh(ps.toplevel_node)
	#else:
	# new_toplevel = ps.fold_root_transforms_into_root(ps.toplevel_node)
	if new_toplevel != null:
		ps.toplevel_node.transform = new_toplevel.transform
		new_toplevel.transform = Transform3D.IDENTITY
		ps.toplevel_node = new_toplevel

	# GameObject references always point to the toplevel node:
	ps.fileid_to_nodepath[ps.objtype_to_name_to_id.get("GameObject", {}).get("", 0)] = NodePath(".")
	ps.fileid_to_nodepath[ps.objtype_to_name_to_id.get("Transform", {}).get("", 0)] = NodePath(".")
	ps.iterate(ps.toplevel_node)

	metaobj.type_to_fileids = {}.duplicate()

	var nodepath_to_gameobject: Dictionary = {}.duplicate()
	for fileId in ps.fileid_to_nodepath:
		var utype: int = fileId / 100000
		if utype == 1:
			nodepath_to_gameobject[ps.fileid_to_nodepath.get(fileId)] = fileId

	#print(str(nodepath_to_gameobject))

	for fileId in ps.fileid_to_nodepath:
		# Guaranteed for imported files
		var utype: int = fileId / 100000
		ps.fileid_to_utype[fileId] = utype
		var type: String = object_adapter.to_classname(utype)
		if not metaobj.type_to_fileids.has(type):
			metaobj.type_to_fileids[type] = PackedInt64Array()
		metaobj.type_to_fileids[type].push_back(fileId)
		#var np: NodePath = ps.fileid_to_nodepath.get(fileId)
		#if nodepath_to_gameobject.has(np):
		#	metaobj.fileid_to_gameobject_fileid[fileId] = nodepath_to_gameobject[np]
		#elif type != "AnimationClip" and type != "Mesh":
		#	push_error("fileid " + str(fileId) + " at nodepath " + str(np) + " missing GameObject fileid")

	metaobj.fileid_to_nodepath = ps.fileid_to_nodepath
	metaobj.fileid_to_skeleton_bone = ps.fileid_to_skeleton_bone
	metaobj.fileid_to_utype = ps.fileid_to_utype
	metaobj.fileid_to_gameobject_fileid = ps.fileid_to_gameobject_fileid

	var skinned_name_to_node = build_skinned_name_to_node_map(ps.toplevel_node, {}.duplicate())
	var skinned_parents: Variant = metaobj.internal_data.get("skinned_parents", null)
	var skinned_parent_to_node = {}
	#print(skinned_name_to_node)
	if typeof(skinned_parents) == TYPE_DICTIONARY:
		for par in skinned_parents:
			var node_list = []
			for skinned_name in skinned_parents[par]:
				if skinned_name_to_node.has(skinned_name):
					node_list.append(skinned_name_to_node[skinned_name])
				else:
					print("Missing skinned " + str(skinned_name))
			skinned_parent_to_node[par] = node_list
	var root_go_id = ps.build_name_map_recursive(skinned_parent_to_node, ps.toplevel_node)
	for child in skinned_parents.get("", {}):
		ps.build_name_map_recursive(skinned_parent_to_node, child, -1, {}, true)
	if ps.use_scene_root and new_toplevel == null:
		for child in ps.all_name_map[root_go_id]:
			if typeof(child) == TYPE_STRING_NAME or typeof(child) == TYPE_STRING:
				root_go_id = ps.all_name_map[root_go_id][child]
				assert(root_go_id == ps.all_name_map[root_go_id][1])
				break
	#print(ps.goname_to_unity_name)
	metaobj.prefab_main_gameobject_id = ps.all_name_map[root_go_id][1]
	metaobj.prefab_main_transform_id = ps.all_name_map[root_go_id][4]
	ps.all_name_map[root_go_id][95] = animator_fileid
	#TODO: loop recursively through scene (including skeleton bones!) and add goname_to_unity_name[each thing] into name_map then set name
	metaobj.gameobject_name_to_fileid_and_children = ps.all_name_map
	metaobj.prefab_gameobject_name_to_fileid_and_children = ps.all_name_map

	asset_database.save()

	return p_scene

func build_skinned_name_to_node_map(node: Node, p_name_to_node_dict: Dictionary):
	var name_to_node_dict = p_name_to_node_dict
	for child in node.get_children():
		name_to_node_dict = build_skinned_name_to_node_map(child, name_to_node_dict)
	if node is MeshInstance3D:
		if node.skin != null:
			name_to_node_dict[node.name] = node
	return name_to_node_dict

static func unsrs(n: int, shift: int) -> int:
	return ((n >> 1) & 0x7fffffffffffffff) >> (shift - 1)

func generate_object_hash(dupe_map: Dictionary, type: String, obj_path: String) -> int:
	var t = "Type:" + type + "->" + obj_path
	dupe_map[t] = dupe_map.get(t, -1) + 1
	t += str(dupe_map[t])
	return xxHash64(t.to_utf8_buffer())

static func xxHash64(buffer: PackedByteArray, seed = 0) -> int:
	# https://github.com/Jason3S/xxhash
	# MIT License
	#
	# Copyright (c) 2019 Jason Dent
	#
	# Permission is hereby granted, free of charge, to any person obtaining a copy
	# of this software and associated documentation files (the "Software"), to deal
	# in the Software without restriction, including without limitation the rights
	# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	# copies of the Software, and to permit persons to whom the Software is
	# furnished to do so, subject to the following conditions:
	#
	# The above copyright notice and this permission notice shall be included in all
	# copies or substantial portions of the Software.
	#
	# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	# SOFTWARE.
	#
	# Parts based on https://github.com/Cyan4973/xxHash
	# xxHash Library - Copyright (c) 2012-2021 Yann Collet (BSD 2-clause)

	var b: PackedByteArray = buffer
	var b32: PackedInt32Array = buffer.to_int32_array()
	var b64: PackedInt64Array = buffer.to_int64_array()

	const PRIME64_1 = -7046029288634856825
	const PRIME64_2 = -4417276706812531889
	const PRIME64_3 = 1609587929392839161
	const PRIME64_4 = -8796714831421723037
	const PRIME64_5 = 2870177450012600261
	var acc: int = (seed + PRIME64_5)
	var offset: int = 0

	if len(b) >= 16:
		var accN: PackedInt64Array = PackedInt64Array([
			seed + PRIME64_1 + PRIME64_2,
			seed + PRIME64_2,
			seed + 0,
			seed - PRIME64_1,
		])
		var limit: int = len(b) - 16
		var lane: int = 0
		offset = 0
		while (offset & 0xffffff70) <= limit:
			accN[lane] += b64[offset / 8] * PRIME64_2
			accN[lane] = ((accN[lane] << 31) | unsrs(accN[lane], 33)) * PRIME64_1
			offset += 8
			lane = (lane + 1) & 3
		acc = (((accN[0] << 1) | unsrs(accN[0], 63)) +
				((accN[1] << 7) | unsrs(accN[1], 57)) +
				((accN[2] << 12) | unsrs(accN[2], 52)) +
				((accN[3] << 18) | unsrs(accN[3], 46)))
		for i in range(4):
			accN[i] = accN[i] * PRIME64_2
			accN[i] = ((accN[i] << 31) | unsrs(accN[i], 33)) * PRIME64_1
			acc = acc ^ accN[i]
			acc = acc * PRIME64_1 + PRIME64_4

	acc = acc + len(buffer)
	var limit = len(buffer) - 8
	while offset <= limit:
		var k1: int = b64[offset/8] * PRIME64_2
		acc ^= ((k1 << 31) | unsrs(k1, 33)) * PRIME64_1
		acc = ((acc << 27) | unsrs(acc, 37)) * PRIME64_1 + PRIME64_4
		offset += 8

	limit = len(buffer) - 4
	if offset <= limit:
		acc = acc ^ (b32[offset/4] * PRIME64_1)
		acc = ((acc << 23) | unsrs(acc, 41)) * PRIME64_2 + PRIME64_3
		offset += 4

	while offset < len(b):
		var lane: int = b[offset]
		acc = acc ^ (lane * PRIME64_5)
		acc = ((acc << 11) | unsrs(acc, 53)) * PRIME64_1
		offset += 1

	acc = acc ^ unsrs(acc, 33)
	acc = acc * PRIME64_2
	acc = acc ^ unsrs(acc, 29)
	acc = acc * PRIME64_3
	acc = acc ^ unsrs(acc, 32)
	return acc

func test_xxHash64():
	assert(xxHash64('a'.to_ascii_buffer()) == 3104179880475896308)
	assert(xxHash64('asdfghasdfghasdfghasdfghasdfghasdfghasdfghasdfghasdfghasdfghasdfghasdfgh'.to_ascii_buffer()) == -3292477735350538661)
	assert(xxHash64(PackedByteArray().duplicate()) == -1205034819632174695)
