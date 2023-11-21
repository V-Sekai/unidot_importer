# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends EditorScenePostImport

const asset_database_class: GDScript = preload("./asset_database.gd")
const asset_meta_class: GDScript = preload("./asset_meta.gd")
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

const ROOT_NODE_NAME = "//RootNode"


class ParseState:
	var object_adapter: Object
	var scene: Node
	var toplevel_node: Node
	var metaobj: Resource
	var source_file_path: String
	var use_new_names: bool = false
	var preserve_hierarchy: bool = false
	var preserve_hierarchy_orig_root_node_name: String = ""

	var skinned_parent_to_node: Dictionary = {}.duplicate()
	var godot_sanitized_to_orig_remap: Dictionary = {}.duplicate()
	var bone_map_dict: Dictionary
	var external_objects_by_id: Dictionary = {}.duplicate()  # fileId -> UnityRef Array
	var external_objects_by_type_name: Dictionary = {}.duplicate()  # type -> name -> UnityRef Array
	var material_to_texture_name: Dictionary = {}.duplicate()  # for Extract Legacy Materials / By Base Texture Name
	var animation_to_take_name: Dictionary = {}.duplicate()

	var saved_materials_by_name: Dictionary = {}.duplicate()
	var saved_meshes_by_name: Dictionary = {}.duplicate()
	var saved_skins_by_name: Dictionary = {}.duplicate()
	var saved_animations_by_name: Dictionary = {}.duplicate()

	var nodes_by_name: Dictionary = {}.duplicate()
	var skeleton_bones_by_name: Dictionary = {}.duplicate()
	var objtype_to_name_to_id: Dictionary = {}.duplicate()
	var objtype_to_next_id: Dictionary = {}.duplicate()
	var used_ids: Dictionary = {}.duplicate()
	var new_name_dupe_map: Dictionary = {}.duplicate()

	var fileid_to_nodepath: Dictionary = {}.duplicate()
	var fileid_to_skeleton_bone: Dictionary = {}.duplicate()
	var fileid_to_utype: Dictionary = {}.duplicate()
	var fileid_to_gameobject_fileid: Dictionary = {}.duplicate()
	var type_to_fileids: Dictionary = {}.duplicate()
	var transform_fileid_to_rotation_delta: Dictionary = {}.duplicate()
	var transform_fileid_to_parent_fileid: Dictionary = {}.duplicate()
	var humanoid_original_transforms: Dictionary
	var humanoid_skeleton_hip_position: Vector3 = Vector3(0.0, 1.0, 0.0)

	var all_name_map: Dictionary = {}.duplicate()

	var root_rotation_delta: Transform3D = Transform3D.IDENTITY
	var is_obj: bool = false
	var is_dae: bool = false
	var default_obj_mesh_name: String = "default"
	var node_is_toplevel: bool = false
	var extractLegacyMaterials: bool = false
	var importMaterials: bool = true
	var materialSearch: int = 1
	var legacy_material_name_setting: int = 1
	var default_material: Material = null
	var asset_database: Resource = null

	# Uh... they... forgot a function?????
	func pop_back(arr: PackedStringArray):
		arr.remove_at(len(arr) - 1)

	# Do we actually need this? Ordering?
	#var materials = [].duplicate()
	#var meshes = [].duplicate()
	#var animations = [].duplicate()
	#var nodes = [].duplicate()

	#func has_obj_id(type: String, name: String) -> bool:
	#	return objtype_to_name_to_id.get(type, {}).has(name)

	func generate_object_hash(dupe_map: Dictionary, type: String, obj_path: String) -> int:
		var ret: int = HashGenerator.generate_object_hash(dupe_map, type, obj_path)
		var t: String = "Type:" + type + "->" + obj_path
		t += str(dupe_map[t])
		metaobj.log_debug(ret, "Hash " + t + " => " + str(ret))
		return ret

	func get_obj_id(type: String, path: PackedStringArray, name: String) -> int:
		if type == "PrefabInstance":
			# May be based on hash in gltf docs, not sure. Anyway for fbx 100100000 seems ok
			return 100100000  # I think we'll just hardcode this.
		if type == "AnimationClip":
			name = animation_to_take_name.get(name, name)
		if self.is_dae and path == PackedStringArray():
			name = name.replace(" ", "_")

		var name_key = type + "|" + name
		var old_style_name = name
		if new_name_dupe_map.has(name_key):
			old_style_name = old_style_name + " " + str(new_name_dupe_map[name_key])
		new_name_dupe_map[name_key] = new_name_dupe_map.get(name_key, 0) + 1
		if objtype_to_name_to_id.get(type, {}).has(old_style_name): # Pre-Unity 2019
			return objtype_to_name_to_id.get(type, {}).get(old_style_name, 0)
		elif use_new_names: # Post Unity 2019
			var pathstr = name
			if len(path) > 0:
				pathstr = ""
				for i in range(len(path)):
					if i != 0:
						pathstr += "/"
					pathstr += path[i]
			return generate_object_hash(new_name_dupe_map, type, pathstr)
		else: # Pre Unity 2019, not in map
			if type == "Animator":
				return 9500000
			var next_obj_id: int = objtype_to_next_id.get(type, object_adapter.to_utype(type) * 100000)
			while used_ids.has(next_obj_id):
				next_obj_id += 2
			objtype_to_next_id[type] = next_obj_id + 2
			used_ids[next_obj_id] = true
			if type != "Material":
				metaobj.log_warn(next_obj_id, "Generating id " + str(next_obj_id) + " for " + str(name) + " type " + str(type))
			return next_obj_id

	func get_orig_name(obj_gltf_type: String, p_obj_name: String) -> String:
		var obj_name = p_obj_name
		if obj_gltf_type == "nodes" and p_obj_name == "Skeleton3D" and not bone_map_dict.is_empty():
			obj_name = "GeneralSkeleton"
		if obj_gltf_type == "bone_name" and not bone_map_dict.is_empty():
			var bone_mapped = bone_map_dict.get(p_obj_name, "")
			if bone_mapped != "":
				obj_name = bone_mapped
			metaobj.log_debug(0, "Lookup bone name " + str(p_obj_name) + " -> " + str(obj_name))
		return self.godot_sanitized_to_orig_remap.get(obj_gltf_type, {}).get(obj_name, obj_name)

	func build_skinned_name_to_node_map(node: Node, p_name_to_node_dict: Dictionary) -> Dictionary:
		var name_to_node_dict: Dictionary = p_name_to_node_dict
		var node_name = get_orig_name("nodes", node.name)
		for child in node.get_children():
			name_to_node_dict = build_skinned_name_to_node_map(child, name_to_node_dict)
		metaobj.log_debug(0, "node.name " + str(node_name) + ": " + str(name_to_node_dict))
		if node is MeshInstance3D:
			if node.skin != null:
				name_to_node_dict[node_name] = node
				metaobj.log_debug(0, "adding " + str(node_name) + ": " + str(name_to_node_dict))
		return name_to_node_dict

	func get_resource_path(sanitized_name: String, extension: String) -> String:
		# return source_file_path.get_basename() + "." + str(fileId) + extension
		return source_file_path.get_basename() + "." + sanitize_filename(sanitized_name) + extension

	func get_parent_materials_paths(material_name: String) -> Array:
		# return source_file_path.get_basename() + "." + str(fileId) + extension
		var retlist: Array = []
		var basedir: String = source_file_path.get_base_dir()
		while basedir != "res://" and basedir != "/" and not basedir.is_empty() and basedir != ".":
			retlist.append(get_materials_path_base(material_name, basedir))
			basedir = basedir.get_base_dir()
		retlist.append(get_materials_path_base(material_name, "res://"))
		metaobj.log_debug(0, "Looking in directories " + str(retlist))
		return retlist

	func get_materials_path_base(material_name: String, base_dir: String) -> String:
		# return source_file_path.get_basename() + "." + str(fileId) + extension
		return base_dir + "/Materials/" + str(material_name) + ".mat.tres"

	func get_materials_path(material_name: String) -> String:
		return get_materials_path_base(material_name, source_file_path.get_base_dir())

	func sanitize_filename(sanitized_name: String) -> String:
		return sanitized_name.replace("/", "").replace(":", "").replace(".", "").replace("@", "").replace('"', "").replace("<", "").replace(">", "").replace("*", "").replace("|", "").replace("?", "")

	func fold_root_transforms_into_only_child() -> bool:
		# FIXME: Animations targeting the parent or the child might need to be adjusted.
		var root_node: Node3D = toplevel_node
		var is_foldable: bool = root_node.get_child_count() == 1
		var wanted_child: int = 0
		if root_node.get_child_count() == 2 and root_node.get_child(0) is AnimationPlayer:
			wanted_child = 1
			is_foldable = true
		elif root_node.get_child_count() == 2 and root_node.get_child(1) is AnimationPlayer:
			is_foldable = true
		if not is_foldable:
			return false
		var child_node = root_node.get_child(wanted_child)
		if child_node is Skeleton3D:
			if len(child_node.get_parentless_bones()) > 1:
				return false
			var root_bone_idx: int = child_node.get_parentless_bones()[0]
			root_rotation_delta = root_rotation_delta * child_node.transform * child_node.get_bone_pose(root_bone_idx)
			toplevel_node = child_node
			return true
		if child_node is Node3D:
			root_rotation_delta = root_rotation_delta * child_node.transform
			toplevel_node = child_node
			return true
		return false

	func register_component(node: Node, p_path: PackedStringArray, p_component: String, fileId_go: int = 0, p_bone_idx: int = -1, parent_transform_id: int = 0):
		#???
		#if node == toplevel_node:
		#	return # GameObject nodes always point to the toplevel node.

		var nodepath: NodePath = scene.get_path_to(node)
		var gltf_type: String = "nodes"
		var orig_name: String
		if node is Skeleton3D:
			gltf_type = "bone_name"
			orig_name = get_orig_name(gltf_type, node.get_bone_name(p_bone_idx))
		elif node is AnimationPlayer:
			orig_name = get_orig_name(gltf_type, node.get_parent().name)
		else:
			orig_name = get_orig_name(gltf_type, node.name)
		p_path.push_back(p_component)
		if node == self.toplevel_node:
			orig_name = ""
		var fileId_comp: int = get_obj_id(p_component, p_path, orig_name)
		pop_back(p_path)  # Must happen first: "GameObject" does not exist in the path
		if p_component == "Transform":
			fileId_go = get_obj_id("GameObject", p_path, orig_name)

		if not all_name_map.has(fileId_go):
			all_name_map[fileId_go] = {}.duplicate()
		all_name_map[fileId_go][object_adapter.to_utype(p_component)] = fileId_comp
		if p_component == "Transform":
			transform_fileid_to_parent_fileid[fileId_comp] = parent_transform_id
			all_name_map[fileId_go][1] = fileId_go  # Redundant...
			fileid_to_nodepath[fileId_go] = nodepath
			fileid_to_gameobject_fileid[fileId_go] = fileId_go
			fileid_to_utype[fileId_go] = 1
			if not type_to_fileids.has("GameObject"):
				type_to_fileids["GameObject"] = PackedInt64Array()
			type_to_fileids["GameObject"].push_back(fileId_go)
		fileid_to_nodepath[fileId_comp] = nodepath
		#if fileId in fileid_to_skeleton_bone:
		#	fileid_to_skeleton_bone.erase(fileId)
		fileid_to_gameobject_fileid[fileId_comp] = fileId_go

		fileid_to_utype[fileId_comp] = object_adapter.to_utype(p_component)
		if not type_to_fileids.has(p_component):
			type_to_fileids[p_component] = PackedInt64Array()
		type_to_fileids[p_component].push_back(fileId_comp)

		if node is Skeleton3D:
			var og_bone_name: String = node.get_bone_name(p_bone_idx)
			fileid_to_skeleton_bone[fileId_comp] = og_bone_name
			if p_component == "Transform":
				fileid_to_skeleton_bone[fileId_go] = og_bone_name
		#metaobj.log_debug(0, "fileid_go:" + str(fileId_go) + '/ ' + str(all_name_map[fileId_go]))
		return fileId_go

	func register_resource(p_resource: Resource, p_name: String, p_type: String, fileId_object: int, p_aux_resource: Variant = null):
		# Using : Variant for argument 5 to workaround the following GDScript bug:
		# SCRIPT ERROR: Invalid type in function 'register_resource' in base 'RefCounted (ParseState)'.
		# The Object-derived class of argument 5 (null instance) is not a subclass of the expected argument class. (Resource)
		var gltf_type = "meshes"
		if p_type == "Mesh":
			metaobj.imported_mesh_paths[p_name] = str(p_resource.resource_path)
			metaobj.imported_mesh_paths["Root Scene_" + p_name] = str(p_resource.resource_path)
		if p_type == "Material":
			metaobj.imported_material_paths[p_name] = str(p_resource.resource_path)
			gltf_type = "materials"
		if p_type == "AnimationClip":
			metaobj.imported_animation_paths[p_name] = str(p_resource.resource_path)
			gltf_type = "animations"
		metaobj.insert_resource(fileId_object, p_resource)
		metaobj.log_debug(0, "Register " + str(metaobj.guid) + ":" + str(fileId_object) + ": " + str(p_type) + " '" + str(p_name) + "' " + str(p_resource))
		if p_aux_resource != null:
			metaobj.insert_resource(-fileId_object, p_aux_resource)  # Used for skin object.
			metaobj.log_debug(0, "Register aux " + str(metaobj.guid) + ":" + str(-fileId_object) + ": '" + str(p_name) + "' " + str(p_aux_resource))
		return fileId_object

	func iterate_skeleton(node: Skeleton3D, p_path: PackedStringArray, p_skel_bone: int, p_attachments_by_bone_name: Dictionary, p_parent_transform_id: int, p_global_rest:= Transform3D(), p_pre_retarget_global_rest:= Transform3D()):
		#metaobj.log_debug(0, "Skeleton iterate_skeleton " + str(node.get_class()) + ", " + str(p_path) + ", " + str(node.name))

		assert(p_skel_bone != -1)

		var fileId_go: int = register_component(node, p_path, "Transform", 0, p_skel_bone, p_parent_transform_id)
		var fileId_transform: int = all_name_map[fileId_go][4]
		var bone_name: String = node.get_bone_name(p_skel_bone)

		#	ParOrigT * ChildOrigT = GodotHumanT * X * ChildOrigT
		#	GodotHumanT = ParOrigT * GodotCorrectionT
		#	We want to solve for X = GodotCorrectionT.inv
		#	GodotCorrectionT = ParOrigT.inv * GodotHumanT
		p_global_rest *= node.get_bone_rest(p_skel_bone)
		if humanoid_original_transforms.has(bone_name):
			p_pre_retarget_global_rest *= humanoid_original_transforms.get(bone_name)
			if bone_name == "Hips":
				humanoid_skeleton_hip_position = node.get_bone_rest(p_skel_bone).origin
				humanoid_skeleton_hip_position.y = node.motion_scale
		else:
			p_pre_retarget_global_rest *= node.get_bone_rest(p_skel_bone)

		if not p_global_rest.is_equal_approx(p_pre_retarget_global_rest):
			metaobj.log_debug(0, "bone " + bone_name + " rest " + str(p_global_rest) + " pre ret " + str(p_pre_retarget_global_rest))
			transform_fileid_to_rotation_delta[fileId_transform] = p_global_rest.affine_inverse() * p_pre_retarget_global_rest
			if not node.has_meta("humanoid_rotation_delta"):
				node.set_meta("humanoid_rotation_delta", {})
			node.get_meta("humanoid_rotation_delta")[node.get_bone_name(p_skel_bone)] = transform_fileid_to_rotation_delta[fileId_transform]

		for child_bone in node.get_bone_children(p_skel_bone):
			var orig_child_name: String = get_orig_name("bone_name", node.get_bone_name(child_bone))
			p_path.push_back(orig_child_name)
			var new_id = self.iterate_skeleton(node, p_path, child_bone, p_attachments_by_bone_name, fileId_transform, p_global_rest, p_pre_retarget_global_rest)
			pop_back(p_path)
			if new_id != 0:
				self.all_name_map[fileId_go][orig_child_name] = new_id

		for p_attachment in p_attachments_by_bone_name.get(node.get_bone_name(p_skel_bone), []):
			var attachment_node: Node = p_attachment
			for child in attachment_node.get_children():
				if child is MeshInstance3D:
					if child.get_blend_shape_count() > 0:  # if skin != null
						register_component(child, p_path, "SkinnedMeshRenderer", fileId_go, p_skel_bone)
					else:
						register_component(child, p_path, "MeshFilter", fileId_go, p_skel_bone)
						register_component(child, p_path, "MeshRenderer", fileId_go, p_skel_bone)
					process_mesh_instance(child)
				elif child is Camera3D:
					register_component(child, p_path, "Camera", fileId_go, p_skel_bone)
				elif child is Light3D:
					register_component(child, p_path, "Light", fileId_go, p_skel_bone)
				elif child is Skeleton3D:
					var new_attachments_by_bone_name: Dictionary = {}.duplicate()
					for possible_attach in child.get_children():
						if possible_attach is BoneAttachment3D:
							var bn = possible_attach.bone_name
							if not new_attachments_by_bone_name.has(bn):
								new_attachments_by_bone_name[bn] = [].duplicate()
							new_attachments_by_bone_name[bn].append(possible_attach)
					for child_child_bone in child.get_parentless_bones():
						var orig_child_name: String = get_orig_name("bone_name", child.get_bone_name(child_child_bone))
						p_path.push_back(orig_child_name)
						var new_id = self.iterate_skeleton(child, p_path, child_child_bone, new_attachments_by_bone_name, fileId_transform, p_global_rest, p_pre_retarget_global_rest)
						pop_back(p_path)
						if new_id != 0:
							self.all_name_map[fileId_go][orig_child_name] = new_id
				else:
					var orig_child_name: String = get_orig_name("nodes", child.name)
					p_path.push_back(orig_child_name)
					var new_id = self.iterate_node(child, p_path, false, fileId_transform, p_global_rest, p_pre_retarget_global_rest)
					pop_back(p_path)
					if new_id != 0:
						self.all_name_map[fileId_go][orig_child_name] = new_id

		var key = p_path[len(p_path) - 1] # node.name
		# node.get_parent() == null or 
		if len(p_path) == 2 and str(p_path[1]) == "root":
			key = preserve_hierarchy_orig_root_node_name
		var skinned_children = skinned_parent_to_node.get(key, [])
		skinned_parent_to_node.erase(key)
		for child in skinned_children:
			metaobj.log_debug(0, "Skinned parent " + str(node.name) + ": " + str(child.name))
			var orig_child_name: String = get_orig_name("nodes", child.name)
			var new_id: int = 0
			if len(p_path) == 1:
				# If not preserve_hierarchy and we determined we can fold root node, that means skinned parents is empty.
				metaobj.log_fail(0, "Root node shouldn't have any skinned meshes when root is folded")
			p_path.push_back(orig_child_name)
			new_id = self.iterate_node(child, p_path, true, fileId_transform)
			pop_back(p_path)
			if new_id != 0:
				self.all_name_map[fileId_go][orig_child_name] = new_id

		return fileId_go

	func iterate_node(node: Node, p_path: PackedStringArray, from_skinned_parent: bool, p_parent_transform_id: int, p_global_rest := Transform3D(), p_pre_retarget_global_rest := Transform3D()):
		metaobj.log_debug(0, "Conventional iterate_node " + str(node.get_class()) + ", " + str(p_path) + ", " + str(node.name))
		#for child in node.get_children():
		#	iterate_node(child, p_path, false)
		var fileId_go: int = 0
		var fileId_transform: int = 0
		if len(p_path) != 1 or node.get_parent() != null:
			if not (node is AnimationPlayer):
				fileId_go = register_component(node, p_path, "Transform", 0, -1, p_parent_transform_id)
				fileId_transform = all_name_map[fileId_go][4]

			if node is AnimationPlayer:
				#var parent_node: Node3D = node.get_parent()
				#if scene.get_path_to(parent_node) == NodePath("."):
				#	parent_node = parent_node.get_child(0)
				#node_name = str(parent_node.name)
				register_component(node, p_path, "Animator", fileId_go)
				process_animation_player(node)
			elif node is MeshInstance3D:
				if node.skin != null and not skinned_parent_to_node.is_empty() and not from_skinned_parent:
					metaobj.log_debug(0, "Already recursed " + str(node.name))
					return 0  # We already recursed into this skinned mesh.
				if from_skinned_parent or node.get_blend_shape_count() > 0:  # has_obj_id("SkinnedMeshRenderer", node_name):
					register_component(node, p_path, "SkinnedMeshRenderer", fileId_go)
				else:
					register_component(node, p_path, "MeshFilter", fileId_go)
					register_component(node, p_path, "MeshRenderer", fileId_go)
				process_mesh_instance(node)
			elif node is Camera3D:
				register_component(node, p_path, "Camera", fileId_go)
			elif node is Light3D:
				register_component(node, p_path, "Light", fileId_go)
		var animplayer: AnimationPlayer = null
		for child in node.get_children():
			if child is AnimationPlayer:
				animplayer = child
				break

		if not (node is AnimationPlayer):
			p_global_rest *= node.transform
			if humanoid_original_transforms.has(node.name):
				p_pre_retarget_global_rest *= humanoid_original_transforms.get(node.name)
			else:
				p_pre_retarget_global_rest *= node.transform

		if not p_global_rest.is_equal_approx(p_pre_retarget_global_rest):
			metaobj.log_debug(0, "node " + node.name + " rest " + str(p_global_rest) + " pre ret " + str(p_pre_retarget_global_rest))
			transform_fileid_to_rotation_delta[fileId_transform] = p_global_rest.affine_inverse() * p_pre_retarget_global_rest

		if len(p_path) == 1:
			p_pre_retarget_global_rest *= root_rotation_delta

		if node.get_child_count() >= 1 and node.get_child(0).name == "RootNode":
			node = node.get_child(0)
		for child in node.get_children():
			if child is Skeleton3D:
				var new_attachments_by_bone_name = {}.duplicate()
				for possible_attach in child.get_children():
					if possible_attach is BoneAttachment3D:
						var bn = possible_attach.bone_name
						if not new_attachments_by_bone_name.has(bn):
							new_attachments_by_bone_name[bn] = [].duplicate()
						new_attachments_by_bone_name[bn].append(possible_attach)
				for child_child_bone in child.get_parentless_bones():
					var orig_child_name: String = get_orig_name("bone_name", child.get_bone_name(child_child_bone))
					if len(p_path) == 1 and node.get_parent() == null:
						preserve_hierarchy_orig_root_node_name = orig_child_name
						p_path.push_back("root")
					else:
						p_path.push_back(orig_child_name)
					var new_id = self.iterate_skeleton(child, p_path, child_child_bone, new_attachments_by_bone_name, fileId_transform, p_global_rest, p_pre_retarget_global_rest)
					pop_back(p_path)
					if len(p_path) == 1 and node.get_parent() == null:
						# HACK: If we are above the root node (due to preserve_hierarchy=false), pretend we are the child.
						fileId_go = new_id
						fileId_transform = all_name_map[fileId_go][4]
					elif new_id != 0:
						self.all_name_map[fileId_go][orig_child_name] = new_id
			else:
				if not (child is AnimationPlayer):
					var child_name: String = child.name
					if child is MeshInstance3D:
						if is_obj and child.mesh != null:
							#node_name = "default"
							child_name = default_obj_mesh_name  # Does this make sense?? For compatibility?
					var orig_child_name: String = get_orig_name("nodes", child_name)
					if len(p_path) == 1 and node.get_parent() == null:
						preserve_hierarchy_orig_root_node_name = orig_child_name
						p_path.push_back("root")
					else:
						p_path.push_back(orig_child_name)
					var new_id = self.iterate_node(child, p_path, false, fileId_transform, p_global_rest, p_pre_retarget_global_rest)
					pop_back(p_path)
					if len(p_path) == 1 and node.get_parent() == null:
						# HACK: If we are above the root node (due to preserve_hierarchy=false), pretend we are the child.
						fileId_go = new_id
						fileId_transform = all_name_map[fileId_go][4]
					elif new_id != 0:
						self.all_name_map[fileId_go][orig_child_name] = new_id
		var key = p_path[len(p_path) - 1] # node.name
		# node.get_parent() == null or 
		if len(p_path) == 2 and str(p_path[1]) == "root":
			key = preserve_hierarchy_orig_root_node_name
		for child in skinned_parent_to_node.get(key, {}):
			metaobj.log_warn(0, "Skinned parent from non-bone " + str(node.name) + ": " + str(child.name))
			var orig_child_name: String = get_orig_name("nodes", child.name)
			var new_id: int = 0
			if len(p_path) == 1:
				# If not preserve_hierarchy and we determined we can fold root node, that means skinned parents is empty.
				metaobj.log_fail(0, "Root node shouldn't have any skinned meshes when root is folded")
			p_path.push_back(orig_child_name)
			new_id = self.iterate_node(child, p_path, true, fileId_transform)
			pop_back(p_path)
			if new_id != 0:
				self.all_name_map[fileId_go][orig_child_name] = new_id
		if animplayer != null:
			self.iterate_node(animplayer, p_path, false, fileId_transform)
		return fileId_go

	func process_animation_player(node: AnimationPlayer):
		var i = 0
		var anim_lib = node.get_animation_library(node.get_animation_library_list()[0])
		var anim_list = anim_lib.get_animation_list()
		var anim_count: int = 0
		for godot_anim_name in anim_list:
			if godot_anim_name == "RESET" or godot_anim_name == "_T-Pose_":
				continue
			anim_count += 1
		for godot_anim_name in anim_list:
			if godot_anim_name == "RESET" or godot_anim_name == "_T-Pose_":
				continue
			var anim: Animation = anim_lib.get_animation(godot_anim_name)
			var anim_name: String = get_orig_name("animations", godot_anim_name)
			if saved_animations_by_name.has(anim_name):
				anim = saved_animations_by_name.get(anim_name)
				if anim != null:
					anim_lib.remove_animation(godot_anim_name)
					anim_lib.add_animation(godot_anim_name, anim)
				continue
			saved_animations_by_name[anim_name] = null
			metaobj.log_debug(0, "Process ANIM " + str(godot_anim_name))
			#if not has_obj_id("AnimationClip", get_orig_name("animations", anim_name))
			#if fileId == 0:
			#	metaobj.log_fail(0, "Missing fileId for Animation " + str(anim_name))
			#else:
			var fileId = get_obj_id("AnimationClip", PackedStringArray(), anim_name)
			if fileId != 0:
				if external_objects_by_id.has(fileId):
					anim = metaobj.get_godot_resource(external_objects_by_id.get(fileId))
				else:
					if anim != null:
						var respath: String
						if source_file_path.get_basename() == godot_anim_name or anim_count <= 1:
							respath = get_resource_path("animation", ".tres")
						else:
							respath = get_resource_path(godot_anim_name, ".tres")
						if FileAccess.file_exists(respath):
							anim.take_over_path(respath)
						ResourceSaver.save(anim, respath)
						anim = load(respath)
				if anim != null:
					anim_lib.remove_animation(godot_anim_name)
					anim_lib.add_animation(godot_anim_name, anim)
					saved_animations_by_name[anim_name] = anim
					self.register_resource(anim, anim_name, "AnimationClip", fileId)
			# metaobj.log_debug(0, "AnimationPlayer " + str(scene.get_path_to(node)) + " / Anim " + str(i) + " anim_name: " + anim_name + " resource_name: " + str(anim.resource_name))
			i += 1

	func process_mesh_instance(node: MeshInstance3D):
		metaobj.log_debug(0, "Process mesh instance: " + str(node.name))
		if node.skin == null and node.skeleton != NodePath():
			metaobj.log_fail(0, "A Skeleton exists for MeshRenderer " + str(node.name))
		if node.skin != null and node.skeleton == NodePath():
			metaobj.log_fail(0, "No Skeleton exists for SkinnedMeshRenderer " + str(node.name))
		var mesh: Mesh = node.mesh
		if mesh == null:
			return
		# FIXME: mesh_name is broken on master branch, maybe 3.2 as well.
		var godot_mesh_name: String = str(mesh.resource_name)
		if godot_mesh_name.begins_with("Root Scene_"):
			godot_mesh_name = godot_mesh_name.substr(11)
		if is_obj:
			godot_mesh_name = default_obj_mesh_name
		var mesh_name: String = get_orig_name("meshes", godot_mesh_name)
		if saved_meshes_by_name.has(mesh_name):
			mesh = saved_meshes_by_name.get(mesh_name)
			if mesh != null:
				node.mesh = mesh
			if node.skin != null:
				node.skin = saved_skins_by_name.get(mesh_name)
		else:
			saved_meshes_by_name[mesh_name] = null
			for i in range(mesh.get_surface_count()):
				var mat: Material = mesh.surface_get_material(i)
				if mat == null:
					continue
				var godot_mat_name: String = mat.resource_name
				var mat_name: String = get_orig_name("materials", godot_mat_name)
				if mat_name == "DefaultMaterial":
					mat_name = "No Name"
				if is_obj:
					mat_name = default_obj_mesh_name + "Mat"  # unity seems to use this rule
				if saved_materials_by_name.has(mat_name):
					mat = saved_materials_by_name.get(mat_name)
					if mat != null:
						mesh.surface_set_material(i, mat)
					continue
				saved_materials_by_name[mat_name] = null
				var fileId = get_obj_id("Material", PackedStringArray(), mat_name)
				metaobj.log_debug(0, "Materials " + str(importMaterials) + " legacy " + str(extractLegacyMaterials) + " fileId " + str(fileId))
				if not importMaterials:
					mat = default_material
				elif not extractLegacyMaterials and fileId == 0 and not use_new_names:
					metaobj.log_fail(0, "Missing fileId for Material " + str(mat_name))
				else:
					var new_mat: Material = null
					if external_objects_by_id.has(fileId):
						new_mat = metaobj.get_godot_resource(external_objects_by_id.get(fileId))
					elif external_objects_by_type_name.get("Material", {}).has(mat_name):
						new_mat = metaobj.get_godot_resource(external_objects_by_type_name.get("Material").get(mat_name))
					if new_mat != null:
						mat = new_mat
						metaobj.log_debug(0, "External material object " + str(fileId) + "/" + str(mat_name) + " " + str(new_mat.resource_name) + "@" + str(new_mat.resource_path))
					elif extractLegacyMaterials:
						var legacy_material_name: String = godot_mat_name
						if legacy_material_name_setting == 0:
							legacy_material_name = material_to_texture_name.get(godot_mat_name, godot_mat_name)
						if legacy_material_name_setting == 2:
							legacy_material_name = source_file_path.get_file().get_basename() + "-" + godot_mat_name

						metaobj.log_debug(0, "Extract legacy material " + mat_name + ": " + get_materials_path(legacy_material_name))
						var d = DirAccess.open("res://")
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
									if pathname.get_file() == legacy_material_name + ".material" or pathname.get_file() == godot_mat_name + ".mat.tres" or pathname.get_file() == godot_mat_name + ".mat.res":
										legacy_material_name = pathname
										mat = load(pathname)
										break
						if mat == null:
							metaobj.log_debug(0, "Material " + str(legacy_material_name) + " was not found. using default")
							mat = default_material
					else:
						var respath: String = get_resource_path(godot_mat_name, ".material")
						metaobj.log_debug(0, "Before save " + str(mat_name) + " " + str(mat.resource_name) + "@" + str(respath) + " from " + str(mat.resource_path))
						if mat.albedo_texture != null:
							metaobj.log_debug(0, "    albedo = " + str(mat.albedo_texture.resource_name) + " / " + str(mat.albedo_texture.resource_path))
						if mat.normal_texture != null:
							metaobj.log_debug(0, "    normal = " + str(mat.normal_texture.resource_name) + " / " + str(mat.normal_texture.resource_path))
						if FileAccess.file_exists(respath):
							mat.take_over_path(respath)
						ResourceSaver.save(mat, respath)
						mat = load(respath)
						metaobj.log_debug(0, "Save-and-load material object " + str(mat_name) + " " + str(mat.resource_name) + "@" + str(mat.resource_path))
						if mat.albedo_texture != null:
							metaobj.log_debug(0, "    albedo = " + str(mat.albedo_texture.resource_name) + " / " + str(mat.albedo_texture.resource_path))
						if mat.normal_texture != null:
							metaobj.log_debug(0, "    normal = " + str(mat.normal_texture.resource_name) + " / " + str(mat.normal_texture.resource_path))
					metaobj.log_debug(0, "Mat for " + str(i) + " is " + str(mat))
					if mat != null:
						mesh.surface_set_material(i, mat)
						saved_materials_by_name[mat_name] = mat
						register_resource(mat, mat_name, "Material", fileId)
				# metaobj.log_debug(0, "MeshInstance " + str(scene.get_path_to(node)) + " / Mesh " + str(mesh.resource_name if mesh != null else "NULL")+ " Material " + str(i) + " name " + str(mat.resource_name if mat != null else "NULL"))
			# metaobj.log_debug(0, "Looking up " + str(mesh_name) + " in " + str(objtype_to_name_to_id.get("Mesh", {})))
			var fileId: int = get_obj_id("Mesh", PackedStringArray(), mesh_name)
			if fileId == 0:
				metaobj.log_fail(0, "Missing fileId for Mesh " + str(mesh_name))
			else:
				var skin: Skin = node.skin
				if external_objects_by_id.has(fileId):
					mesh = metaobj.get_godot_resource(external_objects_by_id.get(fileId))
					if skin != null:
						skin = metaobj.get_godot_resource(external_objects_by_id.get(-fileId))
				else:
					if mesh != null:
						var respath: String = get_resource_path(godot_mesh_name, ".mesh")
						if FileAccess.file_exists(respath):
							mesh.take_over_path(respath)
						ResourceSaver.save(mesh, respath)
						mesh = load(respath)
					if skin != null:
						skin = skin.duplicate()
						var skel: Skeleton3D = node.get_parent() as Skeleton3D
						if skel != null and skel.has_meta("humanoid_rotation_delta"):
							skin.set_meta("humanoid_rotation_delta", skel.get_meta("humanoid_rotation_delta").duplicate())
						var respath: String = get_resource_path(godot_mesh_name, ".skin.tres")
						if FileAccess.file_exists(respath):
							skin.take_over_path(respath)
						ResourceSaver.save(skin, respath)
						skin = load(respath)
				if mesh != null:
					node.mesh = mesh
					saved_meshes_by_name[mesh_name] = mesh
					register_resource(mesh, mesh_name, "Mesh", fileId, skin)
					if skin != null:
						node.skin = skin
						saved_skins_by_name[mesh_name] = skin
		is_obj = false

func _post_import(p_scene: Node) -> Object:
	var source_file_path: String = get_source_file()
	var godot_import_config: ConfigFile = ConfigFile.new()
	if godot_import_config.load(source_file_path + ".import") != OK:
		push_error("Running _post_import script for " + str(source_file_path) + " but cannot load .import")

	var rel_path = source_file_path.replace("res://", "")
	print("Parsing meta at " + source_file_path)
	var asset_database: asset_database_class = asset_database_class.new().get_singleton()
	default_material = asset_database.default_material_reference
	var metaobj: asset_meta_class = asset_database.get_meta_at_path(rel_path)

	var f: FileAccess
	if metaobj == null:
		push_warning("Asset database missing entry for " + str(source_file_path))
		assert(not asset_database.in_package_import)
		f = FileAccess.open(source_file_path + ".meta", FileAccess.READ)
		if f:
			metaobj = asset_database.parse_meta(f, rel_path)
			f = null
		else:
			metaobj = asset_database.create_dummy_meta(rel_path)
		asset_database.insert_meta(metaobj)
	metaobj.initialize(asset_database)
	metaobj.log_debug(0, str(metaobj.importer))

	# For now, we assume all data is available in the asset database resource.
	# var metafile = source_file_path + ".meta"
	var ps: ParseState = ParseState.new()
	ps.object_adapter = object_adapter
	ps.scene = p_scene
	ps.source_file_path = source_file_path
	ps.metaobj = metaobj
	ps.asset_database = asset_database
	ps.material_to_texture_name = metaobj.internal_data.get("material_to_texture_name", {})
	ps.godot_sanitized_to_orig_remap = metaobj.internal_data.get("godot_sanitized_to_orig_remap", {})
	ps.humanoid_original_transforms = metaobj.internal_data.get("humanoid_original_transforms", {})
	if metaobj.importer.keys.get("animationType", 2) == 3:
		var bone_map: BoneMap = metaobj.importer.generate_bone_map_from_human()
		var bone_map_dict: Dictionary = {}
		for prop in bone_map.get_property_list():
			if prop["name"].begins_with("bone_map/"):
				var prof_name: String = prop["name"].trim_prefix("bone_map/")
				bone_map_dict[prof_name] = bone_map.get_skeleton_bone_name(prof_name)
		ps.bone_map_dict = bone_map_dict
	ps.extractLegacyMaterials = metaobj.importer.keys.get("materials", {}).get("materialLocation", 0) == 0
	ps.importMaterials = (metaobj.importer.keys.get("materials", {}).get("materialImportMode", metaobj.importer.keys.get("materials", {}).get("importMaterials", 1)) != 0)
	ps.materialSearch = metaobj.importer.keys.get("materials", {}).get("materialSearch", 1)
	ps.legacy_material_name_setting = metaobj.importer.keys.get("materials", {}).get("materialName", 0)
	ps.preserve_hierarchy = false
	if typeof(metaobj.importer.get("preserveHierarchy")) != TYPE_NIL:
		ps.preserve_hierarchy = metaobj.importer.preserveHierarchy
	ps.default_material = default_material
	ps.is_obj = source_file_path.ends_with(".obj")
	ps.is_dae = source_file_path.ends_with(".dae")
	metaobj.log_debug(0, "Path " + str(source_file_path))
	var external_objects: Dictionary = metaobj.importer.get_external_objects()
	ps.external_objects_by_type_name = external_objects

	var skinned_name_to_node: Dictionary = ps.build_skinned_name_to_node_map(ps.scene, {}.duplicate())
	var skinned_parents: Dictionary = metaobj.internal_data.get("skinned_parents", {})
	var skinned_parent_to_node: Dictionary = {}.duplicate()
	metaobj.log_debug(0, "Now skinning " + str(skinned_name_to_node) + " from parents " + str(skinned_parents))
	for par in skinned_parents:
		var node_list = []
		for skinned_name in skinned_parents[par]:
			if skinned_name_to_node.has(skinned_name):
				metaobj.log_debug(0, "Do skinned " + str(skinned_name) + " to " + str(skinned_name_to_node[skinned_name]))
				node_list.append(skinned_name_to_node[skinned_name])
			else:
				metaobj.log_debug(0, "Missing skinned " + str(skinned_name) + " parent " + str(par))
		skinned_parent_to_node[par] = node_list
	ps.skinned_parent_to_node = skinned_parent_to_node
	ps.default_obj_mesh_name = "default"
	if ps.is_obj:
		var objf: FileAccess = FileAccess.open(source_file_path, FileAccess.READ)
		if objf:
			var textstr = objf.get_as_text()
			objf = null
			# Find the name of the first mesh (first g before first f).
			# Note: Godot does not support splitting .obj into multiple meshes
			# So we will only use the name of the first mesh for now.
			var fidx = textstr.find("\nf ")
			var gidx = textstr.rfind("\ng ", fidx)
			if gidx == -1:
				if textstr.begins_with("g "):
					gidx = 2
			else:
				gidx += 3
			var gendidx = textstr.find("\n", gidx)
			if gendidx != -1 and gidx != -1:
				ps.default_obj_mesh_name = textstr.substr(gidx, gendidx - gidx).strip_edges()
		if ps.default_obj_mesh_name.is_empty():
			ps.default_obj_mesh_name = "default"

	var internalIdMapping: Array = []
	ps.use_new_names = false
	if metaobj.importer != null and typeof(metaobj.importer.keys.get("internalIDToNameTable")) != TYPE_NIL:
		internalIdMapping = metaobj.importer.get("internalIDToNameTable")
		ps.use_new_names = true  # FIXME: Should this only be if empty?
		metaobj.log_debug(0, "Setting new names to true")
	if metaobj.importer != null and typeof(metaobj.importer.keys.get("fileIDToRecycleName")) != TYPE_NIL:
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
	for id_mapping in internalIdMapping:
		var og_obj_name: String = id_mapping.get("second")
		for utypestr in id_mapping.get("first"):
			var fIdMaybeString: Variant = id_mapping.get("first").get(utypestr)
			# Casting to int became complicated... This could be string or int depending on yaml parser.
			if typeof(fIdMaybeString) == TYPE_STRING:
				fIdMaybeString = fIdMaybeString.to_int()
			var fileId: int = int(fIdMaybeString)
			var utype: int
			if typeof(utypestr) == TYPE_STRING:
				utype = int(utypestr.to_int())
			else:
				utype = int(utypestr)
			var obj_name: String = og_obj_name
			var type: String = str(object_adapter.to_classname(fileId / 100000))
			if obj_name.begins_with("//"):
				# Not sure why, but Unity uses //RootNode
				# Maybe it indicates that the node will be hidden???
				obj_name = ""
			elif ps.is_obj:
				obj_name = ps.default_obj_mesh_name  # Technically wrong in Unity 2019+. Should read the last "g objName" line before "f"
			if not ps.objtype_to_name_to_id.has(type):
				ps.objtype_to_name_to_id[type] = {}.duplicate()
				used_names_by_type[type] = {}.duplicate()
			var orig_obj_name: String = obj_name
			var next_num: int = used_names_by_type.get(type).get(orig_obj_name, 1)
			while used_names_by_type[type].has(obj_name):
				obj_name = "%s %d" % [orig_obj_name, next_num]  # No space is deliberate, from sanitization rules.
				next_num += 1
			used_names_by_type[type][orig_obj_name] = next_num
			used_names_by_type[type][obj_name] = 1
			#metaobj.log_debug(0, "Adding recycle id " + str(fileId) + " and type " + str(type) + " and utype " + str(fileId / 100000) + ": " + str(obj_name))
			ps.objtype_to_name_to_id[type][obj_name] = fileId
			ps.used_ids[fileId] = true
			ps.objtype_to_next_id[type] = utype * 100000
			if external_objects.get(type, {}).has(og_obj_name):
				ps.external_objects_by_id[fileId] = external_objects.get(type).get(og_obj_name)

	var animation_clips: Array[Dictionary] = metaobj.importer.get_animation_clips()
	for key in animation_clips:
		ps.animation_to_take_name[key["name"]] = key["take_name"]

	#metaobj.log_debug(0, "Ext objs by id: "+ str(ps.external_objects_by_id))
	#metaobj.log_debug(0, "objtype name by id: "+ str(ps.objtype_to_name_to_id))
	ps.toplevel_node = p_scene
	p_scene.name = source_file_path.get_file().get_basename()

	if ps.is_dae:
		# Basically, Godot implements up_axis by transforming mesh data. Unity implements it by transforming the root node.
		# We are trying to mimick Unity, so we rewrote the up_axis in the .dae in BaseModelHandler, and here we re-apply
		# the up-axis to the root node. This workflow will break if user wishes to change this in Blender after import.
		var up_axis: String = metaobj.internal_data.get("up_axis", "Y_UP")
		# * ps.toplevel_node.transform)
		if up_axis.to_upper() == "X_UP":
			ps.root_rotation_delta = Transform3D(Basis.from_euler(Vector3(0, 0, PI / -2.0)), Vector3.ZERO)
		if up_axis.to_upper() == "Z_UP":
			ps.root_rotation_delta = Transform3D(Basis.from_euler(Vector3(PI / -2.0, 0, 0)), Vector3.ZERO)

	var toplevel_path: PackedStringArray = PackedStringArray().duplicate()
	toplevel_path.push_back("//RootNode")
	var did_fold_root_transforms: bool = false
	var tmp_old_toplevel: Node3D = ps.toplevel_node
	if not ps.preserve_hierarchy and skinned_parents.get("", {}).is_empty():
		# I determined this is done before hash calculation in Unity 2019+
		# I did not test this on older versions, so I'm keeping the old order for those.
		did_fold_root_transforms = ps.fold_root_transforms_into_only_child()
	if not did_fold_root_transforms:
		toplevel_path.push_back("root")
	var tmp_root_transform_fileid = 0
	var root_go_id = ps.iterate_node(tmp_old_toplevel, toplevel_path, false, tmp_root_transform_fileid)
	if not did_fold_root_transforms:
		ps.pop_back(toplevel_path)
	var prefab_instance = ps.get_obj_id("PrefabInstance", toplevel_path, "")

	# GameObject references always point to the toplevel node:
	metaobj.prefab_main_gameobject_id = root_go_id
	metaobj.prefab_main_transform_id = ps.all_name_map[root_go_id][4]
	if !ps.root_rotation_delta.is_equal_approx(Transform3D.IDENTITY):
		metaobj.transform_fileid_to_rotation_delta[metaobj.prefab_main_transform_id] = ps.root_rotation_delta
	ps.fileid_to_nodepath[metaobj.prefab_main_gameobject_id] = NodePath(".")  # Prefab name always toplevel.
	ps.fileid_to_nodepath[metaobj.prefab_main_transform_id] = NodePath(".")
	ps.fileid_to_skeleton_bone.erase(metaobj.prefab_main_gameobject_id)
	ps.fileid_to_skeleton_bone.erase(metaobj.prefab_main_transform_id)

	metaobj.type_to_fileids = ps.type_to_fileids
	metaobj.fileid_to_nodepath = ps.fileid_to_nodepath
	metaobj.fileid_to_skeleton_bone = ps.fileid_to_skeleton_bone
	metaobj.fileid_to_utype = ps.fileid_to_utype
	metaobj.fileid_to_gameobject_fileid = ps.fileid_to_gameobject_fileid
	metaobj.transform_fileid_to_rotation_delta = ps.transform_fileid_to_rotation_delta
	metaobj.transform_fileid_to_parent_fileid = ps.transform_fileid_to_parent_fileid

	metaobj.gameobject_name_to_fileid_and_children = ps.all_name_map
	metaobj.prefab_gameobject_name_to_fileid_and_children = ps.all_name_map
	metaobj.humanoid_skeleton_hip_position = ps.humanoid_skeleton_hip_position

	if not asset_database.in_package_import:
		asset_database.save()
	return p_scene


class HashGenerator:

	static func generate_object_hash(dupe_map: Dictionary, type: String, obj_path: String) -> int:
		var t: String = "Type:" + type + "->" + obj_path
		dupe_map[t] = dupe_map.get(t, -1) + 1
		t += str(dupe_map[t])
		var ret: int = xxHash64(t.to_utf8_buffer())
		return ret

	static func unsrs(n: int, shift: int) -> int:
		return ((n >> 1) & 0x7fffffffffffffff) >> (shift - 1)

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

		var b: PackedByteArray = buffer.slice(0)
		var len_buffer: int = len(buffer)
		b.resize((len_buffer + 7) & (~7))
		var b32: PackedInt32Array = b.to_int32_array()
		var b64: PackedInt64Array = b.to_int64_array()

		const PRIME64_1 = -7046029288634856825
		const PRIME64_2 = -4417276706812531889
		const PRIME64_3 = 1609587929392839161
		const PRIME64_4 = -8796714831421723037
		const PRIME64_5 = 2870177450012600261
		var acc: int = seed + PRIME64_5
		var offset: int = 0

		if len_buffer >= 32:
			var accN: PackedInt64Array = (
				PackedInt64Array(
					[
						seed + PRIME64_1 + PRIME64_2,
						seed + PRIME64_2,
						seed + 0,
						seed - PRIME64_1,
					]
				)
				. duplicate()
			)
			var limit: int = len_buffer - 32
			var lane: int = 0
			offset = 0
			while (offset & 0xffffffe0) <= limit:
				accN[lane] += b64[offset / 8] * PRIME64_2
				accN[lane] = ((accN[lane] << 31) | unsrs(accN[lane], 33)) * PRIME64_1
				offset += 8
				lane = (lane + 1) & 3
			acc = (((accN[0] << 1) | unsrs(accN[0], 63)) + ((accN[1] << 7) | unsrs(accN[1], 57)) + ((accN[2] << 12) | unsrs(accN[2], 52)) + ((accN[3] << 18) | unsrs(accN[3], 46)))
			for i in range(4):
				accN[i] = accN[i] * PRIME64_2
				accN[i] = ((accN[i] << 31) | unsrs(accN[i], 33)) * PRIME64_1
				acc = acc ^ accN[i]
				acc = acc * PRIME64_1 + PRIME64_4

		acc = acc + len_buffer
		var limit = len_buffer - 8
		while offset <= limit:
			var k1: int = b64[offset / 8] * PRIME64_2
			acc ^= ((k1 << 31) | unsrs(k1, 33)) * PRIME64_1
			acc = ((acc << 27) | unsrs(acc, 37)) * PRIME64_1 + PRIME64_4
			offset += 8

		limit = len_buffer - 4
		if offset <= limit:
			acc = acc ^ (b32[offset / 4] * PRIME64_1)
			acc = ((acc << 23) | unsrs(acc, 41)) * PRIME64_2 + PRIME64_3
			offset += 4

		while offset < len_buffer:
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

	static func test_xxHash64():
		assert(xxHash64("a".to_ascii_buffer()) == 3104179880475896308)
		assert(xxHash64("asdfghasdfghasdfghasdfghasdfghasdfghasdfghasdfghasdfghasdfghasdfghasdfgh".to_ascii_buffer()) == -3292477735350538661)
		assert(xxHash64(PackedByteArray().duplicate()) == -1205034819632174695)
