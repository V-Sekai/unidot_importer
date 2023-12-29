# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021 Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends AnimationTree

var meta_to_blend_parameters: Dictionary = {}.duplicate()
var blend_to_meta_parameter: Dictionary = {}.duplicate()
var seek_requests: Array
var _recurse: StringName = &""
var _current_meta: StringName = &""


func _find_animation_node(np: NodePath) -> AnimationNode:
	var node: AnimationNode = tree_root
	for idx in range(1, np.get_name_count() - 1):
		if node is AnimationNodeBlendTree:
			node = node.get_node(np.get_name(idx))
		elif node is AnimationNodeStateMachine:
			if np.get_name(idx) == &"conditions":
				return null
			node = node.get_node(np.get_name(idx))
		elif node is AnimationNodeBlendSpace1D:
			node = node.get_blend_point_node(str(np.get_name(idx)).to_int())
		elif node is AnimationNodeBlendSpace2D:
			node = node.get_blend_point_node(str(np.get_name(idx)).to_int())
		elif node is AnimationNodeAnimation:
			push_error("Encountered AnimationNodeAnimation while walking node tree... " + str(np))
		else:
			push_error("Encountered unknown node type " + str(node.get_class()) + " while walking node tree... " + str(np))
			node = node._get_child_by_name(np.get_name(idx))
		if node == null:
			push_error("Failed to find node at " + str(idx) + " in " + str(np))
	return node


func _setup_blend_to_meta(prop: StringName):
	var np: NodePath = NodePath(str(prop))
	var node: AnimationNode = _find_animation_node(np)
	if node == null:
		blend_to_meta_parameter[prop] = &""
		return
	var last_path: StringName = np.get_name(np.get_name_count() - 1)
	if last_path == &"playback":
		blend_to_meta_parameter[prop] = &""
		return
	# print("found " + str(np) + " : " + str(node))
	#for parameter in node.get_meta_list():
	#	var node_param: String = parameter
	#	if parameter.ends_with("_x") or parameter.ends_with("_y"):
	#		node_param = parameter.substr(0, len(parameter) - 2)
	#	var prop_request: StringName = StringName(str(prop).substr(0, len(str(prop)) - len(str(last_path))) + node_param)
	#	_recurse = prop_request
	#	if typeof(self.get(prop_request)) == TYPE_NIL:
	#		node.remove_meta(StringName(parameter))
	#	_recurse = &""
	if node is AnimationNodeBlendSpace2D:
		var meta_x: Variant = null
		var meta_y: Variant = null
		var sn: StringName = StringName(str(last_path) + "_x")
		if not node.has_meta(sn):
			node.set_meta(sn, &"")
		meta_x = node.get_meta(sn)
		sn = StringName(str(last_path) + "_y")
		if not node.has_meta(sn):
			node.set_meta(sn, &"")
		meta_y = node.get_meta(sn)
		if typeof(meta_x) == TYPE_STRING:
			meta_x = StringName(meta_x)
		if typeof(meta_y) == TYPE_STRING:
			meta_y = StringName(meta_y)
		if not Engine.is_editor_hint():
			blend_to_meta_parameter[prop] = &""
		if typeof(meta_x) == TYPE_STRING_NAME:
			if typeof(meta_y) == TYPE_STRING_NAME:
				if meta_x != &"" and meta_y != &"":
					blend_to_meta_parameter[prop] = [meta_x, meta_y]
					if not meta_to_blend_parameters.has(meta_x):
						meta_to_blend_parameters[meta_x] = [].duplicate()
					if not meta_to_blend_parameters.has(meta_y):
						meta_to_blend_parameters[meta_y] = [].duplicate()
					meta_to_blend_parameters[meta_x].append([true, prop, meta_y])
					meta_to_blend_parameters[meta_y].append([false, prop, meta_x])
					if not tree_root.has_meta(meta_x):
						tree_root.set_meta(meta_x, get(prop).x)
					if not tree_root.has_meta(meta_y):
						tree_root.set_meta(meta_y, get(prop).y)
					set_meta(meta_x, tree_root.get_meta(meta_x, get(prop).x))
					set_meta(meta_y, tree_root.get_meta(meta_y, get(prop).y))
	else:
		var meta: Variant = null
		if not node.has_meta(last_path):
			node.set_meta(last_path, &"")
		meta = node.get_meta(last_path)
		if not Engine.is_editor_hint():
			blend_to_meta_parameter[prop] = &""
		if typeof(meta) == TYPE_STRING:
			meta = StringName(meta)
		if typeof(meta) == TYPE_STRING_NAME:
			if meta != &"":
				blend_to_meta_parameter[prop] = meta
				if not meta_to_blend_parameters.has(meta):
					meta_to_blend_parameters[meta] = [].duplicate()
				meta_to_blend_parameters[meta].append(prop)
				if prop.ends_with("/seek_request"):
					seek_requests.append(prop)
				if not tree_root.has_meta(meta):
					tree_root.set_meta(meta, get(prop))
				set_meta(meta, tree_root.get_meta(meta, get(prop)))
		elif typeof(meta) != TYPE_NIL:
			blend_to_meta_parameter[prop] = &""
			if prop.ends_with("/seek_request"):
				seek_requests.append(prop)
			super.set(prop, meta)


func _get(prop: StringName):
	if tree_root == null:
		seek_requests.clear()
		meta_to_blend_parameters.clear()
		blend_to_meta_parameter.clear()
		return null
	if _recurse == prop:
		return null
	if str(prop).begins_with("parameters/"):
		if not blend_to_meta_parameter.has(prop):
			_setup_blend_to_meta(prop)

		var meta_parameter = blend_to_meta_parameter.get(prop)
		if typeof(meta_parameter) == TYPE_STRING_NAME:
			if meta_parameter == &"":
				return null
			return get_meta(meta_parameter)
		if typeof(meta_parameter) == TYPE_ARRAY:
			return Vector2(get_meta(meta_parameter[0], 0), get_meta(meta_parameter[1], 0))
		return null
	if not str(prop).begins_with("metadata/"):
		#print(self.get_property_list())
		if has_meta(prop):
			#print("prop " + str(prop) + " " + str(get_meta(prop)))
			return get_meta(prop)
		if tree_root.has_meta(prop):
			set_meta(prop, tree_root.get_meta(prop))
			return get_meta(prop)
	return null


func _set(prop: StringName, value):
	if prop == &"tree_root" and value != self.tree_root:
		for param in meta_to_blend_parameters:
			self.remove_meta(param)
		if self.tree_root != null:
			for param in self.tree_root.get_meta_list():
				if self.has_meta(StringName(param)):
					self.remove_meta(StringName(param))
		seek_requests.clear()
		meta_to_blend_parameters.clear()
		blend_to_meta_parameter.clear()
		if value != null:
			for param in value.get_meta_list():
				self.set_meta(StringName(param), value.get_meta(param))
			if active:
				for prop_data in get_property_list():
					if prop_data["name"].begins_with("parameters/"):
						_setup_blend_to_meta(prop_data["name"])
		return false
	if prop == &"active" and value != self.active:
		for param in meta_to_blend_parameters:
			self.remove_meta(param)
		if self.tree_root != null:
			for param in self.tree_root.get_meta_list():
				if self.has_meta(StringName(param)):
					self.remove_meta(StringName(param))
		seek_requests.clear()
		meta_to_blend_parameters.clear()
		blend_to_meta_parameter.clear()
		if value:
			for param in self.tree_root.get_meta_list():
				self.set_meta(StringName(param), self.tree_root.get_meta(param))
			if self.tree_root != null:
				for prop_data in get_property_list():
					if prop_data["name"].begins_with("parameters/"):
						_setup_blend_to_meta(prop_data["name"])
		return false
	if str(prop).begins_with("parameters/"):
		var meta_parameter = blend_to_meta_parameter.get(prop)
		if typeof(value) == TYPE_VECTOR2:
			if typeof(meta_parameter) == TYPE_ARRAY:
				set_meta(meta_parameter[0], value.x)
				set_meta(meta_parameter[1], value.y)
		else:
			#print("Hardcoded " + str(prop) + " " + str(value))
			if typeof(meta_parameter) == TYPE_STRING_NAME:
				if meta_parameter != &"":
					set_meta(meta_parameter, value)
			if not self.active and Engine.is_editor_hint():
				# In editor, convenience function to save node values as defaults.
				var np: NodePath = NodePath(str(prop))
				var node: AnimationNode = _find_animation_node(np)
				if node == null:
					blend_to_meta_parameter[prop] = &""
					return
				var last_path: StringName = np.get_name(np.get_name_count() - 1)
				var meta: Variant = node.get_meta(last_path)
				if typeof(meta) == TYPE_STRING_NAME:
					if meta == &"":
						node.set_meta(last_path, value)
				elif typeof(meta) == typeof(value):
					node.set_meta(last_path, value)
			return false
		return false
	if str(prop).begins_with("metadata/"):
		if _current_meta == prop:
			return false
		_current_meta = prop
		for blend_parameter in meta_to_blend_parameters.get(prop.substr(9), {}):
			if typeof(blend_parameter) == TYPE_STRING_NAME:
				set(blend_parameter, value)
			elif typeof(blend_parameter) == TYPE_ARRAY:
				if blend_parameter[0]:
					set(blend_parameter[1], Vector2(value, get_meta(blend_parameter[2])))
				else:
					set(blend_parameter[1], Vector2(get_meta(blend_parameter[2]), value))
		_current_meta = &""
		return false
	return false

func _ready():
	if active and tree_root != null:
		for prop_data in get_property_list():
			if prop_data["name"].begins_with("parameters/"):
				_setup_blend_to_meta(prop_data["name"])

func _process(_delta: float):
	for prop in seek_requests:
		var meta_parameter = blend_to_meta_parameter.get(prop)
		if typeof(meta_parameter) == TYPE_STRING_NAME:
			if meta_parameter != &"":
				set(prop, get_meta(meta_parameter))
		elif typeof(meta_parameter) != TYPE_NIL:
			set(prop, get_meta(meta_parameter))
