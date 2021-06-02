@tool
extends Resource

const yaml_parser_class: GDScript = preload("./unity_object_parser.gd")
const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
const bin_parser_class: GDScript = preload("./deresuteme/decode.gd")

class DatabaseHolder extends Reference:
	var database: Resource = null

var object_adapter: Reference = object_adapter_class.new()
var database_holder
@export var path: String = ""
@export var guid: String = ""
@export var importer_keys: Dictionary = {}
@export var importer_type: String = ""
var importer # unity_object_adapter.UnityAssetImporter subclass
# for .fbx, must use fileIDToRecycleName in meta.
@export var internal_data: Dictionary = {}

@export var prefab_id_to_guid: Dictionary = {}

# we have a list of all prefabs by ID
#####@export var prefab_fileID_to_parented_fileID: Dictionary = {}
#####@export var prefab_fileID_to_parented_prefab: Dictionary = {}

var prefab_fileid_to_nodepath = {}
var prefab_fileid_to_skeleton_bone = {} # int -> string
var prefab_fileid_to_utype = {} # int -> int
var prefab_type_to_fileids = {} # int -> int
var prefab_fileid_to_gameobject_fileid: Dictionary = {} # int -> int
var fileid_to_component_fileids: Dictionary = {} # int -> int

###### @export var nodepath_to_fileid: Dictionary = {} # TO IMPLEMENT!!!!


@export var fileid_to_nodepath: Dictionary = {}
@export var fileid_to_skeleton_bone: Dictionary = {} # int -> string
@export var fileid_to_utype: Dictionary = {} # int -> int
@export var fileid_to_gameobject_fileid: Dictionary = {} # int -> int
@export var type_to_fileids: Dictionary = {} # string -> Array[int]
@export var godot_resources: Dictionary = {}
@export var main_object_id: int = 0 # e.g. 2100000 for .mat; 100000 for .fbx or GameObject; 100100000 for .prefab

@export var dependency_guids: Dictionary = {}
@export var prefab_dependency_guids: Dictionary = {}

class ParsedAsset extends Reference:
	var local_id_alias: Dictionary = {} # type*100000 + file_index*2 -> real fileId
	var assets: Dictionary = {} # int fileID -> unity_object_adapter.UnityObject

var parsed: ParsedAsset = null

class TopsortTmp extends Reference:
	var database: Reference = null
	var visited: Dictionary = {}.duplicate()
	var output: Array = [].duplicate()

func get_database() -> Resource:
	if database_holder == null or database_holder.database == null:
		pass#push_error("Meta " + str(guid) + " at " l+ str(path) + " was not initialized!")
	return null if database_holder == null else database_holder.database

func get_database_int() -> Resource:
	return null if database_holder == null else database_holder.database

func toposort_prefab_recurse(meta: Resource, tt: TopsortTmp):
	for target_guid in meta.prefab_dependency_guids:
		if not tt.visited.has(target_guid):
			tt.visited[target_guid] = true
			var child_meta: Resource = lookup_meta_by_guid_noinit(tt.database, target_guid)
			if child_meta == null:
				push_error("Unable to find dependency " + str(target_guid) + " of type " + str(meta.dependency_guids.get(target_guid, "")))
			else:
				child_meta.database_holder = database_holder
				toposort_prefab_recurse(child_meta, tt)
	tt.output.push_back(meta)

func toposort_prefab_dependency_guids() -> Array:
	var tt: TopsortTmp = TopsortTmp.new()
	tt.database = self.get_database()
	toposort_prefab_recurse(self, tt)
	return tt.output

static func toposort_prefab_recurse_toplevel(database, guid_to_meta):
	var tt: TopsortTmp = TopsortTmp.new()
	tt.database = database
	for target_guid in guid_to_meta:
		if not tt.visited.has(target_guid):
			tt.visited[target_guid] = true
			var child_meta: Resource = guid_to_meta.get(target_guid)
			if child_meta == null:
				push_error("Unable to find dependency " + str(target_guid))
			else:
				child_meta.toposort_prefab_recurse(child_meta, tt)
	return tt.output

# Expected to be called in topological order
func calculate_prefab_nodepaths(database: Resource):
	#if not is_toplevel:
	for prefab_fileid in self.prefab_id_to_guid:
		var target_prefab_meta: Resource = lookup_meta_by_guid_noinit(database, self.prefab_id_to_guid.get(prefab_fileid))
		if target_prefab_meta == null:
			push_error("Failed to lookup prefab fileid " + str(prefab_fileid) + " guid " + str(self.prefab_id_to_guid.get(prefab_fileid)))
			continue
		if target_prefab_meta.get_database() == null:
			target_prefab_meta.initialize(self.get_database())
		var my_path_prefix: String = str(fileid_to_nodepath.get(prefab_fileid)) + "/"
		for target_fileid in target_prefab_meta.fileid_to_nodepath:
			self.prefab_fileid_to_nodepath[int(target_fileid) ^ int(prefab_fileid)] = NodePath(my_path_prefix + str(target_prefab_meta.fileid_to_nodepath.get(target_fileid)))
		for target_fileid in target_prefab_meta.prefab_fileid_to_nodepath:
			self.prefab_fileid_to_nodepath[int(target_fileid) ^ int(prefab_fileid)] = NodePath(my_path_prefix + str(target_prefab_meta.prefab_fileid_to_nodepath.get(target_fileid)))
		for target_fileid in target_prefab_meta.fileid_to_skeleton_bone:
			self.prefab_fileid_to_nodepath[int(target_fileid) ^ int(prefab_fileid)] = target_prefab_meta.fileid_to_skeleton_bone.get(target_fileid)
		for target_fileid in target_prefab_meta.prefab_fileid_to_skeleton_bone:
			self.prefab_fileid_to_skeleton_bone[int(target_fileid) ^ int(prefab_fileid)] = target_prefab_meta.prefab_fileid_to_skeleton_bone.get(target_fileid)
		for target_fileid in target_prefab_meta.fileid_to_utype:
			self.prefab_fileid_to_utype[int(target_fileid) ^ int(prefab_fileid)] = target_prefab_meta.fileid_to_utype.get(target_fileid)
		for target_fileid in target_prefab_meta.prefab_fileid_to_utype:
			self.prefab_fileid_to_utype[int(target_fileid) ^ int(prefab_fileid)] = target_prefab_meta.prefab_fileid_to_utype.get(target_fileid)
		for target_type in target_prefab_meta.type_to_fileids:
			if not self.prefab_type_to_fileids.has(target_type):
				self.prefab_type_to_fileids[target_type] = PackedInt64Array()
			for target_fileid in target_prefab_meta.type_to_fileids.get(target_type):
				self.prefab_type_to_fileids[target_type].push_back(int(target_fileid) ^ int(prefab_fileid))
		for target_type in target_prefab_meta.prefab_type_to_fileids:
			if not self.prefab_type_to_fileids.has(target_type):
				self.prefab_type_to_fileids[target_type] = PackedInt64Array()
			for target_fileid in target_prefab_meta.prefab_type_to_fileids.get(target_type):
				self.prefab_type_to_fileids[target_type].push_back(int(target_fileid) ^ int(prefab_fileid))
		for target_fileid in target_prefab_meta.fileid_to_gameobject_fileid:
			self.prefab_fileid_to_gameobject_fileid[int(target_fileid) ^ int(prefab_fileid)] = target_prefab_meta.fileid_to_gameobject_fileid.get(target_fileid) ^ int(prefab_fileid)
		for target_fileid in target_prefab_meta.prefab_fileid_to_gameobject_fileid:
			self.prefab_fileid_to_gameobject_fileid[int(target_fileid) ^ int(prefab_fileid)] = target_prefab_meta.prefab_fileid_to_gameobject_fileid.get(target_fileid) ^ int(prefab_fileid)


func calculate_prefab_nodepaths_recursive():
	var toposorted: Variant = toposort_prefab_dependency_guids()
	if typeof(toposorted) != TYPE_ARRAY:
		push_error("BLEH BLEH")
		return
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

# This overrides a built-in resource, storing the resource inside the database itself.
func override_resource(fileID: int, name: String, godot_resource: Resource):
	godot_resource.resource_name = name
	godot_resources[fileID] = godot_resource

# This inserts a reference to an actual resource file on disk.
# We cannot store an external resource reference because
# Godot will fail to load the entire database if a single file is missing.
func insert_resource(fileID: int, godot_resource: Resource):
	godot_resources[fileID] = str(godot_resource.resource_path)

func rename(new_path: String):
	get_database().rename_meta(self, new_path)

# Some properties cannot be serialized.
func initialize(database: Resource):
	self.database_holder = DatabaseHolder.new()
	self.database_holder.database = database
	self.prefab_fileid_to_nodepath = {}
	self.prefab_fileid_to_skeleton_bone = {}
	self.prefab_fileid_to_utype = {}
	self.prefab_type_to_fileids = {}
	if self.importer_type == "":
		self.importer = object_adapter.instantiate_unity_object(self, 0, 0, "AssetImporter")
	else:
		self.importer = object_adapter.instantiate_unity_object(self, 0, 0, self.importer_type)
	self.importer.keys = importer_keys

static func lookup_meta_by_guid_noinit(database: Resource, target_guid: String) -> Reference: # returns asset_meta type
	var found_path: String = database.guid_to_path.get(target_guid, "")
	var found_meta: Resource = null
	if found_path != "":
		found_meta = database.path_to_meta.get(found_path, null)
	return found_meta

func lookup_meta_by_guid(target_guid: String) -> Reference: # returns asset_meta type
	var found_meta: Resource = lookup_meta_by_guid_noinit(get_database(), target_guid)
	if found_meta == null:
		return null
	if found_meta.get_database() == null:
		found_meta.initialize(self.get_database())
	return found_meta

func lookup_meta(unityref: Array) -> Reference: # returns asset_meta type
	if unityref.is_empty() or len(unityref) != 4:
		push_error("UnityRef in wrong format: " + str(unityref))
		return null
	# print("LOOKING UP: " + str(unityref) + " FROM " + guid + "/" + path)
	var local_id: int = unityref[1]
	if local_id == 0:
		return null
	var found_meta: Resource = self
	if typeof(unityref[2]) != TYPE_NIL and unityref[2] != self.guid:
		var target_guid: String = unityref[2]
		found_meta = lookup_meta_by_guid(target_guid)
	return found_meta

func lookup(unityref: Array) -> Resource:
	var found_meta: Resource = lookup_meta(unityref)
	if found_meta == null:
		return null
	var local_id: int = unityref[1]
	# Not implemented:
	#var local_id: int = found_meta.local_id_alias.get(unityref.fileID, unityref.fileID)
	if found_meta.parsed == null:
		push_error("Target ref " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + " was not yet parsed! from " + path + " (" + guid + ")")
		return null
	var ret: Reference = found_meta.parsed.assets.get(local_id)
	if ret == null:
		push_error("Target ref " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + " is null! from " + path + " (" + guid + ")")
		return null
	ret.meta = found_meta
	return ret

func get_godot_resource(unityref: Array) -> Resource:
	var found_meta: Resource = lookup_meta(unityref)
	if found_meta == null:
		if len(unityref) == 4 and unityref[1] != 0:
			var found_path: String = get_database().guid_to_path.get(unityref[2], "")
			push_error("Resource with no meta. Try blindly loading it: " + str(unityref) + "/" + found_path)
			return load("res://" + found_path)
		return null
	var local_id: int = unityref[1]
	# print("guid:" + str(found_meta.guid) +" path:" + str(found_meta.path) + " main_obj:" + str(found_meta.main_object_id) + " local_id:" + str(local_id))
	if found_meta.main_object_id != 0 and found_meta.main_object_id == local_id:
		return load("res://" + found_meta.path)
	if found_meta.godot_resources.has(local_id):
		var ret: Variant = found_meta.godot_resources.get(local_id, null)
		if typeof(ret) == TYPE_STRING:
			return load(ret)
		else:
			return ret
	if found_meta.parsed == null:
		push_error("Target ref " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + " was not yet parsed! from " + path + " (" + guid + ")")
		return null
	push_error("Target ref " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + " would need to dynamically create a godot resource! from " + path + " (" + guid + ")")
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

func get_components_fileids(fileid: int, type: String="") -> PackedInt64Array:
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

func parse_binary_asset(bytearray: PackedByteArray) -> ParsedAsset:
	var parsed = ParsedAsset.new()
	print("Parsing " + str(guid))
	var bin_parser = bin_parser_class.new(self, bytearray)
	print("Parsed " + str(guid) + ":" + str(bin_parser) + " found " + str(len(bin_parser.objs)) + " objects and " + str(len(bin_parser.defs)) + " defs")
	var next_basic_id: Dictionary = {}.duplicate()
	var i = 0
	for output_obj in bin_parser.objs:
		i += 1
		if self.main_object_id == 0:
			push_error("We have no main_object_id but it should be " + str(output_obj.utype * 100000))
			self.main_object_id = output_obj.utype * 100000
		parsed.assets[output_obj.fileID] = output_obj
		fileid_to_utype[output_obj.fileID] = output_obj.utype
		if not type_to_fileids.has(output_obj.type):
			type_to_fileids[output_obj.type] = PackedInt64Array()
		type_to_fileids[output_obj.type].push_back(output_obj.fileID)
		if not output_obj.is_stripped and output_obj.keys.get("m_GameObject", [null,0,null,null])[1] != 0:
			fileid_to_gameobject_fileid[output_obj.fileID] = output_obj.keys.get("m_GameObject")[1]
		var new_basic_id: int = next_basic_id.get(output_obj.utype, output_obj.utype * 100000)
		next_basic_id[output_obj.utype] = new_basic_id + 1
		parsed.local_id_alias[new_basic_id] = output_obj.fileID

	self.parsed = parsed
	print("Done parsing!")
	return parsed

func parse_asset(file: Object) -> ParsedAsset:
	var magic = file.get_line()
	print("Parsing " + self.guid + " : " + file.get_path())
	if not magic.begins_with("%YAML"):
		return null

	var parsed = ParsedAsset.new()

	var yaml_parser = yaml_parser_class.new()
	var i = 0
	# var recycle_ids: Dictionary = {}
	#if self.importer != null:
	#	recycle_ids = self.importer.keys.get("fileIDToRecycleName", {})
	var next_basic_id: Dictionary = {}.duplicate()
	while true:
		i += 1
		var lin = file.get_line()
		var output_obj = yaml_parser.parse_line(lin, self, false)
		if output_obj != null:
			if self.main_object_id == 0:
				push_error("We have no main_object_id but it should be " + str(output_obj.utype * 100000))
				self.main_object_id = output_obj.utype * 100000
			parsed.assets[output_obj.fileID] = output_obj
			fileid_to_utype[output_obj.fileID] = output_obj.utype
			if not type_to_fileids.has(output_obj.type):
				type_to_fileids[output_obj.type] = [].duplicate()
			type_to_fileids[output_obj.type].push_back(output_obj.fileID)
			if not output_obj.is_stripped and output_obj.keys.get("m_GameObject", [null,0,null,null])[1] != 0:
				fileid_to_gameobject_fileid[output_obj.fileID] = output_obj.keys.get("m_GameObject")[1]
			var new_basic_id: int = next_basic_id.get(output_obj.utype, output_obj.utype * 100000)
			next_basic_id[output_obj.utype] = new_basic_id + 1
			parsed.local_id_alias[new_basic_id] = output_obj.fileID
		if file.get_error() == ERR_FILE_EOF:
			break
	self.parsed = parsed
	return parsed

func _init():
	pass

func init_with_file(file: Object, path: String):
	self.path = path
	self.resource_name = path
	type_to_fileids = {}.duplicate() # push_back is not idempotent. must clear to avoid duplicates.
	if file == null:
		return  # Dummy meta object

	var magic = file.get_line()
	print("Parsing meta file! " + file.get_path())
	if not magic.begins_with("fileFormatVersion:"):
		return

	var yaml_parser = yaml_parser_class.new()
	var i = 0
	while true:
		i += 1
		var lin = file.get_line()
		var output_obj: Resource = yaml_parser.parse_line(lin, self, true)
		# unity_object_adapter.UnityObject
		if output_obj != null:
			print("Finished parsing output_obj: " + str(output_obj) + "/" + str(output_obj.type))
			self.importer_keys = output_obj.keys
			self.importer_type = output_obj.type
			self.importer = output_obj
			self.main_object_id = self.importer.main_object_id
		if file.get_error() == ERR_FILE_EOF:
			break
	assert(self.guid != "")
