# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends Resource

const yaml_parser_class: GDScript = preload("./unity_object_parser.gd")
const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
const bin_parser_class: GDScript = preload("./deresuteme/decode.gd")


class DatabaseHolder:
	extends RefCounted
	var database: Resource = null


class LogMessageHolder:
	extends RefCounted
	var all_logs: PackedStringArray = PackedStringArray()
	var warnings_fails: PackedStringArray = PackedStringArray()
	var fails: PackedStringArray = PackedStringArray()

	func get_all_logs() -> String:
		return "\n".join(all_logs)

	func get_warnings_fails() -> String:
		return "\n".join(warnings_fails)

	func get_fail_logs() -> String:
		return "\n".join(fails)

	func has_warnings():
		return not warnings_fails.is_empty()

	func has_fails():
		return not fails.is_empty()


var object_adapter: RefCounted = object_adapter_class.new()
var database_holder
var log_database_holder
var log_message_holder = LogMessageHolder.new()
@export var path: String = ""
@export var guid: String = ""
@export var importer_keys: Dictionary = {}
@export var importer_type: String = ""
var importer  # unity_object_adapter.UnityAssetImporter subclass
# for .fbx, must use fileIDToRecycleName in meta.
@export var internal_data: Dictionary = {}

@export var prefab_id_to_guid: Dictionary = {}  # int -> String: object_adapter.create_godot_node

# we have a list of all prefabs by ID
#####@export var prefab_fileID_to_parented_fileID: Dictionary = {}
#####@export var prefab_fileID_to_parented_prefab: Dictionary = {}

var prefab_transform_fileid_to_rotation_delta: Dictionary = {} # int -> Transform
var prefab_transform_fileid_to_parent_fileid: Dictionary = {} # int -> int
var prefab_fileid_to_nodepath = {}
var prefab_fileid_to_skeleton_bone = {}  # int -> string
var prefab_fileid_to_utype = {}  # int -> int
var prefab_type_to_fileids = {}  # int -> int
var prefab_fileid_to_gameobject_fileid: Dictionary = {}  # int -> int
var fileid_to_component_fileids: Dictionary = {}  # int -> int
# TODO: remove @export
@export var prefab_gameobject_name_to_fileid_and_children: Dictionary = {}  # {null: 400000, "SomeName": {null: 1234, "SomeName2": ...}

###### @export var nodepath_to_fileid: Dictionary = {} # TO IMPLEMENT!!!!

@export var prefab_main_gameobject_id = 0
@export var prefab_main_transform_id = 0
@export var prefab_source_id_pair_to_stripped_id: Dictionary = {} # Vector2i -> int. if not here, we do XOR.
@export var transform_fileid_to_rotation_delta: Dictionary = {} # int -> Transform
@export var transform_fileid_to_parent_fileid: Dictionary = {} # int -> int
@export var fileid_to_nodepath: Dictionary = {}  # int -> NodePath: scene_node_state.add_fileID
@export var fileid_to_skeleton_bone: Dictionary = {}  # int -> string: scene_node_state.add_fileID_to_skeleton_bone
@export var fileid_to_utype: Dictionary = {}  # int -> int: parse_binary_asset/parse_asset
@export var fileid_to_gameobject_fileid: Dictionary = {}  # int -> int: parse_binary_asset/parse_asset
@export var type_to_fileids: Dictionary = {}  # string -> Array[int]: parse_binary_asset/parse_asset
@export var godot_resources: Dictionary = {}  # int -> Resource: insert_resource/override_resource
@export var main_object_id: int = 0  # e.g. 2100000 for .mat; 100000 for .fbx or GameObject; 100100000 for .prefab
@export var gameobject_name_to_fileid_and_children: Dictionary = {}  # {null: 400000, "SomeName": {null: 1234, "SomeName2": ...}
# @export var fileid_to_parent: Dictionary = {} # {400004: 400000, 400008: 400000, 400010: 123456778901234^100100000}
@export var transform_fileid_to_children: Dictionary = {}  # {400000: {"SomeName": {null: 1234, "SomeName2": ...}}}
@export var gameobject_fileid_to_components: Dictionary = {}  # {400000: {"SomeName": {null: 1234, "SomeName2": ...}}}
@export var transform_fileid_to_prefab_ids: Dictionary = {}  # {400000: PackedInt64Array(1, 2, 3)}
@export var gameobject_fileid_to_rename: Dictionary = {}  # {400000: "CoolObject"}

@export var dependency_guids: Dictionary = {}
@export var prefab_dependency_guids: Dictionary = {}
@export var meta_dependency_guids: Dictionary = {}
@export var autodetected_bone_map_dict: Dictionary = {}
@export var humanoid_bone_map_dict: Dictionary = {} # fbx bone name -> godot humanoid bone name
@export var humanoid_bone_map_crc32_dict: Dictionary = {} # CRC32(fbx bone name) -> godot humanoid bone name
@export var humanoid_skeleton_hip_position: Vector3 = Vector3(0.0, 1.0, 0.0)
@export var imported_animation_paths: Dictionary # anim_name -> file_path
@export var imported_mesh_paths: Dictionary # mesh_name (with and without "Root Scene_") -> file_path
@export var imported_material_paths: Dictionary # material_name -> file_path

class ParsedAsset:
	extends RefCounted
	var local_id_alias: Dictionary = {}  # type*100000 + file_index*2 -> real fileId
	var assets: Dictionary = {}  # int fileID -> unity_object_adapter.UnityObject


var parsed: ParsedAsset = null


class TopsortTmp:
	extends RefCounted
	var database: RefCounted = null
	var visited: Dictionary = {}.duplicate()
	var output: Array = [].duplicate()


func get_database() -> Resource:
	if database_holder == null or database_holder.database == null:
		pass  #push_error("Meta " + str(guid) + " at " l+ str(path) + " was not initialized!")
	return null if database_holder == null else database_holder.database


func get_database_int() -> Resource:
	return null if database_holder == null else database_holder.database


func set_log_database(log_database: Object):
	log_database_holder = DatabaseHolder.new()
	log_database_holder.database = log_database


func clear_logs():
	log_message_holder = LogMessageHolder.new()


# Log messages related to this asset
func log_debug(fileid: int, msg: String):
	var fileidstr = ""
	if fileid != 0:
		fileidstr = " @" + str(fileid)
	var seq_str: String = "%08d " % log_database_holder.database.global_log_count
	log_database_holder.database.global_log_count += 1
	var log_str: String = seq_str + msg + fileidstr
	log_message_holder.all_logs.append(log_str)
	log_database_holder.database.log_debug([null, fileid, self.guid, 0], msg)


# Anything that is unexpected but does not necessarily imply corruption.
# For example, successfully loaded a resource with default fileid
func log_warn(fileid: int, msg: String, field: String = "", remote_ref: Array = [null, 0, "", null]):
	var fieldstr: String = ""
	if not field.is_empty():
		fieldstr = "." + field + ": "
	var fileidstr: String = ""
	if remote_ref[1] != 0:
		var ref_guid_str = str(remote_ref[2])
		if log_database_holder.database.guid_to_path.has(ref_guid_str):
			ref_guid_str = log_database_holder.database.guid_to_path[ref_guid_str].get_file()
		fileidstr = " ref " + ref_guid_str + ":" + str(remote_ref[1])
	if fileid != 0:
		fileidstr += " @" + str(fileid)
	var seq_str: String = "%08d " % log_database_holder.database.global_log_count
	log_database_holder.database.global_log_count += 1
	var log_str: String = seq_str + fieldstr + msg + fileidstr
	log_message_holder.all_logs.append(log_str)
	log_message_holder.warnings_fails.append(log_str)
	var xref: Array = remote_ref
	if xref[1] != 0 and (typeof(xref[2]) == TYPE_NIL or xref[2].is_empty()):
		xref = [null, xref[1], self.guid, xref[3]]
	log_database_holder.database.log_warn([null, fileid, self.guid, 0], msg, field, xref)


# Anything that implies the asset will be corrupt / lost data.
# For example, some reference or field could not be assigned.
func log_fail(fileid: int, msg: String, field: String = "", remote_ref: Array = [null, 0, "", null]):
	var fieldstr = ""
	if not field.is_empty():
		fieldstr = "." + field + ": "
	var fileidstr = ""
	if len(remote_ref) >= 2 and remote_ref[1] != 0:
		var ref_guid_str = str(remote_ref[2])
		if log_database_holder.database.guid_to_path.has(ref_guid_str):
			ref_guid_str = log_database_holder.database.guid_to_path[ref_guid_str].get_file()
		fileidstr = " ref " + ref_guid_str + ":" + str(remote_ref[1])
	if fileid != 0:
		fileidstr += " @" + str(fileid)
	var seq_str: String = "%08d " % log_database_holder.database.global_log_count
	log_database_holder.database.global_log_count += 1
	var log_str: String = seq_str + fieldstr + msg + fileidstr
	log_message_holder.all_logs.append(log_str)
	log_message_holder.warnings_fails.append(log_str)
	log_message_holder.fails.append(log_str)
	var xref: Array = remote_ref
	if len(xref) > 2 and xref[1] != 0 and (typeof(xref[2]) == TYPE_NIL or xref[2].is_empty()):
		xref = [null, xref[1], self.guid, xref[3]]
	log_database_holder.database.log_fail([null, fileid, self.guid, 0], msg, field, xref)


func toposort_prefab_recurse(meta: Resource, tt: TopsortTmp):
	for target_guid in meta.prefab_dependency_guids:
		if not tt.visited.has(target_guid):
			tt.visited[target_guid] = true
			var child_meta: Resource = lookup_meta_by_guid_noinit(tt.database, target_guid)
			if child_meta == null:
				log_fail(0, "Unable to find dependency " + str(target_guid) + " of type " + str(meta.dependency_guids.get(target_guid, "")), "prefab", [null, -1, target_guid, -1])
			else:
				log_debug(0, "toposort inner guid " + str(child_meta.guid) + "/" + str(child_meta.path) + "/" + str(target_guid) + " " + str(child_meta.prefab_dependency_guids))
				child_meta.database_holder = database_holder
				child_meta.log_database_holder = database_holder
				toposort_prefab_recurse(child_meta, tt)
	tt.output.push_back(meta)


func toposort_prefab_dependency_guids() -> Array:
	var tt: TopsortTmp = TopsortTmp.new()
	tt.database = self.get_database()
	toposort_prefab_recurse(self, tt)
	return tt.output


func toposort_prefab_recurse_toplevel(database, guid_to_meta):
	var tt: TopsortTmp = TopsortTmp.new()
	tt.database = database
	for target_guid in guid_to_meta:
		if not tt.visited.has(target_guid):
			tt.visited[target_guid] = true
			var child_meta: Resource = guid_to_meta.get(target_guid)
			if child_meta == null:
				log_fail(0, "Unable to find dependency " + str(target_guid), "prefab", [null, -1, target_guid, -1])
			else:
				log_debug(0, "toposort toplevel guid " + str(target_guid) + "/" + str(child_meta.path) + " " + str(child_meta.prefab_dependency_guids))
				child_meta.toposort_prefab_recurse(child_meta, tt)
	return tt.output


func remap_prefab_gameobject_names_inner(prefab_id: int, target_prefab_meta: Resource, original_map: Dictionary, gameobject_id: int, new_map: Dictionary) -> int:
	var gameobject_renames: Dictionary = target_prefab_meta.gameobject_fileid_to_rename
	var transform_new_children: Dictionary = target_prefab_meta.transform_fileid_to_children
	var gameobject_new_components: Dictionary = target_prefab_meta.gameobject_fileid_to_components
	var gameobject_to_prefab_ids: Dictionary = target_prefab_meta.transform_fileid_to_prefab_ids
	var ret: Dictionary = {}.duplicate()
	var my_id: int = xor_or_stripped(gameobject_id, prefab_id)
	if new_map.has(my_id):
		#log_fail(prefab_id, "remap_prefab_gameobject_names_inner: Avoided infinite recursion: " + str(prefab_id) + "/" + str(gameobject_id))
		#return prefab_main_gameobject_id
		ret = new_map[my_id]
	#new_map[my_id] = {}
	var my_transform_id: int = xor_or_stripped(original_map[gameobject_id].get(4, 0), prefab_id)
	var this_map: Dictionary = original_map[gameobject_id]
	for name in this_map:
		var sub_id = this_map[name]
		var prefabbed_id = xor_or_stripped(sub_id, prefab_id)
		if typeof(name) != TYPE_STRING and typeof(name) != TYPE_STRING_NAME:
			# int: class_id; NodePath: script-type
			ret[name] = prefabbed_id
			continue
		var new_name = gameobject_renames.get(prefabbed_id, name)
		ret[new_name] = prefabbed_id
		#ret[new_name] = remap_prefab_gameobject_names_inner(prefab_id, original_map, sub_id, new_map)
	if prefab_id != 0:
		var component_map: Dictionary = gameobject_new_components.get(my_id, {})
		for comp in component_map:
			# TODO: Handle the case where the original component is Deleted and another one added
			if not ret.has(comp):
				ret[comp] = component_map[comp]
		var children_map: Dictionary = transform_new_children.get(my_id, {})
		for child in children_map:
			ret[child] = children_map[child]
	## This one applies to both prefabs and non-prefabs
	#for target_prefab_id in gameobject_to_prefab_ids.get(my_transform_id, PackedInt64Array()):
	#	var target_prefab_meta: Object = lookup_meta_by_guid(self.prefab_id_to_guid.get(target_prefab_id))
	#	var pgntfac = target_prefab_meta.prefab_gameobject_name_to_fileid_and_children
	#	var prefab_name = gameobject_renames[xor_or_stripped(target_prefab_meta.prefab_main_gameobject_id, target_prefab_id)]
	#	ret[prefab_name] = target_prefab_meta.remap_prefab_gameobject_names_inner(target_prefab_id ^ prefab_id, pgntfac, target_prefab_meta.prefab_main_gameobject_id, new_map)
	# Note: overwrites of name should respect m_RootOrder (we may need to store m_RootOrder here too)
	new_map[my_id] = ret
	return target_prefab_meta.prefab_main_gameobject_id


func remap_prefab_gameobject_names_update(prefab_id: int, target_prefab_meta: Resource, original_map: Dictionary, new_map: Dictionary):
	#log_debug(prefab_id, "Remap update " + str(prefab_id) + "/" + str(original_map) + " -> " + str(new_map))
	for key in original_map:
		if not new_map.has(key):
			#log_debug(prefab_id, "REMAP PREFAB %s %s %s" % [str(prefab_id), str(key), str(original_map)])
			remap_prefab_gameobject_names_inner(prefab_id, target_prefab_meta, original_map, key, new_map)
			#log_debug(prefab_id, "REMAP OUT %s" % [str(new_map)])
	#log_debug(prefab_id, "Remap update done " + str(prefab_id) + "/" + str(original_map) + " -> " + str(new_map))
	return new_map


func remap_prefab_gameobject_names(prefab_id: int, target_prefab_meta: Resource, original_map: Dictionary) -> Dictionary:
	var new_map: Dictionary = {}.duplicate()
	remap_prefab_gameobject_names_update(prefab_id, target_prefab_meta, original_map, new_map)
	return new_map


# Expected to be called in topological order
func calculate_prefab_nodepaths(database: Resource):
	#if not is_toplevel:
	for prefab_fileid in self.prefab_id_to_guid:
		var target_prefab_meta: Resource = lookup_meta_by_guid_noinit(database, self.prefab_id_to_guid.get(prefab_fileid))
		if target_prefab_meta == null:
			log_fail(
				0,
				"Failed to lookup prefab fileid " + str(prefab_fileid) + " guid " + str(self.prefab_id_to_guid.get(prefab_fileid)),
				"prefab",
			)
			continue
		if target_prefab_meta.get_database() == null:
			target_prefab_meta.initialize(self.get_database())
		self.remap_prefab_fileids(prefab_fileid, target_prefab_meta)

	if self.prefab_id_to_guid.is_empty():
		self.prefab_gameobject_name_to_fileid_and_children = {}
	else:
		self.prefab_gameobject_name_to_fileid_and_children = self.remap_prefab_gameobject_names(0, self, self.gameobject_name_to_fileid_and_children)


func remap_prefab_fileids(prefab_fileid: int, target_prefab_meta: Resource):
	# xor is the actual operation used for a prefabbed fileid in a prefab instance.
	var my_path_prefix: String = str(fileid_to_nodepath.get(prefab_fileid)) + "/"
	for target_fileid in target_prefab_meta.fileid_to_nodepath:
		self.prefab_fileid_to_nodepath[xor_or_stripped(target_fileid, prefab_fileid)] = NodePath(my_path_prefix + str(target_prefab_meta.fileid_to_nodepath.get(target_fileid)))
	for target_fileid in target_prefab_meta.prefab_fileid_to_nodepath:
		self.prefab_fileid_to_nodepath[xor_or_stripped(target_fileid, prefab_fileid)] = NodePath(my_path_prefix + str(target_prefab_meta.prefab_fileid_to_nodepath.get(target_fileid)))
	for target_fileid in target_prefab_meta.fileid_to_skeleton_bone:
		self.prefab_fileid_to_skeleton_bone[xor_or_stripped(target_fileid, prefab_fileid)] = (target_prefab_meta.fileid_to_skeleton_bone.get(target_fileid))
	for target_fileid in target_prefab_meta.prefab_fileid_to_skeleton_bone:
		self.prefab_fileid_to_skeleton_bone[xor_or_stripped(target_fileid, prefab_fileid)] = (target_prefab_meta.prefab_fileid_to_skeleton_bone.get(target_fileid))
	for target_fileid in target_prefab_meta.fileid_to_utype:
		self.prefab_fileid_to_utype[xor_or_stripped(target_fileid, prefab_fileid)] = target_prefab_meta.fileid_to_utype.get(target_fileid)
	for target_fileid in target_prefab_meta.prefab_fileid_to_utype:
		self.prefab_fileid_to_utype[xor_or_stripped(target_fileid, prefab_fileid)] = (target_prefab_meta.prefab_fileid_to_utype.get(target_fileid))
	for target_fileid in target_prefab_meta.transform_fileid_to_rotation_delta:
		self.prefab_transform_fileid_to_rotation_delta[xor_or_stripped(target_fileid, prefab_fileid)] = (target_prefab_meta.transform_fileid_to_rotation_delta.get(target_fileid))
	for target_fileid in target_prefab_meta.prefab_transform_fileid_to_rotation_delta:
		self.prefab_transform_fileid_to_rotation_delta[xor_or_stripped(target_fileid, prefab_fileid)] = (target_prefab_meta.prefab_transform_fileid_to_rotation_delta.get(target_fileid))
	for target_fileid in target_prefab_meta.transform_fileid_to_parent_fileid:
		self.prefab_transform_fileid_to_parent_fileid[xor_or_stripped(target_fileid, prefab_fileid)] = xor_or_stripped(target_prefab_meta.transform_fileid_to_parent_fileid.get(target_fileid), prefab_fileid)
	for target_fileid in target_prefab_meta.prefab_transform_fileid_to_parent_fileid:
		self.prefab_transform_fileid_to_parent_fileid[xor_or_stripped(target_fileid, prefab_fileid)] = xor_or_stripped(target_prefab_meta.prefab_transform_fileid_to_parent_fileid.get(target_fileid), prefab_fileid)
	for target_type in target_prefab_meta.type_to_fileids:
		if not self.prefab_type_to_fileids.has(target_type):
			self.prefab_type_to_fileids[target_type] = PackedInt64Array()
		for target_fileid in target_prefab_meta.type_to_fileids.get(target_type):
			self.prefab_type_to_fileids[target_type].push_back(xor_or_stripped(target_fileid, prefab_fileid))
	for target_type in target_prefab_meta.prefab_type_to_fileids:
		if not self.prefab_type_to_fileids.has(target_type):
			self.prefab_type_to_fileids[target_type] = PackedInt64Array()
		for target_fileid in target_prefab_meta.prefab_type_to_fileids.get(target_type):
			self.prefab_type_to_fileids[target_type].push_back(xor_or_stripped(target_fileid, prefab_fileid))
	for target_fileid in target_prefab_meta.fileid_to_gameobject_fileid:
		self.prefab_fileid_to_gameobject_fileid[xor_or_stripped(target_fileid, prefab_fileid)] = xor_or_stripped(target_prefab_meta.fileid_to_gameobject_fileid.get(target_fileid), prefab_fileid)
	for target_fileid in target_prefab_meta.prefab_fileid_to_gameobject_fileid:
		self.prefab_fileid_to_gameobject_fileid[xor_or_stripped(target_fileid, prefab_fileid)] = xor_or_stripped(target_prefab_meta.prefab_fileid_to_gameobject_fileid.get(target_fileid), prefab_fileid)


func calculate_prefab_nodepaths_recursive():
	var toposorted: Array = toposort_prefab_dependency_guids()
	var database: Resource = get_database()
	for process_meta in toposorted:
		if process_meta != null and process_meta.guid != guid and (process_meta.main_object_id == 100100000 or process_meta.importer_type == "PrefabImporter"):
			process_meta.calculate_prefab_nodepaths(database)

	#var gameobject_fileid_to_components: Dictionary = {}.duplicate()
	for fileid in fileid_to_gameobject_fileid:
		var gofd: int = fileid_to_gameobject_fileid.get(fileid)
		if not fileid_to_component_fileids.has(gofd):
			fileid_to_component_fileids[gofd] = PackedInt64Array()
		fileid_to_component_fileids[gofd].push_back(fileid)
	for go_fileid in fileid_to_component_fileids.keys():
		for fileid in fileid_to_component_fileids.get(go_fileid):
			fileid_to_component_fileids[fileid] = fileid_to_component_fileids.get(go_fileid)


func xor_or_stripped(fileID: int, prefab_fileID: int) -> int:
	#if fileID == -12901736176340512 or prefab_fileID == 1386572426:
	#	var s: String
	#	for ke in prefab_source_id_pair_to_stripped_id:
	#		s += ",(" + str((ke.x << 32) | ke.y) + "," + str((ke.z << 32) | ke.w) + "): " + str(prefab_source_id_pair_to_stripped_id[ke])
	#	log_debug(prefab_fileID, s)
	return prefab_source_id_pair_to_stripped_id.get(Vector4i(prefab_fileID >> 32, prefab_fileID & 0xffffffff, fileID >> 32, fileID & 0xffffffff), prefab_fileID ^ fileID)


# This overrides a built-in resource, storing the resource inside the database itself.
func override_resource(fileID: int, name: String, godot_resource: Resource):
	godot_resource.resource_name = name
	godot_resources[fileID] = godot_resource


# This inserts a reference to an actual resource file on disk.
# We cannot store an external resource reference because
# Godot will fail to load the entire database if a single file is missing.
func insert_resource(fileID: int, godot_resource: Resource):
	godot_resources[fileID] = str(godot_resource.resource_path)


# Another version, passing in the path directly.
func insert_resource_path(fileID: int, godot_resource_path: String):
	godot_resources[fileID] = str(godot_resource_path)


# Rename is commented out only because it is not currently used,
# it can cause races with multithreading.
#func rename(new_path: String):
#	get_database().rename_meta(self, new_path)


func get_main_object_name():
	return path.get_file().get_basename().get_basename()  # .prefab.tscn


# Some properties cannot be serialized.
func initialize(database: Resource):
	self.database_holder = DatabaseHolder.new()
	self.database_holder.database = database
	self.log_database_holder = self.database_holder
	self.prefab_fileid_to_nodepath = {}
	self.prefab_fileid_to_skeleton_bone = {}
	self.prefab_fileid_to_utype = {}
	self.prefab_type_to_fileids = {}
	if self.importer_type == "":
		self.importer = object_adapter.instantiate_unity_object(self, 0, 0, "AssetImporter")
	else:
		self.importer = object_adapter.instantiate_unity_object(self, 0, 0, self.importer_type)
	self.importer.keys = importer_keys


static func lookup_meta_by_guid_noinit(database: Resource, target_guid: String) -> RefCounted:  # returns asset_meta type
	var found_path: String = database.guid_to_path.get(target_guid, "")
	var found_meta: Resource = null
	if not found_path.is_empty():
		found_meta = database.path_to_meta.get(found_path, null)
	return found_meta


func lookup_meta_by_guid(target_guid: String) -> Resource:  # returns asset_meta type
	var found_meta: Resource = lookup_meta_by_guid_noinit(get_database(), target_guid)
	if found_meta == null:
		return null
	if found_meta.get_database() == null:
		found_meta.initialize(self.get_database())
	return found_meta


func lookup_meta(unityref: Array) -> Resource:  # returns asset_meta type
	if unityref.is_empty() or len(unityref) != 4:
		log_fail(0, "UnityRef in wrong format: " + str(unityref), "ref", unityref)
		return null
	# log_debug(0, "LOOKING UP: " + str(unityref) + " FROM " + guid + "/" + path)
	var local_id: int = unityref[1]
	if local_id == 0:
		return null
	var found_meta: Resource = self
	if typeof(unityref[2]) != TYPE_NIL and unityref[2] != self.guid:
		var target_guid: String = unityref[2]
		found_meta = lookup_meta_by_guid(target_guid)
	return found_meta


func lookup(unityref: Array, silent: bool = false) -> RefCounted:
	var found_meta: Resource = lookup_meta(unityref)
	if found_meta == null:
		return null
	var local_id: int = unityref[1]
	# Not implemented:
	#var local_id: int = found_meta.local_id_alias.get(unityref.fileID, unityref.fileID)
	if found_meta.parsed == null:
		if not silent:
			log_fail(0, "Target ref " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + " was not yet parsed! from " + path + " (" + guid + ")", "ref", unityref)
		return null
	var ret: RefCounted = found_meta.parsed.assets.get(local_id)
	if ret == null:
		if not silent:
			log_fail(0, "Target ref " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + " is null! from " + path + " (" + guid + ")", "ref", unityref)
		return null
	ret.meta = found_meta
	return ret


func lookup_or_instantiate(unityref: Array, type: String) -> RefCounted:
	var found_object: RefCounted = lookup(unityref, true)
	if found_object != null:
		#if found_object.type != type: # Too hard to verify because it could be a subclass.
		#	log_warn(0, "lookup_or_instantiate " + str(found_object.uniq_key) + " not type " + str(type), "ref", unityref)
		return found_object
	var found_meta: Resource = lookup_meta(unityref)
	if found_meta == null:
		return null
	return object_adapter.instantiate_unity_object(found_meta, unityref[1], 0, type)


func set_owner_rec(node: Node, owner: Node):
	node.owner = owner
	for n in node.get_children():
		set_owner_rec(n, owner)


func get_godot_node(unityref: Array) -> Node:
	var found_meta: Resource = lookup_meta(unityref)
	if found_meta == null:
		return null
	var ps: Resource = load("res://" + found_meta.path)
	if ps == null:
		return null
	if ps is PackedScene:
		var root_node: Node = ps.instantiate()
		var node: Node = root_node
		var local_id: int = unityref[1]
		if local_id == 100100000:
			log_warn(0, "Looking up prefab " + str(unityref) + " in loaded scene " + ps.resource_name, "ref", unityref)
			return node
		var np: NodePath = found_meta.fileid_to_nodepath.get(local_id, found_meta.prefab_fileid_to_nodepath.get(local_id, NodePath()))
		if np == NodePath():
			log_fail(0, "Could not find node " + str(unityref) + " in loaded scene " + ps.resource_name, "ref", unityref)
			return null
		node = node.get_node(np)
		if node == null:
			log_fail(0, "Path " + str(np) + " was missing in " + str(unityref) + " in loaded scene " + ps.resource_name, "ref", unityref)
			return null
		if node is Skeleton3D:
			var bone_to_reroot: String = found_meta.fileid_to_skeleton_bone.get(local_id, found_meta.prefab_fileid_to_skeleton_bone.get(local_id, ""))
			var bone_to_keep: int = node.find_bone(bone_to_reroot)
			var keep: Array = []
			for b in range(node.get_bone_count()):
				var parb: int = b
				while parb != -1:
					if parb == bone_to_keep:
						var parname: String = "" if b == bone_to_keep else node.get_bone_name(node.get_bone_parent(b))
						keep.append([node.get_bone_name(b), parname, node.get_bone_pose_position(b), node.get_bone_pose_rotation(b), node.get_bone_pose_scale(b), node.get_bone_rest(b)])
						break
					parb = node.get_bone_parent(parb)
			var cache: Dictionary = {}
			node.clear_bones()
			for bonedata in keep:
				var b = node.get_bone_count()
				cache[bonedata[0]] = b
				node.add_bone(bonedata[0])
				node.set_bone_pose_position(b, bonedata[2])
				node.set_bone_pose_rotation(b, bonedata[3])
				node.set_bone_pose_scale(b, bonedata[4])
				node.set_bone_rest(b, bonedata[5])
			for bonedata in keep:
				if cache[bonedata[0]] != bone_to_keep:
					node.set_bone_parent(cache[bonedata[0]], cache[bonedata[1]])
			for child in node.get_children():
				if child is BoneAttachment3D:
					if not cache.has(child.bone_name):
						child.queue_free()
				else:
					child.queue_free()  # sub-skeleton = no skinned meshes should exist since they will reference deleted bones.
		if node == root_node:
			return node
		node.owner = null
		for child in node.get_children():
			set_owner_rec(child, node)
		node.get_parent().remove_child(node)
		root_node.queue_free()
		return node
	return null


func get_godot_resource(unityref: Array, silent: bool = false) -> Resource:
	var found_meta: Resource = lookup_meta(unityref)
	if found_meta == null:
		if len(unityref) == 4 and unityref[1] != 0:
			var found_path: String = get_database().guid_to_path.get(unityref[2], "")
			if not silent:
				log_warn(0, "Resource with no meta. Try blindly loading it: " + str(unityref) + "/" + found_path, "ref", unityref)
			return load("res://" + found_path)
		return null
	var local_id: int = unityref[1]
	# log_debug(0, "guid:" + str(found_meta.guid) +" path:" + str(found_meta.path) + " main_obj:" + str(found_meta.main_object_id) + " local_id:" + str(local_id))
	if found_meta.fileid_to_nodepath.has(local_id) or found_meta.prefab_fileid_to_nodepath.has(local_id):
		local_id = found_meta.main_object_id
	if found_meta.main_object_id != 0 and found_meta.main_object_id == local_id:
		return load("res://" + found_meta.path)
	if found_meta.godot_resources.has(local_id):
		var ret: Variant = found_meta.godot_resources.get(local_id, null)
		if typeof(ret) != TYPE_OBJECT and typeof(ret) != TYPE_NIL:
			return load(ret)
		else:
			return ret
	if found_meta.parsed == null:
		if not silent:
			log_fail(0, "Failed to find Resource at " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + "! from " + path + " (" + guid + ")", "ref", unityref)
		return null
	if not silent:
		log_fail(0, "Target ref " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + " would need to dynamically create a godot resource! from " + path + " (" + guid + ")", "ref", unityref)
	#var res: Resource = found_meta.parsed.assets[local_id].create_godot_resource()
	#found_meta.godot_resources[local_id] = res
	#return res
	return null


func get_gameobject_fileid(fileid: int) -> int:
	if prefab_fileid_to_gameobject_fileid.has(fileid):
		return prefab_fileid_to_gameobject_fileid.get(fileid)
	if fileid_to_gameobject_fileid.has(fileid):
		return fileid_to_gameobject_fileid.get(fileid)
	if fileid_to_utype.get(fileid, 0) == 1:
		return fileid
	if prefab_fileid_to_utype.get(fileid, 0) == 1:
		return fileid
	return 0


func find_fileids_of_type(type: String) -> PackedInt64Array:
	var fileids: PackedInt64Array = PackedInt64Array()
	fileids.append_array(type_to_fileids.get(type, PackedInt64Array()))
	fileids.append_array(prefab_type_to_fileids.get(type, PackedInt64Array()))
	return fileids


func get_component_fileid(fileid: int, type: String) -> int:
	var component_fileids: PackedInt64Array = fileid_to_component_fileids.get(fileid, PackedInt64Array())
	var utype: int = object_adapter.to_utype(type)
	for comp_fileid in component_fileids:
		if fileid_to_utype.get(comp_fileid, -1) == utype:
			return comp_fileid
		elif prefab_fileid_to_utype.get(comp_fileid, -1) == utype:
			return comp_fileid
	return 0


func get_components_fileids(fileid: int, type: String = "") -> PackedInt64Array:
	var component_fileids: PackedInt64Array = fileid_to_component_fileids.get(fileid, PackedInt64Array())
	if type.is_empty():
		return component_fileids
	var utype: int = object_adapter.to_utype(type)
	var out_fileids: PackedInt64Array = PackedInt64Array()
	for comp_fileid in component_fileids:
		if fileid_to_utype.get(comp_fileid, -1) == utype:
			out_fileids.push_back(comp_fileid)
		elif prefab_fileid_to_utype.get(comp_fileid, -1) == utype:
			out_fileids.push_back(comp_fileid)
	return out_fileids


const BLACKLISTED_OBJECT_TYPES: Dictionary = {
	"AnimatorStateTransition": 1,
	"AnimatorState": 1,
	"AnimatorTransition": 1,
	"AnimatorStateMachine": 1,
	"BlendTree": 1,
}


func parse_binary_asset(bytearray: PackedByteArray) -> ParsedAsset:
	var parsed = ParsedAsset.new()
	log_debug(0, "Parsing " + str(guid))
	var bin_parser = bin_parser_class.new(self, bytearray)
	log_debug(0, "Parsed " + str(guid) + ":" + str(bin_parser) + " found " + str(len(bin_parser.objs)) + " objects and " + str(len(bin_parser.defs)) + " defs")
	var next_basic_id: Dictionary = {}.duplicate()
	if self.main_object_id == 0:
		for output_obj in bin_parser.objs:
			if output_obj.fileID == 15600000:
				# TerrainData may be special cased...
				self.main_object_id = output_obj.fileID
	if self.main_object_id == 0:
		for output_obj in bin_parser.objs:
			if BLACKLISTED_OBJECT_TYPES.has(output_obj.type) or (output_obj.keys.get("m_ObjectHideFlags", 0) & 1) != 0:
				continue
			if (output_obj.fileID % 100000 == 0 or output_obj.fileID < 1000000) and output_obj.fileID > 0:
				log_warn(output_obj.fileID, "We have no main_object_id but found a nice round number " + str(output_obj.fileID))
				self.main_object_id = output_obj.fileID
	var i = 0
	for output_obj in bin_parser.objs:
		i += 1
		if self.main_object_id == 0:
			if (output_obj.keys.get("m_ObjectHideFlags", 0) & 1) == 0:
				log_warn(output_obj.fileID, "We have no main_object_id but it should be " + str(output_obj.fileID))
				self.main_object_id = output_obj.fileID
		parsed.assets[output_obj.fileID] = output_obj
		fileid_to_utype[output_obj.fileID] = output_obj.utype
		if not type_to_fileids.has(output_obj.type):
			type_to_fileids[output_obj.type] = PackedInt64Array().duplicate()
		type_to_fileids[output_obj.type].push_back(output_obj.fileID)
		if output_obj.is_stripped:
			prefab_source_id_pair_to_stripped_id[Vector4i(output_obj.prefab_instance[1] >> 32, output_obj.prefab_instance[1] & 0xffffffff, output_obj.prefab_source_object[1] >> 32, output_obj.prefab_source_object[1] & 0xffffffff)] = output_obj.fileID
		if not output_obj.is_stripped and output_obj.keys.get("m_GameObject", [null, 0, null, null])[1] != 0:
			fileid_to_gameobject_fileid[output_obj.fileID] = output_obj.keys.get("m_GameObject")[1]
		if not output_obj.is_stripped and output_obj.keys.get("m_Father", [null, 0, null, null])[1] != 0:
			transform_fileid_to_parent_fileid[output_obj.fileID] = output_obj.keys.get("m_Father")[1]
		if output_obj.type == "Prefab" or output_obj.type == "PrefabInstance":
			transform_fileid_to_parent_fileid[output_obj.fileID] = output_obj.parent_ref[1]
		var new_basic_id: int = next_basic_id.get(output_obj.utype, output_obj.utype * 100000)
		next_basic_id[output_obj.utype] = new_basic_id + 1
		parsed.local_id_alias[new_basic_id] = output_obj.fileID

	self.parsed = parsed
	log_debug(0, "Done parsing!")
	return parsed


func parse_asset(file: Object) -> ParsedAsset:
	var magic = file.get_line()
	log_debug(0, "Parsing " + self.guid + " : " + file.get_path())
	if not magic.begins_with("%YAML"):
		return null

	log_debug(0, "Path " + self.path + ": " + str(self.main_object_id))
	var parsed = ParsedAsset.new()

	var yaml_parser = yaml_parser_class.new()
	yaml_parser.debug_guid = guid
	yaml_parser.debug_path = path
	var i = 0

	# var recycle_ids: Dictionary = {}
	#if self.importer != null:
	#	recycle_ids = self.importer.keys.get("fileIDToRecycleName", {})
	var next_basic_id: Dictionary = {}.duplicate()
	while true:
		i += 1
		var lin = file.get_line()
		var output_obj = yaml_parser.parse_line(lin, self, false, object_adapter.instantiate_unity_object)
		if output_obj != null:
			if not BLACKLISTED_OBJECT_TYPES.has(output_obj.type) and self.main_object_id == 0 and output_obj.fileID > 0 and (output_obj.keys.get("m_ObjectHideFlags", 0) & 1) == 0 and (output_obj.fileID % 100000 == 0 or output_obj.fileID < 1000000):
				log_warn(output_obj.fileID, "We have no main_object_id but found a nice round number " + str(output_obj.fileID))
				self.main_object_id = output_obj.fileID
			parsed.assets[output_obj.fileID] = output_obj
			fileid_to_utype[output_obj.fileID] = output_obj.utype
			if not type_to_fileids.has(output_obj.type):
				type_to_fileids[output_obj.type] = PackedInt64Array().duplicate()
			type_to_fileids[output_obj.type].push_back(output_obj.fileID)
			if output_obj.is_stripped:
				prefab_source_id_pair_to_stripped_id[Vector4i(output_obj.prefab_instance[1] >> 32, output_obj.prefab_instance[1] & 0xffffffff, output_obj.prefab_source_object[1] >> 32, output_obj.prefab_source_object[1] & 0xffffffff)] = output_obj.fileID
			if not output_obj.is_stripped and output_obj.keys.get("m_GameObject", [null, 0, null, null])[1] != 0:
				fileid_to_gameobject_fileid[output_obj.fileID] = output_obj.keys.get("m_GameObject")[1]
			if not output_obj.is_stripped and output_obj.keys.get("m_Father", [null, 0, null, null])[1] != 0:
				transform_fileid_to_parent_fileid[output_obj.fileID] = output_obj.keys.get("m_Father")[1]
			if output_obj.type == "Prefab" or output_obj.type == "PrefabInstance":
				transform_fileid_to_parent_fileid[output_obj.fileID] = output_obj.parent_ref[1]
			var new_basic_id: int = next_basic_id.get(output_obj.utype, output_obj.utype * 100000)
			next_basic_id[output_obj.utype] = new_basic_id + 1
			parsed.local_id_alias[new_basic_id] = output_obj.fileID
		if file.get_error() == ERR_FILE_EOF:
			break
	self.parsed = parsed
	if self.main_object_id == 0:
		for fileID in parsed.assets:
			if (parsed.assets[fileID].keys.get("m_ObjectHideFlags", 0) & 1) == 0:
				log_warn(fileID, "We have no main_object_id but it should be " + str(fileID))
				self.main_object_id = fileID

	return parsed


func _init():
	pass


func init_with_file(file: Object, path: String):
	self.path = path
	self.resource_name = path
	type_to_fileids = {}.duplicate()  # push_back is not idempotent. must clear to avoid duplicates.
	if file == null:
		return  # Dummy meta object

	var magic = file.get_line()
	log_debug(0, "Parsing meta file! " + file.get_path())
	if not magic.begins_with("fileFormatVersion:"):
		return

	var yaml_parser = yaml_parser_class.new()
	var i = 0
	while true:
		i += 1
		var lin = file.get_line()
		var output_obj: RefCounted = yaml_parser.parse_line(lin, self, true, object_adapter.instantiate_unity_object)
		# unity_object_adapter.UnityObject
		if output_obj != null:
			log_debug(output_obj.fileID, "Finished parsing output_obj: " + str(output_obj) + "/" + str(output_obj.type))
			self.importer_keys = output_obj.keys
			self.importer_type = output_obj.type
			self.importer = output_obj
			self.main_object_id = self.importer.get_main_object_id()
			log_debug(output_obj.fileID, "Main object id for " + path + ": " + str(self.main_object_id))
		if file.get_error() == ERR_FILE_EOF:
			break
	assert(not self.guid.is_empty())
