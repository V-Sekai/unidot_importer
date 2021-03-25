extends Reference

const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")

############ FIXME: This should be Array(fileId, guid, utype)
#### WE CANNOT STORE Resource AS INNER CLASS!!
#class UnityRef extends Resource:
#	var fileID: int = 0
#	var guid: String = ""
#	var utype: int = 0
#	func to_string() -> String:
#		return _to_string()
#	func _to_string() -> String:
#		var ret: String = "[UNITY REF {fileID: " + str(fileID)
#		if guid != "":
#			ret += ", guid: " + str(guid)
#		ret += "}]"
#		return ret

var object_adapter = object_adapter_class.new()

var indentation_level: int = 0
var current_obj: Object = null
var current_obj_type: String = ""
var current_obj_utype: int = 0
var current_obj_fileID: int = 0
var current_obj_stripped: bool = false
var brace_line: String = ""
var continuation_line_indentation_level: int = 0
var double_quote_line: String = ""
var single_quote_line: String = ""
var prev_key: String = ""
var current_obj_tree: Array = []
var current_indent_tree: Array = []
var meta_guid: String = ""
var search_obj_key_regex: RegEx = RegEx.new()
var arr_obj_key_regex: RegEx = RegEx.new()
var line_number: int = 0

func _init():
	current_obj = null
	arr_obj_key_regex = RegEx.new()
	arr_obj_key_regex.compile("^-?\\s?([^\"\'{}:]*):\\s*")
	search_obj_key_regex = RegEx.new()
	search_obj_key_regex.compile("\\s*([^\"\'{}:]*):\\s*")

func parse_value(line: String) -> Variant:
	if len(line) < 24 and line.is_valid_integer():
		return line.to_int()
	if len(line) < 32 and line.is_valid_float():
		return line.to_float()
	if line == "[]":
		return [].duplicate()
	if line.begins_with("{}"):
		# either {}
		# or:
		# - a: b
		# - c: d
		# We treat dictionaries as arrays where each item is a single key dictionary
		# This is technically wrong, so we might want to fix some day.
		# fileIdToRecycleMap is the only known usage of this anyway
		return [].duplicate()
	if line.begins_with("{"):
		if not line.ends_with("}"):
			printerr("Invalid object value " + line.substr(0, 64))
			return null
		var value_color: Color = Color()
		var value_quat: Quat = Quat()
		var value_vec3: Vector3 = Vector3()
		var value_vec2: Vector2 = Vector2()
		var is_vec2: bool = false
		var is_color: bool = false
		var is_vec3: bool = false
		var is_quat: bool = false
		var value_ref: Array = [] # UnityRef
		# UnityRef, Vector2, Vector3, Quaternion?
		var offset = 1
		while true:
			var match_obj = search_obj_key_regex.search(line, offset)
			if match_obj == null:
				printerr("Unable to match regex on inline object @" + str(line_number) + ": " + line.substr(128))
			#	break
			offset = match_obj.get_end()
			var comma = line.find(",", offset)
			var value: String = ""
			if comma == -1:
				value = line.substr(offset, len(line) - offset - 1)
			else:
				value = line.substr(offset, comma - offset)
				offset = comma + 1
			var key = match_obj.get_string(1)
			match key:
				"x":
					value_quat.x = value.to_float()
					value_vec3.x = value.to_float()
					value_vec2.x = value.to_float()
				"y":
					value_quat.y = value.to_float()
					value_vec3.y = value.to_float()
					value_vec2.y = value.to_float()
					is_vec2 = true
				"z":
					value_quat.z = value.to_float()
					value_vec3.z = value.to_float()
					is_vec3 = true
				"w":
					value_quat.w = value.to_float()
					is_quat = true
				"r":
					value_color.r = value.to_float()
					is_color = true
				"g":
					value_color.g = value.to_float()
				"b":
					value_color.b = value.to_float()
				"a":
					value_color.a = value.to_float()
				"instanceID", "fileID": # {instanceID: 0} instead of fileID??
					#if value != "0":
					if value_ref.is_empty():
						value_ref.resize(4)
					value_ref[1] = value.to_int()
				"guid":
					if value_ref.is_empty():
						value_ref.resize(4)
					value_ref[2] = value
				"type":
					if value_ref.is_empty():
						value_ref.resize(4)
					value_ref[3] = value.to_int()
				_:
					printerr("Unsupported serializable struct type " + key + ": " + line.substr(128))
			if comma == -1:
				break
		if is_quat:
			return value_quat
		elif is_color:
			return value_color
		elif is_vec3:
			return value_vec3
		elif is_vec2:
			return value_vec2
		elif not value_ref.is_empty():
			return value_ref
		else:
			return null
	elif line.begins_with('\"'):
		return JSON.parse(line).result
	elif line.begins_with("'"):
		return line.substr(1, len(line)-1).replace("''", "")
	else:
		return line

func parse_line(line: String, meta: Object, is_meta: bool) -> Resource: # unity_object_adapter.UnityObject
	line_number = line_number + 1
	line = line.replace("\r", "")
	while line.ends_with("\r"):
		line = line.substr(0, len(line) - 1)
	var line_plain: String = line.dedent()
	var obj_key_match: RegExMatch = arr_obj_key_regex.search(line_plain)
	var value_start: int = 2
	if obj_key_match != null:
		value_start = 0 + obj_key_match.get_end()
	var missing_brace: bool = false
	var missing_single_quote: bool = false
	var missing_double_quote: bool = false
	var ending_double_quotes: bool = line_plain.ends_with('"')
	var ending_single_quotes: int = 1 if line_plain.ends_with("'") else 0
	if line_plain.ends_with("''"):
		ending_single_quotes = (len(line_plain) - len(line_plain.rstrip("'")))
	if ending_double_quotes:
		var idx: int = len(line_plain) - 2
		while line_plain.substr(idx, 1) == '\\':
			idx -= 1
			ending_double_quotes = not ending_double_quotes
	#print("st=" + str(value_start) + " < " + str(len(line_plain)) + ":" + line_plain)
	#print(JSON.print(line))
	if value_start < len(line_plain) and brace_line == "" and single_quote_line == "" and double_quote_line == "":
		missing_brace = line_plain.substr(value_start,1) == '{' and not line_plain.ends_with('}')
		missing_double_quote = line_plain.substr(value_start,1) == '"' and not line_plain.ends_with('"')
		missing_single_quote = line_plain.substr(value_start,1) == "'" and ending_single_quotes % 2 == (1 if ending_single_quotes + value_start == len(line_plain) else 0)
	var new_indentation_level = len(line) - len(line_plain)
	var object_to_return: Object = null
	if line.begins_with("--- ") or (line == "" and single_quote_line == ""):
		if current_obj != null:
			#print("line " + str(line) + ": Returning object of type " + str(current_obj.type))
			object_to_return = current_obj
			# print("returning " + str(current_obj) + " at line " + str(line_number)+":" + str(single_quote_line))
		indentation_level = 0
		if line.begins_with("--- "):
			current_obj = null
			var parts = line.split(" ")
			if !parts[1].begins_with("!u!"):
				printerr("Separator line not starting with --- !u!: " + line.substr(128))
			current_obj_utype = parts[1].substr(3).to_int()
			current_obj_fileID = parts[2].substr(1).to_int()
			current_obj_stripped = line.ends_with(" stripped")
	elif line == "%YAML 1.1":
		pass
	elif line == "%TAG !u! tag:unity3d.com,2011:":
		pass
	elif is_meta and line.begins_with("fileFormatVersion:"):
		# usually 2?
		pass
	elif is_meta and line.begins_with("folderAsset:"):
		# For directories; is set to "yes" if this is a folder .meta file
		pass
	elif is_meta and line.begins_with("timeCreated:"):
		# For directories; Unix time, in seconds
		pass
	elif is_meta and line.begins_with("licenseType:"):
		# For directories; Always says "Free"
		pass
	elif is_meta and line.begins_with("guid:"):
		meta.guid = line.split(":")[1].strip_edges()
	elif new_indentation_level == 0 and line.ends_with(":"):
		if current_obj != null:
			printerr("Creating toplevel object without header")
		current_obj_type = line.split(":")[0]
		current_obj = object_adapter.instantiate_unity_object(meta, current_obj_fileID, current_obj_utype, current_obj_type)
		if current_obj_stripped:
			current_obj.is_stripped = true
	elif line == "" and single_quote_line != "":
		single_quote_line += "\n"
	elif new_indentation_level == 0:
		printerr("Invalid toplevel line @" + str(line_number) + ": " + line.replace("\r","").substr(128))
	elif missing_single_quote:
		single_quote_line = line_plain
		continuation_line_indentation_level = new_indentation_level
		#print("Missing single start "  + str(single_quote_line))
	elif missing_double_quote:
		double_quote_line = line_plain
		continuation_line_indentation_level = new_indentation_level
		#print("Missing double start")
	elif missing_brace:
		brace_line = line_plain
		continuation_line_indentation_level = new_indentation_level
		#print("Missing brace start")
	elif (single_quote_line != "" and new_indentation_level > continuation_line_indentation_level and (ending_single_quotes % 2) == 0):
		single_quote_line += line_plain
		#print("Missing single mid: " + brace_line)
	elif (double_quote_line != "" and new_indentation_level > continuation_line_indentation_level and not ending_double_quotes):
		double_quote_line += " " + line_plain
		#print("Missing double mid: " + brace_line)
	elif (brace_line != "" and new_indentation_level > continuation_line_indentation_level and not line_plain.ends_with('}')):
		brace_line += line_plain
		printerr("Missing brace mid: " + brace_line)
	else:
		if new_indentation_level > continuation_line_indentation_level:
			var endcontinuation: bool = false
			if brace_line != "" and line_plain.ends_with('}'):
				line_plain = brace_line + line_plain
				brace_line = ""
				endcontinuation = true
				#print("Missing brace end")
			if single_quote_line != "" and (ending_single_quotes % 2) != 0:
				line_plain = single_quote_line + line_plain
				single_quote_line = ""
				endcontinuation = true
				#print("Missing single end")
			if double_quote_line != "" and ending_double_quotes:
				line_plain = double_quote_line + " " + line_plain
				double_quote_line = ""
				endcontinuation = true
				#print("Missing double end")
			if endcontinuation:
				new_indentation_level = continuation_line_indentation_level
				obj_key_match = arr_obj_key_regex.search(line_plain)
		if new_indentation_level > indentation_level or (new_indentation_level == indentation_level and line_plain.begins_with("- ") and typeof(current_obj_tree.back()) != TYPE_ARRAY):
			if line_plain.begins_with("- "):
				current_indent_tree.push_back(indentation_level)
				var new_arr: Array = [].duplicate()
				current_obj_tree.back()[prev_key] = new_arr
				current_obj_tree.push_back(new_arr)
				indentation_level = new_indentation_level
			else:
				var new_obj: Dictionary = {}.duplicate()
				current_indent_tree.push_back(indentation_level)
				if indentation_level == 0:
					new_obj = current_obj.keys
				else:
					current_obj_tree.back()[prev_key] = new_obj
				current_obj_tree.push_back(new_obj)
				indentation_level = new_indentation_level
		else:
			while new_indentation_level < indentation_level:
				indentation_level = current_indent_tree[-1]
				current_indent_tree.pop_back()
				current_obj_tree.pop_back()
			if typeof(current_obj_tree.back()) == TYPE_ARRAY and not line_plain.begins_with("- "):
				current_indent_tree.pop_back()
				current_obj_tree.pop_back()

		if line_plain.begins_with("- ") and obj_key_match != null:
			current_indent_tree.push_back(indentation_level)
			indentation_level = new_indentation_level + 2
			var new_obj = {}.duplicate()
			current_obj_tree.back().push_back(new_obj)
			current_obj_tree.push_back(new_obj)
		if obj_key_match != null:
			if obj_key_match.get_end() == len(line_plain):
				prev_key = obj_key_match.get_string(1)
			else:
				var parsed_val = parse_value(line_plain.substr(obj_key_match.get_end()))
				if typeof(parsed_val) == TYPE_ARRAY and len(parsed_val) >= 3 and parsed_val[0] == null and typeof(parsed_val[2]) == TYPE_STRING:
					match obj_key_match.get_string(1):
						"m_SourcePrefab", "m_ParentPrefab":
							meta.prefab_dependency_guids[parsed_val[2]] = 1
					meta.dependency_guids[parsed_val[2]] = 1
				current_obj_tree.back()[obj_key_match.get_string(1)] = parsed_val
		elif line_plain.begins_with("- "):
			var parsed_val = parse_value(line_plain.substr(2))
			if typeof(parsed_val) == TYPE_ARRAY and len(parsed_val) >= 3 and parsed_val[0] == null and typeof(parsed_val[2]) == TYPE_STRING:
				meta.dependency_guids[parsed_val[2]] = 1
			current_obj_tree.back().push_back(parsed_val)
	return object_to_return
