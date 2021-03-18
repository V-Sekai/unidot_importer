@tool
extends Reference

func to_classname(utype: int) -> String:
	var ret = utype_to_classname.get(utype, "")
	if ret == "":
		return "[UnknownType:" + str(utype) + "]"
	return ret


func to_utype(classname: String) -> int:
	return classname_to_utype.get(classname, 0)


func instantiate_unity_object(meta: Object, fileID: int, utype: int, type: String) -> UnityObject:
	var ret: UnityObject = null
	var actual_type = type
	if utype != 0 and utype_to_classname.has(utype):
		actual_type = utype_to_classname[utype]
		if actual_type != type and (type != "Behaviour" or actual_type != "FlareLayer") and (type != "Prefab" or actual_type != "PrefabInstance"):
			printerr("Mismatched type for " + meta.guid + ":" + str(fileID) + " type:" + type + " vs. utype:" + str(utype) + ":" + actual_type)
	if _type_dictionary.has(actual_type):
		# print("Will instantiate object of type " + str(actual_type) + "/" + str(type) + "/" + str(utype) + "/" + str(classname_to_utype.get(actual_type, utype)))
		ret = _type_dictionary[actual_type].new()
	else:
		printerr("Failed to instantiate object of type " + str(actual_type) + "/" + str(type) + "/" + str(utype) + "/" + str(classname_to_utype.get(actual_type, utype)))
		if type.ends_with("Importer"):
			ret = UnityAssetImporter.new()
		else:
			ret = UnityObject.new()
	ret.meta = meta
	ret.fileID = fileID
	if utype != 0 and utype != classname_to_utype.get(actual_type, utype):
		printerr("Mismatched utype " + str(utype) + " for " + type)
	ret.utype = classname_to_utype.get(actual_type, utype)
	ret.type = actual_type
	return ret


class Skelley extends Reference:
	var id: int = 0
	var bones: Array = [].duplicate()
	
	var root_bones: Array = [].duplicate()
	
	var physical_bones: Dictionary = {}.duplicate()
	var bone_attachments: Dictionary = {}.duplicate()
	
	var uniq_key_to_bone: Dictionary = {}.duplicate()
	var godot_skeleton: Skeleton3D = Skeleton3D.new()
	
	# Temporary private storage:
	var intermediate_bones: Array = [].duplicate()
	var intermediates: Dictionary = {}.duplicate()
	var bone0_parent_list: Array = [].duplicate()
	var bone0_parents: Dictionary = {}.duplicate()
	
	func initialize(bone0: UnityTransform):
		var current_parent: UnityTransform = bone0.parent
		var tmp: Array = [].duplicate()
		while current_parent != null:
			tmp.push_back(current_parent)
			print("Adding bone0_parents " + current_parent.name + ":" + current_parent.uniq_key)
			bone0_parents[current_parent.uniq_key] = current_parent
			intermediates[current_parent.uniq_key] = current_parent
			current_parent = current_parent.parent
		# reverse list
		for i in range(len(tmp)):
			bone0_parent_list.push_back(tmp[-1 - i])

	func add_bone(bone: UnityTransform) -> Array:
		bones.push_back(bone)
		var added_bones: Array = [].duplicate()
		var current_parent: UnityTransform = bone
		print("Checking bone0_parents " + current_parent.name + ":" + current_parent.uniq_key)
		while current_parent != null and not bone0_parents.has(current_parent.uniq_key):
			if intermediates.has(current_parent.uniq_key):
				return added_bones
			intermediates[current_parent.uniq_key] = current_parent
			intermediate_bones.push_back(current_parent)
			added_bones.push_back(current_parent)
			current_parent = current_parent.parent
		if current_parent == null:
			printerr("No common ancestor for skeleton " + bone.name + " containing " + bones[0].name)
			return added_bones
		if current_parent.parent == null:
			bone0_parents.clear()
			bone0_parent_list.clear()
			printerr("Warning: Skeleton parented at root " + bone.name + " containing " + bones[0].name + " at " + current_parent.name)
			return added_bones
		if bone0_parent_list.is_empty():
			return added_bones
		current_parent = current_parent.parent
		while bone0_parent_list[-1] != current_parent:
			bone0_parents.erase(bone0_parent_list[-1].uniq_key)
			bone0_parent_list.pop_back()
			if bone0_parent_list.is_empty():
				printerr("Assertion failure " + bones[0].name + "/" + current_parent.name)
				return []
			if not intermediates.has(bone0_parent_list[-1].uniq_key):
				intermediates[bone0_parent_list[-1].uniq_key] = bone0_parent_list[-1]
				intermediate_bones.push_back(bone0_parent_list[-1])
				added_bones.push_back(bone0_parent_list[-1])
		return added_bones

	# if null, this is a root node.
	var parent_transform: UnityTransform:
		get:
			if bone0_parent_list.is_empty():
				return null
			return bone0_parent_list[-1]

	func add_nodes_recursively(skel_parents: Dictionary, bone_transform: UnityTransform):
		for child_ref in bone_transform.children_refs:
			var child: UnityTransform = bone_transform.meta.lookup(child_ref)
			# not skel_parents.has(child.uniq_key):
			if not intermediates.has(child.uniq_key):
				intermediates[child.uniq_key] = child
				intermediate_bones.push_back(child)
			if len(child.gameObject.components) > 1:
				var rb: UnityRigidbody = child.gameObject.rigidbody
				if rb != null: #### and not rb.isKinematic:
					physical_bones[child.uniq_key] = rb
				else:
					bone_attachments[child.uniq_key] = child.gameObject
			# TODO: We might also want to include prefab instances here. If something is a prefab, we should not include it in the skeleton!
			if skel_parents.has(child.uniq_key):
				bone_attachments[child.uniq_key] = child.gameObject
				# We will not recurse: everything underneath this is part of a separate skeleton.
			else:
				add_nodes_recursively(skel_parents, child)

	func construct_final_bone_list(skel_parents: Dictionary):
		for bone in intermediate_bones:
			if bone.parent == self.parent_transform:
				root_bones.push_back(bone)
		for bone in root_bones:
			self.add_nodes_recursively(skel_parents, bone)
		# Keep original bone list in order; migrate intermediates in.
		for bone in bones:
			intermediates.erase(bone)
		for bone in intermediate_bones:
			if intermediates.has(bone):
				bones.push_back(bone)
		var idx: int = 0
		for bone in bones:
			uniq_key_to_bone[bone.uniq_key] = idx
			idx += 1
		idx = 0
		for bone in bones:
			godot_skeleton.add_bone(bone.name)
			godot_skeleton.set_bone_parent(idx, uniq_key_to_bone.get(bone.parent.uniq_key, -1))
			godot_skeleton.set_bone_rest(idx, bone.godot_transform)
			idx += 1
	# Skelley rules:
	# Root bone will be added as parent to common ancestor of all bones
	# Found parent transforms of each skeleton.
	# Found a list of bones in each skeleton.


static func create_node_state(database: Resource, meta: Resource, root_node: Node3D) -> GodotNodeState:
	var state: GodotNodeState = GodotNodeState.new()
	state.init_node_state(database, meta, root_node)
	return state


class GodotNodeState extends Reference:
	var owner: Node = null
	var body: CollisionObject3D = null
	var database: Resource = null # asset_database instance
	var meta: Resource = null # asset_database.AssetMeta instance

	# Dictionary from parent_transform uniq_key -> array of convert_scene.Skelley
	var skelley_parents: Dictionary = {}.duplicate()
	# Dictionary from any transform uniq_key -> convert_scene.Skelley
	var uniq_key_to_skelley: Dictionary = {}.duplicate()

	func duplicate():
		var state: GodotNodeState = GodotNodeState.new()
		state.owner = owner
		state.body = body
		state.database = database
		state.meta = meta
		state.skelley_parents = skelley_parents
		state.uniq_key_to_skelley = uniq_key_to_skelley
		return state
	
	func add_child(child: Node, new_parent: Node3D, fileID: int):
		if owner != null:
			new_parent.add_child(child)
			child.owner = owner
		if fileID != 0:
			add_fileID(child, fileID)

	func add_fileID_to_skeleton_bone(bone_name: String, fileID: int):
		meta.fileid_to_skeleton_bone[fileID] = bone_name
	
	func add_fileID(child: Node, fileID: int):
		if owner != null:
			meta.fileid_to_nodepath[fileID] = owner.get_path_to(child)
		else:
			meta.fileid_to_nodepath[fileID] = NodePath(".")
	
	func init_node_state(database: Resource, meta: Resource, root_node: Node3D) -> GodotNodeState:
		self.database = database
		self.meta = meta
		self.owner = root_node
		return self
	
	func state_with_body(new_body: CollisionObject3D) -> GodotNodeState:
		var state: GodotNodeState = duplicate()
		state.body = new_body
		return state

	func state_with_meta(new_meta: Resource) -> GodotNodeState:
		var state: GodotNodeState = duplicate()
		state.meta = new_meta
		return state

	func state_with_owner(new_owner: Node3D) -> GodotNodeState:
		var state: GodotNodeState = duplicate()
		state.owner = new_owner
		return state


static func initialize_skelleys(assets: Array, node_state: GodotNodeState) -> Array:
	var skelleys: Dictionary = {}.duplicate()
	var skel_ids: Dictionary = {}.duplicate()
	var num_skels = 0

	# Start out with one Skeleton per SkinnedMeshRenderer, but merge overlapping skeletons.
	# This includes skeletons where the members are interleaved (S1 -> S2 -> S1 -> S2)
	# which can actually happen in practice, for example clothing with its own bones.
	for asset in assets:
		if asset.type == "SkinnedMeshRenderer":
			var bones: Array = asset.bones
			if bones.is_empty():
				# Common if MeshRenderer is upgraded to SkinnedMeshRenderer, e.g. by the user.
				# For example, this happens when adding a Cloth component.
				# Also common for meshes which have blend shapes but no skeleton.
				# Skinned mesh renderers without bones act as normal meshes.
				continue
			var bone0_obj: UnityTransform = asset.meta.lookup(bones[0])
			# TODO: what about meshes with bones but without skin? Can this even happen?
			var this_id: int = num_skels
			var this_skelley: Skelley = null
			if skel_ids.has(bone0_obj.uniq_key):
				this_id = skel_ids[bone0_obj.uniq_key]
				this_skelley = skelleys[this_id]
			else:
				this_skelley = Skelley.new()
				this_skelley.initialize(bone0_obj)
				this_skelley.id = this_id
				skelleys[this_id] = this_skelley
				num_skels += 1

			for bone in bones:
				var bone_obj: UnityTransform = asset.meta.lookup(bone)
				var added_bones = this_skelley.add_bone(bone_obj)
				for added_bone in added_bones:
					var uniq_key: String = added_bone.uniq_key
					if skel_ids.get(uniq_key, this_id) != this_id:
						var new_id: int = skel_ids[uniq_key]
						for inst in skelleys[this_id].bones:
							if skel_ids.get(inst.uniq_key) == this_id:
								skelleys[new_id].add_bone(inst)
						for i in skel_ids:
							if skel_ids.get(str(i)) == this_id:
								skel_ids[str(i)] = new_id
						skelleys.erase(this_id) # We merged two skeletons.
						this_id = new_id
					skel_ids[uniq_key] = this_id
			print(str(skel_ids))

	var skelleys_with_no_parent = [].duplicate()

	# If skelley_parents contains your node, add Skelley.skeleton as a child to it for each item in the list.
	for skel_id in skelleys:
		var skelley: Skelley = skelleys[skel_id]
		if skelley.parent_transform == null:
			skelleys_with_no_parent.push_back(skelley)
		else:
			var uniq_key = skelley.parent_transform.uniq_key
			if not node_state.skelley_parents.has(uniq_key):
				node_state.skelley_parents[uniq_key] = [].duplicate()
			node_state.skelley_parents[uniq_key].push_back(skelley)

	for skel_id in skelleys:
		var skelley: Skelley = skelleys[skel_id]
		skelley.construct_final_bone_list(node_state.skelley_parents)
		for uniq_key in skelley.uniq_key_to_bone:
			node_state.uniq_key_to_skelley[uniq_key] = skelley

	return skelleys_with_no_parent


# Unity types follow:
### ================ BASE OBJECT TYPE ================
class UnityObject extends Reference:
	var meta: Resource = null # AssetMeta instance
	var keys: Dictionary = {}
	var fileID: int = 0 # Not set in .meta files
	var type: String = ""
	var utype: int = 0 # Not set in .meta files
	var _cache_uniq_key: String = ""

	var uniq_key: String:
		get:
			if _cache_uniq_key.is_empty():
				_cache_uniq_key = str(utype)+":"+str(keys.get("m_Name",""))+":"+str(meta.guid) + ":" + str(fileID)
			return _cache_uniq_key

	func _to_string() -> String:
		#return "[" + str(type) + " @" + str(fileID) + ": " + str(len(keys)) + "]" # str(keys) + "]"
		#return "[" + str(type) + " @" + str(fileID) + ": " + JSON.print(keys) + "]"
		return str(type) + ":" + str(name) + " @" + str(meta.guid) + ":" + str(fileID)

	var name: String:
		get:
			return keys.get("m_Name","NO_NAME:"+uniq_key)

	var toplevel: bool:
		get:
			return true

	var is_collider: bool:
		get:
			return false

	var transform: Object:
		get:
			return null

	# Belongs in UnityComponent, but we haven't implemented all types yet.
	func create_godot_node(state: GodotNodeState, new_parent: Node3D) -> Node:
		var new_node: Node = Node.new()
		new_node.name = type
		state.add_child(new_node, new_parent, fileID)
		return new_node

	func create_godot_resource() -> Resource:
		return null


### ================ ASSET TYPES ================
# FIXME: All of these are native Godot types. I'm not sure if these types are needed or warranted.
class UnityMesh extends UnityObject:
	pass

class UnityMaterial extends UnityObject:

	func get_float_properties() -> Dictionary:
		var flts = keys.get("m_SavedProperties").get("m_Floats")
		var ret = {}.duplicate()
		for dic in flts:
			for key in dic:
				ret[key] = dic.get(key)
		return ret

	func get_color_properties() -> Dictionary:
		var cols = keys.get("m_SavedProperties").get("m_Colors")
		var ret = {}.duplicate()
		for dic in cols:
			for key in dic:
				ret[key] = dic.get(key)
		return ret

	func get_tex_properties() -> Dictionary:
		var texs = keys.get("m_SavedProperties").get("m_TexEnvs")
		var ret = {}.duplicate()
		for dic in texs:
			for key in dic:
				ret[key] = dic.get(key)
		return ret

	func get_texture(texProperties: Dictionary, name: String) -> Texture:
		var env = texProperties.get(name, {})
		var texref: Array = env.get("m_Texture", [])
		if not texref.is_empty():
			return meta.get_godot_resource(texref)
		return null

	func get_texture_scale(texProperties: Dictionary, name: String) -> Vector3:
		var env = texProperties.get(name, {})
		var scale: Vector2 = env.get("m_Scale", Vector2(1,1))
		return Vector3(scale.x, scale.y, 0.0)

	func get_texture_offset(texProperties: Dictionary, name: String) -> Vector3:
		var env = texProperties.get(name, {})
		var offset: Vector2 = env.get("m_Offset", Vector2(0,0))
		return Vector3(offset.x, offset.y, 0.0)

	func get_color(colorProperties: Dictionary, name: String, dfl: Color) -> Color:
		var col: Color = colorProperties.get(name, dfl)
		return col

	func get_float(floatProperties: Dictionary, name: String, dfl: float) -> float:
		var ret: float = floatProperties.get(name, dfl)
		return ret

	func get_vector(colorProperties: Dictionary, name: String, dfl: Color) -> Plane:
		var col: Color = colorProperties.get(name, dfl)
		return Plane(Vector3(col.r, col.g, col.b), col.a)

	func get_keywords() -> Dictionary:
		var ret: Dictionary = {}.duplicate()
		var kwd = keys.get("m_ShaderKeywords", "")
		if typeof(kwd) == TYPE_STRING:
			for x in kwd.split(' '):
				ret[x] = true
		return ret

	func create_godot_resource() -> Material:
		var kws = get_keywords()
		var floatProperties = get_float_properties()
		print(str(floatProperties))
		var texProperties = get_tex_properties()
		print(str(texProperties))
		var colorProperties = get_color_properties()
		print(str(colorProperties))
		var ret = StandardMaterial3D.new()
		ret.albedo_tex_force_srgb = true # Nothing works if this isn't set to true explicitly. Stupid default.
		ret.albedo_color = get_color(colorProperties, "_Color", Color.white)
		ret.albedo_texture = get_texture(texProperties, "_MainTex")
		ret.uv1_scale = get_texture_scale(texProperties, "_MainTex")
		ret.uv1_offset = get_texture_offset(texProperties, "_MainTex")
		# TODO: ORM not yet implemented.
		if kws.get("_NORMALMAP", false):
			ret.normal_enabled = true
			ret.normal_texture = get_texture(texProperties, "_BumpMap")
			ret.normal_scale = get_float(floatProperties, "_BumpScale", 1.0)
		if kws.get("_EMISSION", false):
			ret.emission_enabled = true
			var emis_vec: Plane = get_vector(colorProperties, "_EmissionColor", Color.black)
			var emis_mag = max(emis_vec.x, max(emis_vec.y, emis_vec.z))
			ret.emission = Color.black
			if emis_mag > 0:
				ret.emission = Color(emis_vec.x/emis_mag, emis_vec.y/emis_mag, emis_vec.z/emis_mag)
				ret.emission_energy = emis_mag
			ret.emission_texture = get_texture(texProperties, "_EmissionMap")
		if kws.get("_PARALLAXMAP", false):
			ret.heightmap_enabled = true
			ret.heightmap_texture = get_texture(texProperties, "_ParallaxMap")
			ret.heightmap_scale = get_float(floatProperties, "_Parallax", 1.0)
		if kws.get("__SPECULARHIGHLIGHTS_OFF", false):
			ret.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		if kws.get("_GLOSSYREFLECTIONS_OFF", false):
			pass
		var occlusion = get_texture(texProperties, "_OcclusionMap")
		if occlusion != null:
			ret.ao_enabled = true
			ret.ao_texture = occlusion
			ret.ao_light_affect = get_float(floatProperties, "_OcclusionStrength", 1.0) # why godot defaults to 0???
			ret.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		if kws.get("_METALLICGLOSSMAP"):
			ret.metallic_texture = get_texture(texProperties, "_MetallicGlossMap")
			ret.metallic = get_float(floatProperties, "_Metallic", 0.0)
			ret.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		# TODO: Glossiness: invert color channels??
		ret.roughness = 1.0 - get_float(floatProperties, "_Glossiness", 0.0)
		if kws.get("_ALPHATEST_ON"):
			ret.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		elif kws.get("_ALPHABLEND_ON") or kws.get("_ALPHAPREMULTIPLY_ON"):
			# FIXME: No premultiply
			ret.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Godot's detail map is a bit lacking right now...
		#if kws.get("_DETAIL_MULX2"):
		#	ret.detail_enabled = true
		#	ret.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		return ret

class UnityShader extends UnityObject:
	pass

class UnityTexture extends UnityObject:
	pass

class UnityAnimationClip extends UnityObject:
	pass

class UnityTexture2D extends UnityTexture:
	pass

class UnityTexture2DArray extends UnityTexture:
	pass

class UnityTexture3D extends UnityTexture:
	pass

class UnityCubemap extends UnityTexture:
	pass

class UnityCubemapArray extends UnityTexture:
	pass

class UnityRenderTexture extends UnityTexture:
	pass

class UnityCustomRenderTexture extends UnityRenderTexture:
	pass

### ================ GAME OBJECT TYPE ================
class UnityGameObject extends UnityObject:

	func create_skeleton_bone(xstate: GodotNodeState, skelley: Skelley):
		var state: Object = xstate
		# Instead of a transform, this sets the skeleton transform position maybe?, etc. etc. etc.
		var transform: UnityTransform = self.transform
		var ret: Node3D = null
		state.add_fileID_to_skeleton_bone(self.name, fileID)
		state.add_fileID_to_skeleton_bone(self.name, transform.fileID)
		if skelley.bone_attachments.has(transform.uniq_key):
			var ba: BoneAttachment3D = BoneAttachment3D.new()
			ba.name = self.name
			ba.bone_name = self.name
			state.add_child(ba, skelley.godot_skeleton, fileID)
			state.add_fileID(ret, transform.fileID)
			ret = ba
		elif skelley.physical_bones.has(transform.uniq_key):
			ret = self.rigidbody.create_physical_bone(state, skelley, name)
			state.add_fileID(ret, fileID)
			state.add_fileID(ret, transform.fileID)
		else:
			state.add_fileID(skelley.godot_skeleton, fileID)
			state.add_fileID(skelley.godot_skeleton, transform.fileID)
		if ret != null:
			var list_of_skelleys: Array = state.skelley_parents.get(transform.uniq_key, [])
			for new_skelley in list_of_skelleys:
				ret.add_child(new_skelley.godot_skeleton)
				new_skelley.godot_skeleton.owner = state.owner

		var skip_first: bool = true

		for component_ref in components:
			if skip_first:
				#Is it a fair assumption that Transform is always the first component???
				skip_first = false
			else:
				assert(ret != null)
				var component = meta.lookup(component_ref.get("component"))
				component.create_godot_node(state, ret)

		for child_ref in transform.children_refs:
			var child_transform = meta.lookup(child_ref)
			var child_game_object = child_transform.gameObject
			var new_skelley: Skelley = state.uniq_key_to_skelley.get(child_transform.uniq_key, null)
			if new_skelley != null:
				child_game_object.create_skeleton_bone(state, new_skelley)
			else:
				assert(ret != null)
				child_game_object.create_godot_node(state, ret)

	func create_godot_node(xstate: GodotNodeState, new_parent: Node3D) -> Node3D:
		var state: Object = xstate
		var ret: Node3D = null
		var components: Array = self.components
		var has_collider: bool = false
		var extra_fileID: Array = [fileID]
		var transform: UnityTransform = self.transform

		for component_ref in components:
			var component = meta.lookup(component_ref.get("component"))
			# Some components take priority and must be created here.
			if component.type == "Rigidbody":
				ret = component.create_physics_body(state, new_parent, name)
				ret.transform = transform.godot_transform
				extra_fileID.push_back(transform.fileID)
				state = state.state_with_body(ret as CollisionObject3D)
			if component.is_collider:
				extra_fileID.push_back(component.fileID)
				has_collider = true
		if has_collider and (state.body == null or state.body.get_class().begins_with("StaticBody")):
			ret = StaticBody3D.new()
		else:
			ret = Node3D.new()
		ret.name = name
		state.add_child(ret, new_parent, transform.fileID)
		ret.transform = transform.godot_transform
		state = state.state_with_body(ret as StaticBody3D)
		if new_parent == null:
			# We are the root (of a Prefab). Become the owner.
			state = state.state_with_owner(ret)
		for ext in extra_fileID:
			state.add_fileID(ret, ext)
		var skip_first: bool = true

		for component_ref in components:
			if skip_first:
				#Is it a fair assumption that Transform is always the first component???
				skip_first = false
			else:
				var component = meta.lookup(component_ref.get("component"))
				component.create_godot_node(state, ret)

		print("Look for a skeleton at " + transform.uniq_key + " in " + str(state.skelley_parents.keys()))
		var list_of_skelleys: Array = state.skelley_parents.get(transform.uniq_key, [])
		for new_skelley in list_of_skelleys:
			print("Found skeleton at " + transform.uniq_key +" : " + str(new_skelley))
			ret.add_child(new_skelley.godot_skeleton)
			new_skelley.godot_skeleton.owner = state.owner

		for child_ref in transform.children_refs:
			var child_transform = meta.lookup(child_ref)
			var child_game_object = child_transform.gameObject
			var new_skelley: Skelley = state.uniq_key_to_skelley.get(child_transform.uniq_key, null)
			if new_skelley != null:
				child_game_object.create_skeleton_bone(state, new_skelley)
			else:
				child_game_object.create_godot_node(state, ret)

		return ret

	var components: Array:
		get:
			return keys.get("m_Component")

	var transform: UnityTransform:
		get:
			return meta.lookup(components[0].get("component"))

	var meshFilter: UnityMeshFilter:
		get:
			for component_ref in components:
				var component = meta.lookup(component_ref.get("component"))
				if component.type == "MeshFilter":
					return component

	var rigidbody: UnityRigidbody:
		get:
			for component_ref in components:
				var component = meta.lookup(component_ref.get("component"))
				if component.type == "Rigidbody":
					return component

	var toplevel: bool:
		get:
			return transform.parent == null


### ================ COMPONENT TYPES ================
class UnityComponent extends UnityObject:
	func create_godot_node(state: GodotNodeState, new_parent: Node3D) -> Node:
		var new_node: Node = Node.new()
		new_node.name = type
		state.add_child(new_node, new_parent, fileID)
		new_node.editor_description = str(self)
		return new_node

	var gameObject: UnityGameObject:
		get:
			return meta.lookup(keys.get("m_GameObject"))

	var name: String:
		get:
			return gameObject.name

	var enabled: bool:
		get:
			return true

	var toplevel: bool:
		get:
			return false

class UnityBehaviour extends UnityComponent:
	var enabled: bool:
		get:
			return keys.get("m_Enabled", true)

class UnityTransform extends UnityComponent:
	func create_godot_node(state: GodotNodeState, new_parent: Node3D) -> Node3D:
		var new_node: Node3D = Node3D.new()
		state.add_child(new_node, new_parent, fileID)
		new_node.transform = godot_transform
		return new_node

	var localPosition: Vector3:
		get:
			return keys.get("m_LocalPosition", Vector3(1,2,3))

	var localRotation: Quat:
		get:
			return keys.get("m_LocalRotation", Quat(0.1,0.2,0.3,0.4))

	var localScale: Vector3:
		get:
			var scale = keys.get("m_LocalScale", Vector3(0.4,0.6,0.8))
			if scale.x > -1e-7 && scale.x < 1e-7:
				scale.x = 1e-7
			if scale.y > -1e-7 && scale.y < 1e-7:
				scale.y = 1e-7
			if scale.z > -1e-7 && scale.z < 1e-7:
				scale.z = 1e-7
			return scale

	var godot_transform: Transform:
		get:
			return Transform(Basis(localRotation).scaled(localScale), localPosition)

	var rootOrder: int:
		get:
			return keys.get("m_RootOrder", 0)

	var parent: UnityTransform:
		get:
			return meta.lookup(keys.get("m_Father"))

	var children_refs: Array:
		get:
			return keys.get("m_Children")

class UnityRectTransform extends UnityTransform:
	pass

class UnityCollider extends UnityBehaviour:
	func create_godot_node(state: GodotNodeState, new_parent: Node3D) -> Node:
		var new_node: CollisionShape3D = CollisionShape3D.new()
		state.add_child(new_node, state.body, fileID)
		var cur_node = new_parent
		var xform = Transform(self.basis, self.center)
		while cur_node != state.body:
			xform = cur_node.transform * xform
			cur_node = cur_node.parent
		new_node.transform = xform
		new_node.shape = self.shape
		new_node.name = self.type
		return new_node

	var center: Vector3:
		get:
			return keys.get("m_Center", Vector3(0.0, 0.0, 0.0))

	var basis: Basis:
		get:
			return Basis(Vector3(0.0, 0.0, 0.0))

	var shape: Shape3D:
		get:
			return null

	var is_collider: bool:
		get:
			return true

class UnityBoxCollider extends UnityCollider:
	var shape: Shape3D:
		get:
			var bs: BoxShape3D = BoxShape3D.new()
			bs.size = size
			return bs

	var size: Vector3:
		get:
			return keys.get("m_Size")


class UnitySphereCollider extends UnityCollider:
	var shape: Shape3D:
		get:
			var bs: SphereShape3D = SphereShape3D.new()
			bs.radius = radius
			return bs

	var radius: float:
		get:
			return keys.get("m_Radius")

class UnityCapsuleCollider extends UnityCollider:
	var shape: Shape3D:
		get:
			var bs: CapsuleShape3D = CapsuleShape3D.new()
			bs.radius = radius
			var adj_height: float = height - 2 * bs.radius
			if adj_height < 0.0:
				adj_height = 0.0
			bs.height = adj_height
			return bs

	var basis: Basis:
		get:
			if direction == 0: # Along the X-Axis
				return Basis(Vector3(0.0, 0.0, PI/2.0))
			if direction == 1: # Along the Y-Axis (Godot default)
				return Basis(Vector3(0.0, 0.0, 0.0))
			if direction == 2: # Along the Z-Axis
				return Basis(Vector3(PI/2.0, 0.0, 0.0))

	var direction: int:
		get:
			return keys.get("m_Direction") # 0, 1 or 2

	var radius: float:
		get:
			return keys.get("m_Radius")

	var height: float:
		get:
			return keys.get("m_Height")

class UnityMeshCollider extends UnityCollider:

	var convex: Shape3D:
		get:
			return keys.get("m_Convex")

	var shape: Shape3D:
		get:
			if convex:
				return meta.get_godot_resource(mesh).create_convex_shape()
			else:
				return meta.get_godot_resource(mesh).create_trimesh_shape()
		
	var mesh: Array: # UnityRef
		get:
			var ret = keys.get("m_Mesh")
			if ret == null:
				var mf: UnityMeshFilter = gameObject.meshFilter
				if mf != null:
					return gameObject.meshFilter.mesh
			return ret

class UnityRigidbody extends UnityComponent:

	func create_godot_node(state: GodotNodeState, new_parent: Node3D) -> Node:
		return null

	func create_physics_body(state: GodotNodeState, new_parent: Node3D, name: String) -> Node:
		var new_node: Node3D;
		if isKinematic:
			var kinematic: KinematicBody3D = KinematicBody3D.new()
			new_node = kinematic
		else:
			var rigid: RigidBody3D = RigidBody3D.new()
			new_node = rigid

		new_node.name = name # Not type: This replaces the usual transform node.
		state.add_child(new_node, new_parent, fileID)
		return new_node

	func create_physical_bone(state, skelley, name):
		var new_node: PhysicalBone3D = PhysicalBone3D.new()
		new_node.bone_name = name
		new_node.name = name
		state.add_child(new_node, skelley.godot_skeleton, fileID)
		return new_node

	var isKinematic: bool:
		get:
			return keys.get("m_IsKinematic") != 0


class UnityMeshFilter extends UnityComponent:
	func create_godot_node(state: GodotNodeState, new_parent: Node3D) -> Node:
		return null
		
	var mesh: Array: # UnityRef
		get:
			return keys.get("m_Mesh")

class UnityRenderer extends UnityBehaviour:
	pass

class UnityMeshRenderer extends UnityRenderer:
	func create_godot_node(state: GodotNodeState, new_parent: Node3D) -> Node:
		return create_godot_node_orig(state, new_parent)

	func create_godot_node_orig(state: GodotNodeState, new_parent: Node3D) -> Node:
		var new_node: MeshInstance3D = MeshInstance3D.new()
		new_node.name = type
		state.add_child(new_node, new_parent, fileID)
		new_node.editor_description = str(self)
		new_node.mesh = meta.get_godot_resource(self.mesh)

		var mf: UnityMeshFilter = gameObject.meshFilter
		if mf != null:
			state.add_fileID(new_node, mf.fileID)

		return new_node
		
	var mesh: Array: # UnityRef
		get:
			var mf: UnityMeshFilter = gameObject.meshFilter
			if mf != null:
				return mf.mesh
			return null

class UnitySkinnedMeshRenderer extends UnityMeshRenderer:

	func create_godot_node(state: GodotNodeState, new_parent: Node3D) -> Node:
		if len(bones) == 0:
			return create_godot_node_orig(state, new_parent)
		else:

			print("input bone key: " + str(bones[0]) + "/" + str(meta))
			print("input bone key: " + str(bones[0]) + "DD" + str(state.meta))
			print("input bone key: " + str(bones[0]) + "/" + str(meta) + "_" + str(meta.lookup))
			print("input bone key: " + str(bones[0]) + "/" + str(meta) + "_" + str(state.meta.lookup))
			var first_bone_key: String = meta.lookup(bones[0]).uniq_key
			print("Resulting bone key: " + str(first_bone_key))
			var ret: MeshInstance3D = create_godot_node_orig(state, state.uniq_key_to_skelley.get(first_bone_key).godot_skeleton)
			# ret.skeleton = NodePath("..") # default?
			# skin??
			return ret

	var bones: Array:
		get:
			return keys.get("m_Bones")

	var mesh: Array: # UnityRef
		get:
			return keys.get("m_Mesh")

class UnityLight extends UnityBehaviour:
	func create_godot_node(state: GodotNodeState, new_parent: Node3D) -> Node:
		var light: Light3D
		var unityLightType = lightType
		if unityLightType == 0:
			# Assuming default cookie
			# Assuming Legacy pipeline:
			# Scriptable Rendering Pipeline: shape and innerSpotAngle not supported.
			# Assuming RenderSettings.m_SpotCookie: == {fileID: 10001, guid: 0000000000000000e000000000000000, type: 0}
			var spot_light: SpotLight3D = SpotLight3D.new()
			spot_light.set_param(Light3D.PARAM_SPOT_ANGLE, spotAngle)
			spot_light.set_param(Light3D.PARAM_SPOT_ATTENUATION, 0.25) # Eyeball guess for Unity's default spotlight texture
			spot_light.set_param(Light3D.PARAM_ATTENUATION, 1.0)
			spot_light.set_param(Light3D.PARAM_RANGE, lightRange)
			light = spot_light
		elif unityLightType == 1:
			# depth_range? max_disatance? blend_splits? bias_split_scale?
			#keys.get("m_ShadowNearPlane")
			var dir_light: DirectionalLight3D = DirectionalLight3D.new()
			dir_light.set_param(Light3D.PARAM_SHADOW_NORMAL_BIAS, shadowNormalBias)
			light = dir_light
		elif unityLightType == 2:
			var omni_light: OmniLight3D = OmniLight3D.new()
			light = omni_light
			omni_light.set_param(Light3D.PARAM_ATTENUATION, 1.0)
			omni_light.set_param(Light3D.PARAM_RANGE, lightRange)
		elif unityLightType == 3:
			printerr("Rectangle Area Light not supported!")
			# areaSize?
			return UnityBehaviour.create_godot_node(state, new_parent)
		elif unityLightType == 4:
			printerr("Disc Area Light not supported!")
			return UnityBehaviour.create_godot_node(state, new_parent)

		# TODO: Layers
		if keys.get("useColorTemperature"):
			printerr("Color Temperature not implemented.")
		light.name = type
		state.add_child(light, new_parent, fileID)
		light.transform = Transform(Basis(Vector3(0.0, PI, 0.0)))
		light.light_color = color
		light.set_param(Light3D.PARAM_ENERGY, intensity)
		light.set_param(Light3D.PARAM_INDIRECT_ENERGY, bounceIntensity)
		light.shadow_enabled = shadowType != 0
		light.set_param(Light3D.PARAM_SHADOW_BIAS, shadowBias)
		if lightmapBakeType == 1:
			light.light_bake_mode = Light3D.BAKE_INDIRECT
		elif lightmapBakeType == 2:
			light.light_bake_mode == Light3D.BAKE_ALL
			light.editor_only = true
		else:
			light.light_bake_mode == Light3D.BAKE_DISABLED
		return light
	
	var color: Color:
		get:
			return keys.get("m_Color")
	
	var lightType: float:
		get:
			return keys.get("m_Type")
	
	var lightRange: float:
		get:
			return keys.get("m_Range")

	var intensity: float:
		get:
			return keys.get("m_Intensity")
	
	var bounceIntensity: float:
		get:
			return keys.get("m_BounceIntensity")
	
	var spotAngle: float:
		get:
			return keys.get("m_SpotAngle")

	var lightmapBakeType: int:
		get:
			return keys.get("m_Lightmapping")

	var shadowType: int:
		get:
			return keys.get("m_Shadows").get("m_Type")

	var shadowBias: float:
		get:
			return keys.get("m_Shadows").get("m_Bias")

	var shadowNormalBias: float:
		get:
			return keys.get("m_Shadows").get("m_NormalBias")


### ================ IMPORTER TYPES ================
class UnityAssetImporter extends UnityObject:
	var main_object_id: int:
		get:
			return 0 # Unknown

	func get_external_objects() -> Dictionary:
		var eo: Dictionary = {}.duplicate()
		for srcAssetIdent in keys.get("externalObjects", []):
			var type_str: String = srcAssetIdent.get("first", {}).get("type","")
			var type_key: String = type_str.split(":")[-1]
			var key: String = srcAssetIdent.get("first", {}).get("name","")
			var val: Array = srcAssetIdent.get("second", {}) # UnityRef
			if key != "" and type_str.begins_with("UnityEngine"):
				if not eo.has(type_key):
					eo[type_key] = {}.duplicate()
				eo[type_key][key] = val
		return eo


class UnityModelImporter extends UnityAssetImporter:

	var addCollider: bool:
		get:
			return keys.get("meshes").get("addCollider") == 1

	func get_animation_clips() -> Array:
		var unityClips = keys.get("animations").get("clipAnimations", [])
		var outClips = [].duplicate()
		for unityClip in unityClips:
			var clip = {}.duplicate()
			outClips.push_back(clip)
			clip["name"] = unityClip.get("name", "")
			clip["start_frame"] = unityClip.get("firstFrame", 0.0)
			clip["end_frame"] = unityClip.get("lastFrame", 0.0)
			# "loop" also exists but appears to be unused at least
			clip["loops"] = unityClip.get("loopTime", 0) != 0
			# TODO: Root motion?
			#cycleOffset: -0
			#loop: 0
			#hasAdditiveReferencePose: 0
			#loopTime: 1
			#loopBlend: 1
			#loopBlendOrientation: 0
			#loopBlendPositionY: 1
			#loopBlendPositionXZ: 0
			#keepOriginalOrientation: 0
			#keepOriginalPositionY: 0
			#keepOriginalPositionXZ: 0
			# TODO: Humanoid retargeting?
			# humanDescription:
			#   serializedVersion: 2
			#   human:
			#   - boneName: RightUpLeg
			#     humanName: RightUpperLeg
		return outClips

	var meshes_light_baking: int:
		get:
			# Godot uses: Disabled,Enabled,GenLightmaps
			return keys.get("meshes").get("generateSecondaryUV") * 2

	var meshes_root_scale: float:
		get:
			return keys.get("meshes").get("globalScale") == 1

	var animation_import: bool:
		# legacyGenerateAnimations = 4 ??
		# animationType = 3 ??
		get:
			return (keys.get("importAnimation") and
				keys.get("animationType") != 0)

	var fileIDToRecycleName: Dictionary:
		get:
			return keys.get("fileIDToRecycleName", {})

	# 0: No compression; 1: keyframe reduction; 2: keyframe reduction and compress
	# 3: all of the above and choose best curve for runtime memory.
	func animation_optimizer_settings() -> Dictionary:
		var rotError: float = keys.get("animations").get("animationRotationError", 0.5) # Degrees
		var rotErrorHalfRevs: float = rotError / 180 # p_alowed_angular_err is defined this way (divides by PI)
		return {
			"enabled": keys.get("animations").get("animationCompression") != 0,
			"max_linear_error": keys.get("animations").get("animationPositionError", 0.5),
			"max_angular_error": rotErrorHalfRevs, # Godot defaults this value to 
		}

	var main_object_id: int:
		get:
			return 100100000 # a model is a type of Prefab

class UnityShaderImporter extends UnityAssetImporter:
	var main_object_id: int:
		get:
			return 4800000 # Shader

class UnityTextureImporter extends UnityAssetImporter:
	var textureShape: int:
		get:
			# 1: Texture2D
			# 2: Cubemap
			# 3: Texture2DArray (Unity 2020)
			# 4: Texture3D (Unity 2020)
			return keys.get("textureShape", 0) # Some old files do not have this

	# TODO: implement textureType. Currently unused
	var textureType: int:
		get:
			# -1: Unknown
			# 0: Default
			# 1: NormalMap
			# 2: GUI
			# 3: Sprite
			# ...
			# bumpmap.convertToNormalMap?
			return keys.get("textureType", 0)

	var main_object_id: int:
		# Note: some textureType will add a Sprite or other asset as well.
		get:
			match textureShape:
				0, 1:
					return 2800000 # "Texture2D",
				2:
					return 8900000 # "Cubemap",
				3:
					return 18700000 # "Texture2DArray",
				4:
					return 11700000 # "Texture3D",
				_:
					return 0

class UnityTrueTypeFontImporter extends UnityAssetImporter:
	var main_object_id: int:
		get:
			return 12800000 # Font

class UnityNativeFormatImporter extends UnityAssetImporter:
	var main_object_id: int:
		get:
			return keys.get("mainObjectFileID", 0)

class UnityPrefabImporter extends UnityAssetImporter:
	var main_object_id: int:
		get:
			# PrefabInstance is 1001. Multiply by 100000 to create default ID.
			return 100100000 # Always should be this ID.

class UnityTextScriptImporter extends UnityAssetImporter:
	var main_object_id: int:
		get:
			return 4900000 # TextAsset

class UnityAudioImporter extends UnityAssetImporter:
	var main_object_id: int:
		get:
			return 8300000 # AudioClip

class UnityDefaultImporter extends UnityAssetImporter:
	# Will depend on filetype or file extension?
	# Check file extension from `meta.path`???
	var main_object_id: int:
		get:
			match meta.path.get_extension():
				"unity":
					# Scene file.
					# 1: OcclusionCullingSettings (29),
					# 2: RenderSettings (104),
					# 3: LightmapSettings (157),
					# 4: NavMeshSettings (196),
					# We choose 1 to represent the default id, but there is no actual root node.
					return 1
				"txt", "html", "htm", "xml", "bytes", "json", "csv", "yaml", "fnt":
					# Supported file extensions for text (.bytes is special)
					return 4900000 # TextAsset
				_:
					# Folder, or unsupported type.
					return 102900000 # DefaultAsset

var _type_dictionary: Dictionary = {
	# "AimConstraint": UnityAimConstraint,
	# "AnchoredJoint2D": UnityAnchoredJoint2D,
	# "Animation": UnityAnimation,
	"AnimationClip": UnityAnimationClip,
	# "Animator": UnityAnimator,
	# "AnimatorController": UnityAnimatorController,
	# "AnimatorOverrideController": UnityAnimatorOverrideController,
	# "AnimatorState": UnityAnimatorState,
	# "AnimatorStateMachine": UnityAnimatorStateMachine,
	# "AnimatorStateTransition": UnityAnimatorStateTransition,
	# "AnimatorTransition": UnityAnimatorTransition,
	# "AnimatorTransitionBase": UnityAnimatorTransitionBase,
	# "AnnotationManager": UnityAnnotationManager,
	# "AreaEffector2D": UnityAreaEffector2D,
	# "AssemblyDefinitionAsset": UnityAssemblyDefinitionAsset,
	# "AssemblyDefinitionImporter": UnityAssemblyDefinitionImporter,
	# "AssemblyDefinitionReferenceAsset": UnityAssemblyDefinitionReferenceAsset,
	# "AssemblyDefinitionReferenceImporter": UnityAssemblyDefinitionReferenceImporter,
	# "AssetBundle": UnityAssetBundle,
	# "AssetBundleManifest": UnityAssetBundleManifest,
	# "AssetDatabaseV1": UnityAssetDatabaseV1,
	"AssetImporter": UnityAssetImporter,
	# "AssetImporterLog": UnityAssetImporterLog,
	# "AssetImportInProgressProxy": UnityAssetImportInProgressProxy,
	# "AssetMetaData": UnityAssetMetaData,
	# "AudioBehaviour": UnityAudioBehaviour,
	# "AudioBuildInfo": UnityAudioBuildInfo,
	# "AudioChorusFilter": UnityAudioChorusFilter,
	# "AudioClip": UnityAudioClip,
	# "AudioDistortionFilter": UnityAudioDistortionFilter,
	# "AudioEchoFilter": UnityAudioEchoFilter,
	# "AudioFilter": UnityAudioFilter,
	# "AudioHighPassFilter": UnityAudioHighPassFilter,
	# "AudioImporter": UnityAudioImporter,
	# "AudioListener": UnityAudioListener,
	# "AudioLowPassFilter": UnityAudioLowPassFilter,
	# "AudioManager": UnityAudioManager,
	# "AudioMixer": UnityAudioMixer,
	# "AudioMixerController": UnityAudioMixerController,
	# "AudioMixerEffectController": UnityAudioMixerEffectController,
	# "AudioMixerGroup": UnityAudioMixerGroup,
	# "AudioMixerGroupController": UnityAudioMixerGroupController,
	# "AudioMixerLiveUpdateBool": UnityAudioMixerLiveUpdateBool,
	# "AudioMixerLiveUpdateFloat": UnityAudioMixerLiveUpdateFloat,
	# "AudioMixerSnapshot": UnityAudioMixerSnapshot,
	# "AudioMixerSnapshotController": UnityAudioMixerSnapshotController,
	# "AudioReverbFilter": UnityAudioReverbFilter,
	# "AudioReverbZone": UnityAudioReverbZone,
	# "AudioSource": UnityAudioSource,
	# "Avatar": UnityAvatar,
	# "AvatarMask": UnityAvatarMask,
	# "BaseAnimationTrack": UnityBaseAnimationTrack,
	# "BaseVideoTexture": UnityBaseVideoTexture,
	"Behaviour": UnityBehaviour,
	# "BillboardAsset": UnityBillboardAsset,
	# "BillboardRenderer": UnityBillboardRenderer,
	# "BlendTree": UnityBlendTree,
	"BoxCollider": UnityBoxCollider,
	# "BoxCollider2D": UnityBoxCollider2D,
	# "BuildReport": UnityBuildReport,
	# "BuildSettings": UnityBuildSettings,
	# "BuiltAssetBundleInfoSet": UnityBuiltAssetBundleInfoSet,
	# "BuoyancyEffector2D": UnityBuoyancyEffector2D,
	# "CachedSpriteAtlas": UnityCachedSpriteAtlas,
	# "CachedSpriteAtlasRuntimeData": UnityCachedSpriteAtlasRuntimeData,
	# "Camera": UnityCamera,
	# "Canvas": UnityCanvas,
	# "CanvasGroup": UnityCanvasGroup,
	# "CanvasRenderer": UnityCanvasRenderer,
	"CapsuleCollider": UnityCapsuleCollider,
	# "CapsuleCollider2D": UnityCapsuleCollider2D,
	# "CGProgram": UnityCGProgram,
	# "CharacterController": UnityCharacterController,
	# "CharacterJoint": UnityCharacterJoint,
	# "CircleCollider2D": UnityCircleCollider2D,
	# "Cloth": UnityCloth,
	# "ClusterInputManager": UnityClusterInputManager,
	"Collider": UnityCollider,
	# "Collider2D": UnityCollider2D,
	# "Collision": UnityCollision,
	# "Collision2D": UnityCollision2D,
	"Component": UnityComponent,
	# "CompositeCollider2D": UnityCompositeCollider2D,
	# "ComputeShader": UnityComputeShader,
	# "ComputeShaderImporter": UnityComputeShaderImporter,
	# "ConfigurableJoint": UnityConfigurableJoint,
	# "ConstantForce": UnityConstantForce,
	# "ConstantForce2D": UnityConstantForce2D,
	"Cubemap": UnityCubemap,
	"CubemapArray": UnityCubemapArray,
	"CustomRenderTexture": UnityCustomRenderTexture,
	# "DefaultAsset": UnityDefaultAsset,
	"DefaultImporter": UnityDefaultImporter,
	# "DelayedCallManager": UnityDelayedCallManager,
	# "Derived": UnityDerived,
	# "DistanceJoint2D": UnityDistanceJoint2D,
	# "EdgeCollider2D": UnityEdgeCollider2D,
	# "EditorBuildSettings": UnityEditorBuildSettings,
	# "EditorExtension": UnityEditorExtension,
	# "EditorExtensionImpl": UnityEditorExtensionImpl,
	# "EditorProjectAccess": UnityEditorProjectAccess,
	# "EditorSettings": UnityEditorSettings,
	# "EditorUserBuildSettings": UnityEditorUserBuildSettings,
	# "EditorUserSettings": UnityEditorUserSettings,
	# "Effector2D": UnityEffector2D,
	# "EmptyObject": UnityEmptyObject,
	# "FakeComponent": UnityFakeComponent,
	# "FBXImporter": UnityFBXImporter,
	# "FixedJoint": UnityFixedJoint,
	# "FixedJoint2D": UnityFixedJoint2D,
	# "Flare": UnityFlare,
	# "FlareLayer": UnityFlareLayer,
	# "float": Unityfloat,
	# "Font": UnityFont,
	# "FrictionJoint2D": UnityFrictionJoint2D,
	# "GameManager": UnityGameManager,
	"GameObject": UnityGameObject,
	# "GameObjectRecorder": UnityGameObjectRecorder,
	# "GlobalGameManager": UnityGlobalGameManager,
	# "GraphicsSettings": UnityGraphicsSettings,
	# "Grid": UnityGrid,
	# "GridLayout": UnityGridLayout,
	# "Halo": UnityHalo,
	# "HaloLayer": UnityHaloLayer,
	# "HierarchyState": UnityHierarchyState,
	# "HingeJoint": UnityHingeJoint,
	# "HingeJoint2D": UnityHingeJoint2D,
	# "HumanTemplate": UnityHumanTemplate,
	# "IConstraint": UnityIConstraint,
	# "IHVImageFormatImporter": UnityIHVImageFormatImporter,
	# "InputManager": UnityInputManager,
	# "InspectorExpandedState": UnityInspectorExpandedState,
	# "Joint": UnityJoint,
	# "Joint2D": UnityJoint2D,
	# "LensFlare": UnityLensFlare,
	# "LevelGameManager": UnityLevelGameManager,
	# "LibraryAssetImporter": UnityLibraryAssetImporter,
	"Light": UnityLight,
	# "LightingDataAsset": UnityLightingDataAsset,
	# "LightingDataAssetParent": UnityLightingDataAssetParent,
	# "LightmapParameters": UnityLightmapParameters,
	# "LightmapSettings": UnityLightmapSettings,
	# "LightProbeGroup": UnityLightProbeGroup,
	# "LightProbeProxyVolume": UnityLightProbeProxyVolume,
	# "LightProbes": UnityLightProbes,
	# "LineRenderer": UnityLineRenderer,
	# "LocalizationAsset": UnityLocalizationAsset,
	# "LocalizationImporter": UnityLocalizationImporter,
	# "LODGroup": UnityLODGroup,
	# "LookAtConstraint": UnityLookAtConstraint,
	# "LowerResBlitTexture": UnityLowerResBlitTexture,
	"Material": UnityMaterial,
	"Mesh": UnityMesh,
	# "Mesh3DSImporter": UnityMesh3DSImporter,
	"MeshCollider": UnityMeshCollider,
	"MeshFilter": UnityMeshFilter,
	"MeshRenderer": UnityMeshRenderer,
	"ModelImporter": UnityModelImporter,
	# "MonoBehaviour": UnityMonoBehaviour,
	# "MonoImporter": UnityMonoImporter,
	# "MonoManager": UnityMonoManager,
	# "MonoObject": UnityMonoObject,
	# "MonoScript": UnityMonoScript,
	# "Motion": UnityMotion,
	# "NamedObject": UnityNamedObject,
	"NativeFormatImporter": UnityNativeFormatImporter,
	# "NativeObjectType": UnityNativeObjectType,
	# "NavMeshAgent": UnityNavMeshAgent,
	# "NavMeshData": UnityNavMeshData,
	# "NavMeshObstacle": UnityNavMeshObstacle,
	# "NavMeshProjectSettings": UnityNavMeshProjectSettings,
	# "NavMeshSettings": UnityNavMeshSettings,
	# "NewAnimationTrack": UnityNewAnimationTrack,
	"Object": UnityObject,
	# "OcclusionArea": UnityOcclusionArea,
	# "OcclusionCullingData": UnityOcclusionCullingData,
	# "OcclusionCullingSettings": UnityOcclusionCullingSettings,
	# "OcclusionPortal": UnityOcclusionPortal,
	# "OffMeshLink": UnityOffMeshLink,
	# "PackageManifest": UnityPackageManifest,
	# "PackageManifestImporter": UnityPackageManifestImporter,
	# "PackedAssets": UnityPackedAssets,
	# "ParentConstraint": UnityParentConstraint,
	# "ParticleSystem": UnityParticleSystem,
	# "ParticleSystemForceField": UnityParticleSystemForceField,
	# "ParticleSystemRenderer": UnityParticleSystemRenderer,
	# "PhysicMaterial": UnityPhysicMaterial,
	# "Physics2DSettings": UnityPhysics2DSettings,
	# "PhysicsManager": UnityPhysicsManager,
	# "PhysicsMaterial2D": UnityPhysicsMaterial2D,
	# "PhysicsUpdateBehaviour2D": UnityPhysicsUpdateBehaviour2D,
	# "PlatformEffector2D": UnityPlatformEffector2D,
	# "PlatformModuleSetup": UnityPlatformModuleSetup,
	# "PlayableDirector": UnityPlayableDirector,
	# "PlayerSettings": UnityPlayerSettings,
	# "PluginBuildInfo": UnityPluginBuildInfo,
	# "PluginImporter": UnityPluginImporter,
	# "PointEffector2D": UnityPointEffector2D,
	# "Polygon2D": UnityPolygon2D,
	# "PolygonCollider2D": UnityPolygonCollider2D,
	# "PositionConstraint": UnityPositionConstraint,
	# "Prefab": UnityPrefab,
	"PrefabImporter": UnityPrefabImporter,
	# "PrefabInstance": UnityPrefabInstance,
	# "PreloadData": UnityPreloadData,
	# "Preset": UnityPreset,
	# "PresetManager": UnityPresetManager,
	# "Projector": UnityProjector,
	# "QualitySettings": UnityQualitySettings,
	# "RayTracingShader": UnityRayTracingShader,
	# "RayTracingShaderImporter": UnityRayTracingShaderImporter,
	"RectTransform": UnityRectTransform,
	# "ReferencesArtifactGenerator": UnityReferencesArtifactGenerator,
	# "ReflectionProbe": UnityReflectionProbe,
	# "RelativeJoint2D": UnityRelativeJoint2D,
	"Renderer": UnityRenderer,
	# "RendererFake": UnityRendererFake,
	# "RenderSettings": UnityRenderSettings,
	"RenderTexture": UnityRenderTexture,
	# "ResourceManager": UnityResourceManager,
	"Rigidbody": UnityRigidbody,
	# "Rigidbody2D": UnityRigidbody2D,
	# "RootMotionData": UnityRootMotionData,
	# "RotationConstraint": UnityRotationConstraint,
	# "RuntimeAnimatorController": UnityRuntimeAnimatorController,
	# "RuntimeInitializeOnLoadManager": UnityRuntimeInitializeOnLoadManager,
	# "SampleClip": UnitySampleClip,
	# "ScaleConstraint": UnityScaleConstraint,
	# "SceneAsset": UnitySceneAsset,
	# "SceneVisibilityState": UnitySceneVisibilityState,
	# "ScriptedImporter": UnityScriptedImporter,
	# "ScriptMapper": UnityScriptMapper,
	# "SerializableManagedHost": UnitySerializableManagedHost,
	# "Shader": UnityShader,
	"ShaderImporter": UnityShaderImporter,
	# "ShaderVariantCollection": UnityShaderVariantCollection,
	# "SiblingDerived": UnitySiblingDerived,
	# "SketchUpImporter": UnitySketchUpImporter,
	"SkinnedMeshRenderer": UnitySkinnedMeshRenderer,
	# "Skybox": UnitySkybox,
	# "SliderJoint2D": UnitySliderJoint2D,
	# "SortingGroup": UnitySortingGroup,
	# "SparseTexture": UnitySparseTexture,
	# "SpeedTreeImporter": UnitySpeedTreeImporter,
	# "SpeedTreeWindAsset": UnitySpeedTreeWindAsset,
	"SphereCollider": UnitySphereCollider,
	# "SpringJoint": UnitySpringJoint,
	# "SpringJoint2D": UnitySpringJoint2D,
	# "Sprite": UnitySprite,
	# "SpriteAtlas": UnitySpriteAtlas,
	# "SpriteAtlasDatabase": UnitySpriteAtlasDatabase,
	# "SpriteMask": UnitySpriteMask,
	# "SpriteRenderer": UnitySpriteRenderer,
	# "SpriteShapeRenderer": UnitySpriteShapeRenderer,
	# "StreamingController": UnityStreamingController,
	# "StreamingManager": UnityStreamingManager,
	# "SubDerived": UnitySubDerived,
	# "SubstanceArchive": UnitySubstanceArchive,
	# "SubstanceImporter": UnitySubstanceImporter,
	# "SurfaceEffector2D": UnitySurfaceEffector2D,
	# "TagManager": UnityTagManager,
	# "TargetJoint2D": UnityTargetJoint2D,
	# "Terrain": UnityTerrain,
	# "TerrainCollider": UnityTerrainCollider,
	# "TerrainData": UnityTerrainData,
	# "TerrainLayer": UnityTerrainLayer,
	# "TextAsset": UnityTextAsset,
	# "TextMesh": UnityTextMesh,
	"TextScriptImporter": UnityTextScriptImporter,
	"Texture": UnityTexture,
	"Texture2D": UnityTexture2D,
	"Texture2DArray": UnityTexture2DArray,
	"Texture3D": UnityTexture3D,
	"TextureImporter": UnityTextureImporter,
	# "Tilemap": UnityTilemap,
	# "TilemapCollider2D": UnityTilemapCollider2D,
	# "TilemapRenderer": UnityTilemapRenderer,
	# "TimeManager": UnityTimeManager,
	# "TrailRenderer": UnityTrailRenderer,
	"Transform": UnityTransform,
	# "Tree": UnityTree,
	"TrueTypeFontImporter": UnityTrueTypeFontImporter,
	# "UnityConnectSettings": UnityUnityConnectSettings,
	# "Vector3f": UnityVector3f,
	# "VFXManager": UnityVFXManager,
	# "VFXRenderer": UnityVFXRenderer,
	# "VideoClip": UnityVideoClip,
	# "VideoClipImporter": UnityVideoClipImporter,
	# "VideoPlayer": UnityVideoPlayer,
	# "VisualEffect": UnityVisualEffect,
	# "VisualEffectAsset": UnityVisualEffectAsset,
	# "VisualEffectImporter": UnityVisualEffectImporter,
	# "VisualEffectObject": UnityVisualEffectObject,
	# "VisualEffectResource": UnityVisualEffectResource,
	# "VisualEffectSubgraph": UnityVisualEffectSubgraph,
	# "VisualEffectSubgraphBlock": UnityVisualEffectSubgraphBlock,
	# "VisualEffectSubgraphOperator": UnityVisualEffectSubgraphOperator,
	# "WebCamTexture": UnityWebCamTexture,
	# "WheelCollider": UnityWheelCollider,
	# "WheelJoint2D": UnityWheelJoint2D,
	# "WindZone": UnityWindZone,
	# "WorldAnchor": UnityWorldAnchor,
}

var utype_to_classname = {
	0: "Object",
	1: "GameObject",
	2: "Component",
	3: "LevelGameManager",
	4: "Transform",
	5: "TimeManager",
	6: "GlobalGameManager",
	8: "Behaviour",
	9: "GameManager",
	11: "AudioManager",
	13: "InputManager",
	18: "EditorExtension",
	19: "Physics2DSettings",
	20: "Camera",
	21: "Material",
	23: "MeshRenderer",
	25: "Renderer",
	27: "Texture",
	28: "Texture2D",
	29: "OcclusionCullingSettings",
	30: "GraphicsSettings",
	33: "MeshFilter",
	41: "OcclusionPortal",
	43: "Mesh",
	45: "Skybox",
	47: "QualitySettings",
	48: "Shader",
	49: "TextAsset",
	50: "Rigidbody2D",
	53: "Collider2D",
	54: "Rigidbody",
	55: "PhysicsManager",
	56: "Collider",
	57: "Joint",
	58: "CircleCollider2D",
	59: "HingeJoint",
	60: "PolygonCollider2D",
	61: "BoxCollider2D",
	62: "PhysicsMaterial2D",
	64: "MeshCollider",
	65: "BoxCollider",
	66: "CompositeCollider2D",
	68: "EdgeCollider2D",
	70: "CapsuleCollider2D",
	72: "ComputeShader",
	74: "AnimationClip",
	75: "ConstantForce",
	78: "TagManager",
	81: "AudioListener",
	82: "AudioSource",
	83: "AudioClip",
	84: "RenderTexture",
	86: "CustomRenderTexture",
	89: "Cubemap",
	90: "Avatar",
	91: "AnimatorController",
	93: "RuntimeAnimatorController",
	94: "ScriptMapper",
	95: "Animator",
	96: "TrailRenderer",
	98: "DelayedCallManager",
	102: "TextMesh",
	104: "RenderSettings",
	108: "Light",
	109: "CGProgram",
	110: "BaseAnimationTrack",
	111: "Animation",
	114: "MonoBehaviour",
	115: "MonoScript",
	116: "MonoManager",
	117: "Texture3D",
	118: "NewAnimationTrack",
	119: "Projector",
	120: "LineRenderer",
	121: "Flare",
	122: "Halo",
	123: "LensFlare",
	124: "FlareLayer",
	125: "HaloLayer",
	126: "NavMeshProjectSettings",
	128: "Font",
	129: "PlayerSettings",
	130: "NamedObject",
	134: "PhysicMaterial",
	135: "SphereCollider",
	136: "CapsuleCollider",
	137: "SkinnedMeshRenderer",
	138: "FixedJoint",
	141: "BuildSettings",
	142: "AssetBundle",
	143: "CharacterController",
	144: "CharacterJoint",
	145: "SpringJoint",
	146: "WheelCollider",
	147: "ResourceManager",
	150: "PreloadData",
	153: "ConfigurableJoint",
	154: "TerrainCollider",
	156: "TerrainData",
	157: "LightmapSettings",
	158: "WebCamTexture",
	159: "EditorSettings",
	162: "EditorUserSettings",
	164: "AudioReverbFilter",
	165: "AudioHighPassFilter",
	166: "AudioChorusFilter",
	167: "AudioReverbZone",
	168: "AudioEchoFilter",
	169: "AudioLowPassFilter",
	170: "AudioDistortionFilter",
	171: "SparseTexture",
	180: "AudioBehaviour",
	181: "AudioFilter",
	182: "WindZone",
	183: "Cloth",
	184: "SubstanceArchive",
	185: "ProceduralMaterial",
	186: "ProceduralTexture",
	187: "Texture2DArray",
	188: "CubemapArray",
	191: "OffMeshLink",
	192: "OcclusionArea",
	193: "Tree",
	195: "NavMeshAgent",
	196: "NavMeshSettings",
	198: "ParticleSystem",
	199: "ParticleSystemRenderer",
	200: "ShaderVariantCollection",
	205: "LODGroup",
	206: "BlendTree",
	207: "Motion",
	208: "NavMeshObstacle",
	210: "SortingGroup",
	212: "SpriteRenderer",
	213: "Sprite",
	214: "CachedSpriteAtlas",
	215: "ReflectionProbe",
	218: "Terrain",
	220: "LightProbeGroup",
	221: "AnimatorOverrideController",
	222: "CanvasRenderer",
	223: "Canvas",
	224: "RectTransform",
	225: "CanvasGroup",
	226: "BillboardAsset",
	227: "BillboardRenderer",
	228: "SpeedTreeWindAsset",
	229: "AnchoredJoint2D",
	230: "Joint2D",
	231: "SpringJoint2D",
	232: "DistanceJoint2D",
	233: "HingeJoint2D",
	234: "SliderJoint2D",
	235: "WheelJoint2D",
	236: "ClusterInputManager",
	237: "BaseVideoTexture",
	238: "NavMeshData",
	240: "AudioMixer",
	241: "AudioMixerController",
	243: "AudioMixerGroupController",
	244: "AudioMixerEffectController",
	245: "AudioMixerSnapshotController",
	246: "PhysicsUpdateBehaviour2D",
	247: "ConstantForce2D",
	248: "Effector2D",
	249: "AreaEffector2D",
	250: "PointEffector2D",
	251: "PlatformEffector2D",
	252: "SurfaceEffector2D",
	253: "BuoyancyEffector2D",
	254: "RelativeJoint2D",
	255: "FixedJoint2D",
	256: "FrictionJoint2D",
	257: "TargetJoint2D",
	258: "LightProbes",
	259: "LightProbeProxyVolume",
	271: "SampleClip",
	272: "AudioMixerSnapshot",
	273: "AudioMixerGroup",
	290: "AssetBundleManifest",
	300: "RuntimeInitializeOnLoadManager",
	310: "UnityConnectSettings",
	319: "AvatarMask",
	320: "PlayableDirector",
	328: "VideoPlayer",
	329: "VideoClip",
	330: "ParticleSystemForceField",
	331: "SpriteMask",
	362: "WorldAnchor",
	363: "OcclusionCullingData",
	1001: "PrefabInstance",
	1002: "EditorExtensionImpl",
	1003: "AssetImporter",
	1004: "AssetDatabaseV1",
	1005: "Mesh3DSImporter",
	1006: "TextureImporter",
	1007: "ShaderImporter",
	1008: "ComputeShaderImporter",
	1020: "AudioImporter",
	1026: "HierarchyState",
	1028: "AssetMetaData",
	1029: "DefaultAsset",
	1030: "DefaultImporter",
	1031: "TextScriptImporter",
	1032: "SceneAsset",
	1034: "NativeFormatImporter",
	1035: "MonoImporter",
	1038: "LibraryAssetImporter",
	1040: "ModelImporter",
	1041: "FBXImporter",
	1042: "TrueTypeFontImporter",
	1045: "EditorBuildSettings",
	1048: "InspectorExpandedState",
	1049: "AnnotationManager",
	1050: "PluginImporter",
	1051: "EditorUserBuildSettings",
	1055: "IHVImageFormatImporter",
	1101: "AnimatorStateTransition",
	1102: "AnimatorState",
	1105: "HumanTemplate",
	1107: "AnimatorStateMachine",
	1108: "PreviewAnimationClip",
	1109: "AnimatorTransition",
	1110: "SpeedTreeImporter",
	1111: "AnimatorTransitionBase",
	1112: "SubstanceImporter",
	1113: "LightmapParameters",
	1120: "LightingDataAsset",
	1124: "SketchUpImporter",
	1125: "BuildReport",
	1126: "PackedAssets",
	1127: "VideoClipImporter",
	100000: "int",
	100001: "bool",
	100002: "float",
	100003: "MonoObject",
	100004: "Collision",
	100005: "Vector3f",
	100006: "RootMotionData",
	100007: "Collision2D",
	100008: "AudioMixerLiveUpdateFloat",
	100009: "AudioMixerLiveUpdateBool",
	100010: "Polygon2D",
	100011: "void",
	19719996: "TilemapCollider2D",
	41386430: "AssetImporterLog",
	73398921: "VFXRenderer",
	156049354: "Grid",
	181963792: "Preset",
	277625683: "EmptyObject",
	285090594: "IConstraint",
	294290339: "AssemblyDefinitionReferenceImporter",
	334799969: "SiblingDerived",
	367388927: "SubDerived",
	369655926: "AssetImportInProgressProxy",
	382020655: "PluginBuildInfo",
	426301858: "EditorProjectAccess",
	468431735: "PrefabImporter",
	483693784: "TilemapRenderer",
	638013454: "SpriteAtlasDatabase",
	641289076: "AudioBuildInfo",
	644342135: "CachedSpriteAtlasRuntimeData",
	646504946: "RendererFake",
	662584278: "AssemblyDefinitionReferenceAsset",
	668709126: "BuiltAssetBundleInfoSet",
	687078895: "SpriteAtlas",
	747330370: "RayTracingShaderImporter",
	825902497: "RayTracingShader",
	877146078: "PlatformModuleSetup",
	895512359: "AimConstraint",
	937362698: "VFXManager",
	994735392: "VisualEffectSubgraph",
	994735403: "VisualEffectSubgraphOperator",
	994735404: "VisualEffectSubgraphBlock",
	1001480554: "Prefab",
	1027052791: "LocalizationImporter",
	1091556383: "Derived",
	1114811875: "ReferencesArtifactGenerator",
	1152215463: "AssemblyDefinitionAsset",
	1154873562: "SceneVisibilityState",
	1183024399: "LookAtConstraint",
	1268269756: "GameObjectRecorder",
	1325145578: "LightingDataAssetParent",
	1386491679: "PresetManager",
	1403656975: "StreamingManager",
	1480428607: "LowerResBlitTexture",
	1542919678: "StreamingController",
	1742807556: "GridLayout",
	1766753193: "AssemblyDefinitionImporter",
	1773428102: "ParentConstraint",
	1803986026: "FakeComponent",
	1818360608: "PositionConstraint",
	1818360609: "RotationConstraint",
	1818360610: "ScaleConstraint",
	1839735485: "Tilemap",
	1896753125: "PackageManifest",
	1896753126: "PackageManifestImporter",
	1953259897: "TerrainLayer",
	1971053207: "SpriteShapeRenderer",
	1977754360: "NativeObjectType",
	1995898324: "SerializableManagedHost",
	2058629509: "VisualEffectAsset",
	2058629510: "VisualEffectImporter",
	2058629511: "VisualEffectResource",
	2059678085: "VisualEffectObject",
	2083052967: "VisualEffect",
	2083778819: "LocalizationAsset",
	208985858483: "ScriptedImporter",
}

func invert_hashtable(ht: Dictionary) -> Dictionary:
	var outd: Dictionary = Dictionary()
	for key in ht:
		outd[ht[key]] = key
	return outd

var classname_to_utype: Dictionary = invert_hashtable(utype_to_classname)
