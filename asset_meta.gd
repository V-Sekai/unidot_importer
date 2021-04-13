@tool
extends Resource

const yaml_parser_class: GDScript = preload("./unity_object_parser.gd")
const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")

var database: Resource = null
@export var path: String = ""
@export var guid: String = ""
@export var importer_keys: Dictionary = {}
@export var importer_type: String = ""
var importer: Reference = null # unity_object_adapter.UnityAssetImporter subclass
# for .fbx, must use fileIDToRecycleName in meta.
@export var internal_data: Dictionary = {}

@export var prefab_id_to_guid: Dictionary = {}

# we have a list of all prefabs by ID
#####@export var prefab_fileID_to_parented_fileID: Dictionary = {}
#####@export var prefab_fileID_to_parented_prefab: Dictionary = {}

var prefab_fileid_to_nodepath: Dictionary = {}
var prefab_fileid_to_skeleton_bone: Dictionary = {} # int -> string
var prefab_fileid_to_utype: Dictionary = {} # int -> int

@export var fileid_to_nodepath: Dictionary = {}
@export var fileid_to_skeleton_bone: Dictionary = {} # int -> string
@export var fileid_to_utype: Dictionary = {} # int -> int
@export var godot_resources: Dictionary = {}
@export var main_object_id: int = 0 # e.g. 2100000 for .mat; 100000 for .fbx or GameObject; 100100000 for .prefab

@export var dependency_guids: Dictionary = {}
@export var prefab_dependency_guids: Dictionary = {}

class ParsedAsset extends Reference:
	var local_id_alias: Dictionary = {} # type*100000 + file_index*2 -> real fileId
	var assets: Dictionary = {} # int fileID -> unity_object_adapter.UnityObject

var parsed: ParsedAsset = null

class TopsortTmp extends Reference:
	var visited: Dictionary = {}.duplicate()
	var output: Array = [].duplicate()

func toposort_prefab_recurse(meta: Resource, tt: TopsortTmp):
	for target_guid in meta.prefab_dependency_guids:
		if not tt.visited.has(target_guid):
			tt.visited[target_guid] = true
			var child_meta: Resource = lookup_meta_by_guid_noinit(target_guid)
			if child_meta == null:
				printerr("Unable to find dependency " + str(target_guid) + " of type " + str(meta.dependency_guids.get(target_guid, "")))
			else:
				toposort_prefab_recurse(child_meta, tt)
	tt.output.push_back(meta)

func toposort_prefab_dependency_guids() -> Array:
	var tt: TopsortTmp = TopsortTmp.new()
	toposort_prefab_recurse(self, tt)
	return tt.output

# Expected to be called in topological order
func calculate_prefab_nodepaths():
	#if not is_toplevel:
	for prefab_fileid in self.prefab_id_to_guid:
		var target_prefab_meta: Resource = lookup_meta_by_guid_noinit(self.prefab_id_to_guid.get(prefab_fileid))
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


func calculate_prefab_nodepaths_recursive():
	var toposorted: Variant = toposort_prefab_dependency_guids()
	if typeof(toposorted) != TYPE_ARRAY:
		printerr("BLEH BLEH")
		return
	for process_meta in toposorted:
		if process_meta != null and process_meta.guid != guid and (process_meta.main_object_id == 100100000 or process_meta.importer_type == "PrefabImporter"):
			process_meta.calculate_prefab_nodepaths()

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
	database.rename_meta(self, new_path)

# Some properties cannot be serialized.
func initialize(database: Resource):
	self.database = database
	self.prefab_fileid_to_nodepath = {}
	self.prefab_fileid_to_skeleton_bone = {}
	self.prefab_fileid_to_utype = {}
	if self.importer_type == "":
		self.importer = object_adapter_class.new().instantiate_unity_object(self, 0, 0, "AssetImporter")
	else:
		self.importer = object_adapter_class.new().instantiate_unity_object(self, 0, 0, self.importer_type)
	self.importer.keys = importer_keys

func lookup_meta_by_guid_noinit(target_guid: String) -> Reference: # returns asset_meta type
	var found_path: String = database.guid_to_path.get(target_guid, "")
	var found_meta: Resource = null
	if found_path != "":
		found_meta = database.path_to_meta.get(found_path, null)
	return found_meta

func lookup_meta_by_guid(target_guid: String) -> Reference: # returns asset_meta type
	var found_meta: Resource = lookup_meta_by_guid_noinit(target_guid)
	if found_meta == null:
		return null
	if found_meta.database == null:
		found_meta.initialize(self.database)
	return found_meta

func lookup_meta(unityref: Array) -> Reference: # returns asset_meta type
	if unityref.is_empty() or len(unityref) != 4:
		printerr("UnityRef in wrong format: " + str(unityref))
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
		printerr("Target ref " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + " was not yet parsed! from " + path + " (" + guid + ")")
		return null
	var ret: Reference = found_meta.parsed.assets.get(local_id)
	if ret == null:
		printerr("Target ref " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + " is null! from " + path + " (" + guid + ")")
		return null
	ret.meta = found_meta
	return ret

func get_godot_resource(unityref: Array) -> Resource:
	var found_meta: Resource = lookup_meta(unityref)
	if found_meta == null:
		if len(unityref) == 4 and unityref[1] != 0:
			var found_path: String = database.guid_to_path.get(unityref[2], "")
			printerr("Resource with no meta. Try blindly loading it: " + str(unityref) + "/" + found_path)
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
		printerr("Target ref " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + " was not yet parsed! from " + path + " (" + guid + ")")
		return null
	printerr("Target ref " + found_meta.path + ":" + str(local_id) + " (" + found_meta.guid + ")" + " would need to dynamically create a godot resource! from " + path + " (" + guid + ")")
	#var res: Resource = found_meta.parsed.assets[local_id].create_godot_resource()
	#found_meta.godot_resources[local_id] = res
	#return res
	return null

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
				printerr("We have no main_object_id but it should be " + str(output_obj.utype * 100000))
				self.main_object_id = output_obj.utype * 100000
			parsed.assets[output_obj.fileID] = output_obj
			var new_basic_id: int = next_basic_id.get(output_obj.utype, output_obj.utype * 100000)
			next_basic_id[output_obj.utype] = new_basic_id + 1
			parsed.local_id_alias[new_basic_id] = output_obj.fileID
		if file.get_error() == ERR_FILE_EOF:
			break
	self.parsed = parsed
	return parsed

static func create_dummy_meta(asset_path: String) -> Resource:
	var meta = new()
	meta.assets = {}.duplicate()
	meta.path = asset_path
	var hc: HashingContext = HashingContext.new()
	hc.start(HashingContext.HASH_MD5)
	hc.update("GodotDummyMetaGuid".to_ascii_buffer())
	hc.update(asset_path.to_ascii_buffer())
	meta.guid = hc.finish().hex_encode()
	return meta

static func parse_meta(file: Object, path: String) -> Resource: # This class...
	var meta = new()
	meta.path = path

	var magic = file.get_line()
	print("Parsing meta file! " + file.get_path())
	if not magic.begins_with("fileFormatVersion:"):
		return meta

	var yaml_parser = yaml_parser_class.new()
	var i = 0
	while true:
		i += 1
		var lin = file.get_line()
		var output_obj: Resource = yaml_parser.parse_line(lin, meta, true)
		# unity_object_adapter.UnityObject
		if output_obj != null:
			print("Finished parsing output_obj: " + str(output_obj) + "/" + str(output_obj.type))
			meta.importer_keys = output_obj.keys
			meta.importer_type = output_obj.type
			meta.importer = output_obj
			meta.main_object_id = meta.importer.main_object_id
		if file.get_error() == ERR_FILE_EOF:
			break
	assert(meta.guid != "")
	return meta;
