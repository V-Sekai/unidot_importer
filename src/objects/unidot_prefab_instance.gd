# Is a PrefabInstance a GameObject? Unidot seems to treat it that way at times. Other times not...
# Is this canon? We'll never know because the documentation denies even the existence of a "PrefabInstance" class
class_name UnidotPrefabInstance extends UnidotGameObject

const anim_tree_runtime := preload("../../runtime/anim_tree.gd")

const STRING_KEYS: Dictionary = {
	"value": 1,
	"m_Name": 1,
	"m_TagString": 1,
	"name": 1,
	"first": 1,
	"propertyPath": 1,
	"path": 1,
	"attribute": 1,
	"m_ShaderKeywords": 1,
	"typelessdata": 1,  # Mesh m_VertexData; Texture image data
	"m_IndexBuffer": 1,
	"Hash": 1,
}

func get_godot_type() -> String:
	return "PackedScene"

func is_stripped_or_prefab_instance() -> bool:
	return true

func set_owner_rec(node: Node, owner: Node):
	node.owner = owner
	for n in node.get_children():
		set_owner_rec(n, owner)

# When you see a PrefabInstance, load() the scene.
# If it is_prefab_reference but not the root, log an error.

# For all Transform in scene, find transforms whose parent has is_prefab_reference=true. These subtrees must be mapped from PrefabInstance.

# TODO: Create map from corresponding source object id (stripped id, PrefabInstanceId^target object id) and do so recursively, to target path...

# For all PrefabInstance in scene, make map from m_TransformParent
# Note also: a PrefabInstance with m_TransformParent=0 in a prefab defines a "Prefab Variant". In Godot terms, this is an "inhereted" or instanced scene.
# COMPLICATED!!!

# Rules about skeletons: If any skinned mesh has bones, which are part of a prefab instance, mark all bones as belonging to that prefab instance (no consideration is made as to whether they link two separate skeletons together.)
# Then, repeat one more time and makwe sure no overlap
# all transforms are marked as parented to the prefab.

func set_editable_children(state: RefCounted, instanced_scene: Node) -> Node:
	state.owner.set_editable_instance(instanced_scene, true)
	return instanced_scene

func get_name() -> String:
	# The default name of a prefab instance will always be the filename, regardless of m_Name.
	# But it can be overridden.
	var source_prefab_meta = meta.lookup_meta(self.source_prefab)
	var go_id = 400000
	if source_prefab_meta != null:
		go_id = source_prefab_meta.prefab_main_gameobject_id
	else:
		log_debug("During prefab name lookup, failed to lookup meta for source prefab " + str(self.source_prefab))
	for mod in modifications:
		var property_key: String = mod.get("propertyPath", "")
		var source_obj_ref: Array = mod.get("target", [null, 0, "", null])
		var value: String = mod.get("value", "")
		if property_key == "m_Name" and source_obj_ref[1] == go_id:
			log_debug("Found overridden m_Name: Mod is " + str(mod))
			return value
	return source_prefab_meta.get_main_object_name()

func create_godot_node(xstate: RefCounted, new_parent: Node3D) -> Node:  # Node3D
	# called from toplevel (scene, inherited prefab?)
	var ret_data: Array = self.instantiate_prefab_node(xstate, new_parent)
	if len(ret_data) < 4:
		return null
	return ret_data[3]  # godot node.

# Generally, all transforms which are sub-objects of a prefab will be marked as such ("Create map from corresponding source object id (stripped id, PrefabInstanceId^target object id) and do so recursively, to target path...")
func instantiate_prefab_node(xstate: RefCounted, new_parent: Node3D) -> Array:  # [prefab_fileid, prefab_name, prefab_root_gameobject_id, godot_node]
	meta.prefab_id_to_guid[self.fileID] = self.source_prefab[2]  # UnidotRef[2] is guid
	var state: RefCounted = xstate  # scene_node_state
	var ps: RefCounted = state.prefab_state  # scene_node_state.PrefabState
	var target_prefab_meta = meta.lookup_meta(source_prefab)
	if target_prefab_meta == null or target_prefab_meta.guid == self.meta.guid:
		log_fail("Unable to load prefab dependency " + str(source_prefab) + " from " + str(self.meta.guid), "prefab", source_prefab)
		return []
	var packed_scene: PackedScene = target_prefab_meta.get_godot_resource(source_prefab)
	if packed_scene == null:
		log_fail("Failed to instantiate prefab with guid " + str(self) + " from " + str(self.meta.guid), "prefab", source_prefab)
		return []
	meta.transform_fileid_to_parent_fileid[meta.xor_or_stripped(target_prefab_meta.prefab_main_transform_id, self.fileID)] = self.parent_ref[1]
	log_debug("Assigning prefab root transform " + str(meta.xor_or_stripped(target_prefab_meta.prefab_main_transform_id, self.fileID)) + " parent fileid " + str(self.parent_ref[1]))
	log_debug("Instancing PackedScene at " + str(packed_scene.resource_path) + ": " + str(packed_scene.resource_name))
	var instanced_scene: Node3D = null
	var toplevel_rename: String = ""
	for mod in modifications:
		var property_key: String = mod.get("propertyPath", "")
		var source_obj_ref: Array = mod.get("target", [null, 0, "", null])
		var value: String = mod.get("value", "")
		var mod_fileID: int = source_obj_ref[1]
		if property_key == "m_Name" and mod_fileID == target_prefab_meta.prefab_main_gameobject_id:
			toplevel_rename = value
			break
	if new_parent == null:
		# This is the "Inherited Scene" case (Godot), or "Prefab Variant" as it is called.
		# Godot does not have an API to create an inherited scene. However, luckily, the file format is simple.
		# We just need a [instance=ExtResource(1)] attribute on the root node.

		# FIXME: This may be unstable across Godot versions, if .tscn format ever changes.
		# node->set_scene_inherited_state(sdata->get_state()) is not exposed to GDScript. Let's HACK!!!
		var stub_filename = "res://_temp_scene.tscn"
		var dres = DirAccess.open("res://")
		var fres = FileAccess.open(stub_filename, FileAccess.WRITE_READ)
		log_debug("Writing stub scene to " + stub_filename)
		var to_write: String = "[gd_scene load_steps=2 format=2]\n\n" + '[ext_resource path="' + str(packed_scene.resource_path) + '" type="PackedScene" id=1]\n\n' + "[node name=" + var_to_str(str(toplevel_rename)) + " instance=ExtResource( 1 )]\n"
		fres.store_string(to_write)
		#log_debug(to_write)
		fres.flush()
		fres.close()
		fres = null
		var temp_packed_scene: PackedScene = ResourceLoader.load(stub_filename, "", ResourceLoader.CACHE_MODE_IGNORE)
		instanced_scene = temp_packed_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		dres.remove(stub_filename)
		instanced_scene.name = StringName(toplevel_rename)
		state.add_child(instanced_scene, new_parent, self)
	else:
		# Traditional instanced scene case: It only requires calling instantiate() and setting the filename.
		instanced_scene = packed_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		instanced_scene.name = StringName(toplevel_rename)
		#instanced_scene.scene_file_path = packed_scene.resource_path
		state.add_child(instanced_scene, new_parent, self)

		if set_editable_children(state, instanced_scene) != instanced_scene:
			instanced_scene.scene_file_path = ""
			set_owner_rec(instanced_scene, state.owner)
	var anim_player: AnimationPlayer = instanced_scene.get_node_or_null("AnimationPlayer") as AnimationPlayer
	# Scenes with only a RESET but not a unidot-created _T-Pose_ are following the Godot convention of rest-pose as RESET.
	# In Godot engine versions which support rest-as-RESET, the model will already be posed correctly and we do not want this.
	if anim_player != null and anim_player.has_animation(&"RESET") and anim_player.has_animation(&"_T-Pose_"):
		var root_node: Node = anim_player.get_node(anim_player.root_node)
		var reset_anim: Animation = anim_player.get_animation(&"RESET")
		if reset_anim != null:
			# Copied from AnimationMixer::reset()
			var aux_player := AnimationPlayer.new()
			root_node.add_child(aux_player)
			aux_player.reset_on_save = false
			var al := AnimationLibrary.new()
			al.add_animation(&"RESET", reset_anim)
			aux_player.add_animation_library(&"", al)
			aux_player.assigned_animation = &"RESET"
			aux_player.seek(0.0, true)
			root_node.remove_child(aux_player)
			aux_player.queue_free()

	var pgntfac = target_prefab_meta.prefab_gameobject_name_to_fileid_and_children
	var gntfac = target_prefab_meta.gameobject_name_to_fileid_and_children
	#state.prefab_state.prefab_gameobject_name_map[meta.xor_or_stripped(self.meta.prefab_main_gameobject_id, self.fileID] =
	meta.remap_prefab_gameobject_names_update(self.fileID, target_prefab_meta, gntfac, ps.prefab_gameobject_name_map)
	meta.remap_prefab_gameobject_names_update(self.fileID, target_prefab_meta, pgntfac, ps.prefab_gameobject_name_map)
	#log_debug("Resulting name_map: " + str(ps.prefab_gameobject_name_map))
	meta.remap_prefab_fileids(self.fileID, target_prefab_meta)

	state.add_bones_to_prefabbed_skeletons(self.fileID, target_prefab_meta, instanced_scene)

	log_debug("Prefab " + str(packed_scene.resource_path) + " ------------")
	log_debug("Adding to parent " + str(new_parent))
	#log_debug(str(target_prefab_meta.fileid_to_nodepath))
	#log_debug(str(target_prefab_meta.prefab_fileid_to_nodepath))
	#log_debug(str(target_prefab_meta.fileid_to_skeleton_bone))
	#log_debug(str(target_prefab_meta.prefab_fileid_to_skeleton_bone))
	#log_debug(" ------------")
#				var component_key = component.get_component_key()
#				if not name_map.has(component_key):
#					name_map[component_key] = component.fileID
	var fileID_to_keys = {}.duplicate()
	var nodepath_to_first_virtual_object = {}.duplicate()
	var nodepath_to_keys = {}.duplicate()
	for mod in modifications:
		# log_debug("Preparing to apply mod: Mod is " + str(mod))
		var property_key: String = mod.get("propertyPath", "")
		var source_obj_ref: Array = mod.get("target", [null, 0, "", null])
		var obj_value: Array = mod.get("objectReference", [null, 0, "", null])
		var value: String = mod.get("value", "")

		if property_key == "m_StaticEditorFlags" or property_key == "m_Layer" or property_key == "m_TagString":
			var value_var: Variant = value
			if property_key != "m_TagString":
				value_var = value.to_int()
			# 33 - filter, 23 - renderer
			# We really want the MeshRenderer and Rigidbody to learn about the static lightmap flag.
			var child_components: Dictionary = pgntfac.get(source_obj_ref[1], gntfac.get(source_obj_ref[1], {}))
			for key in child_components:
				if typeof(key) != TYPE_STRING:
					var component_fileID: int = child_components[key]
					if component_fileID != 0:
						if not fileID_to_keys.has(component_fileID):
							fileID_to_keys[component_fileID] = {}.duplicate()
						fileID_to_keys.get(component_fileID)[property_key] = value_var

		var fileID: int = source_obj_ref[1]
		if not fileID_to_keys.has(fileID):
			fileID_to_keys[fileID] = {}.duplicate()
		if STRING_KEYS.has(property_key):
			fileID_to_keys.get(fileID)[property_key] = value
		elif value.is_empty():
			fileID_to_keys.get(fileID)[property_key] = obj_value
		elif obj_value[1] != 0:
			log_warn("Object has both value " + str(value) + " and objref " + str(obj_value) + " for " + str(mod), property_key, obj_value)
			fileID_to_keys.get(fileID)[property_key] = obj_value
		elif len(value) < 24 and value.is_valid_int():
			fileID_to_keys.get(fileID)[property_key] = value.to_int()
		elif len(value) < 32 and value.is_valid_float():
			fileID_to_keys.get(fileID)[property_key] = value.to_float()
		else:
			fileID_to_keys.get(fileID)[property_key] = value
	# Some legacy "feature" where objects part of a prefab might be not stripped
	# In that case, the 'non-stripped' copy will override even the modifications.
	for asset in ps.non_stripped_prefab_references.get(self.fileID, []):
		var fileID: int = asset.prefab_source_object[1]
		if not fileID_to_keys.has(fileID):
			fileID_to_keys[fileID] = {}.duplicate()
		for key in asset.keys:
			# log_debug("Legacy prefab override fileID " + str(fileID) + " key " + str(key) + " value " + str(asset.keys[key]))
			fileID_to_keys[fileID][key] = asset.keys[key]
	var animator_node_to_object: Dictionary
	for fileID in fileID_to_keys:
		var target_utype: int = target_prefab_meta.fileid_to_utype.get(fileID, target_prefab_meta.prefab_fileid_to_utype.get(fileID, 0))
		var target_nodepath: NodePath = target_prefab_meta.fileid_to_nodepath.get(fileID, target_prefab_meta.prefab_fileid_to_nodepath.get(fileID, NodePath()))
		var target_skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone.get(fileID, target_prefab_meta.prefab_fileid_to_skeleton_bone.get(fileID, ""))
		var virtual_fileID = meta.xor_or_stripped(fileID, self.fileID)
		var virtual_unidot_object: UnidotObject = adapter.instantiate_unidot_object_from_utype(meta, virtual_fileID, target_utype)
		var uprops: Dictionary = fileID_to_keys.get(fileID, {})
		log_debug("XXXd Calculating prefab modifications " + str(target_prefab_meta.guid) + "/" + str(fileID) + "/" + str(target_nodepath) + ":" + target_skel_bone + " " + str(uprops))
		if uprops.has("m_Name"):
			var m_Name: String = uprops["m_Name"]
			state.add_prefab_rename(fileID, m_Name)
		var existing_node = instanced_scene.get_node(target_nodepath)
		if uprops.get("m_Controller", [null, 0])[1] != 0:
			var animtree: AnimationTree = null
			if target_utype == 95:  # Animator component
				if existing_node != null and existing_node.get_class() == "AnimationPlayer":
					log_debug("Adding AnimationTree as sibling to existing AnimationPlayer component")
					animtree = AnimationTree.new()
					animtree.name = "AnimationTree"
					animtree.set("deterministic", false) # New feature in 4.2, acts like Untiy write defaults off
					if uprops.get("m_ApplyRootMotion", 0) == 0:
						animtree.root_motion_track = NodePath("%GeneralSkeleton:Root")
					existing_node.get_parent().add_child(animtree, true)
					animtree.owner = state.owner
					animtree.anim_player = animtree.get_path_to(existing_node)
					animtree.active = meta.setting_animtree_active() and uprops.get("m_Enabled", true)
					animtree.set_script(anim_tree_runtime)
					# Weird special case, likely to break.
					# The original file was a .glb and doesn't have an AnimationTree node.
					# We add one and try to pretend it's ours.
					# Maybe better to change glb post-import script to add one.
					state.add_fileID(animtree, virtual_unidot_object)
				else:
					animtree = existing_node
				virtual_unidot_object.keys = uprops
				animator_node_to_object[animtree] = virtual_unidot_object
				virtual_unidot_object.assign_controller(animtree.get_node(animtree.anim_player), animtree, uprops["m_Controller"])
		log_debug("Looking up instanced object at " + str(target_nodepath) + ": " + str(existing_node))
		if target_skel_bone.is_empty() and existing_node == null:
			log_fail(str(fileID) + " FAILED to get_node to apply mod to node at path " + str(target_nodepath) + "!! Mod is " + str(uprops), "empty" if uprops.is_empty() else uprops.keys()[0], virtual_unidot_object)
		elif target_skel_bone.is_empty():
			if existing_node.has_meta("unidot_keys"):
				var orig_meta: Variant = existing_node.get_meta("unidot_keys")
				var exist_prop: Variant = orig_meta
				for uprop in uprops:
					var last_key: String = ""
					var this_key: String = ""
					var skip_first_piece: bool = true
					for prop_piece in uprop.split("."):
						if skip_first_piece:
							skip_first_piece = false
							continue
						if typeof(exist_prop) == TYPE_DICTIONARY:
							last_key = this_key
							this_key = prop_piece
							exist_prop = exist_prop.get(prop_piece, {})
						elif typeof(exist_prop) == TYPE_ARRAY:
							if prop_piece == "Array":
								continue
							if prop_piece == "size":
								continue
							log_debug("Splitting array key: " + str(uprop) + " prop_piece " + str(prop_piece) + ": " + str(exist_prop) + " / all props: " + str(uprops))
							var idx: int = (prop_piece.split("[")[1].split("]")[0]).to_int()
							exist_prop = exist_prop[idx]
						else:
							match prop_piece:
								"x":
									exist_prop.x = uprops[uprop]
								"y":
									exist_prop.y = uprops[uprop]
								"z":
									exist_prop.z = uprops[uprop]
								"w":
									exist_prop.w = uprops[uprop]
								"r":
									exist_prop.r = uprops[uprop]
								"g":
									exist_prop.g = uprops[uprop]
								"b":
									exist_prop.b = uprops[uprop]
								"a":
									exist_prop.a = uprops[uprop]
					if typeof(exist_prop) == typeof(uprops[uprop]):
						exist_prop = uprops[uprop]
					if typeof(exist_prop) != TYPE_DICTIONARY:
						if last_key.is_empty():
							orig_meta[this_key] = exist_prop
						else:
							orig_meta[last_key][this_key] = exist_prop
				existing_node.set_meta("unidot_keys", orig_meta)
			if not nodepath_to_first_virtual_object.has(target_nodepath) or nodepath_to_first_virtual_object[target_nodepath] is UnidotTransform or nodepath_to_first_virtual_object[target_nodepath] is UnidotGameObject:
				nodepath_to_first_virtual_object[target_nodepath] = virtual_unidot_object
			var converted: Dictionary = virtual_unidot_object.convert_properties(existing_node, uprops)
			log_debug("Converted props " + str(converted) + " from " + str(nodepath_to_keys.get(target_nodepath)) + " at " + str(virtual_unidot_object))
			virtual_unidot_object.apply_component_props(existing_node, converted)
			if not nodepath_to_keys.has(target_nodepath):
				nodepath_to_keys[target_nodepath] = converted
			else:
				var dict: Dictionary = nodepath_to_keys.get(target_nodepath)
				for key in converted:
					dict[key] = converted.get(key)
				nodepath_to_keys[target_nodepath] = dict
		else:
			if existing_node != null:
				# Test this:
				log_debug("Applying mod to skeleton bone " + str(existing_node) + " at path " + str(target_nodepath) + ":" + str(target_skel_bone) + "!! Mod is " + str(uprops))
				virtual_unidot_object.configure_skeleton_bone_props(existing_node, target_skel_bone, uprops)
			else:
				log_fail("FAILED to get_node to apply mod to skeleton at path " + str(target_nodepath) + ":" + target_skel_bone + "!! Mod is " + str(uprops), "empty" if uprops.is_empty() else uprops.keys()[0], virtual_unidot_object)
	for target_nodepath in nodepath_to_keys:
		var virtual_unidot_object: UnidotObject = nodepath_to_first_virtual_object.get(target_nodepath)
		var existing_node = instanced_scene.get_node(target_nodepath)
		var uprops: Dictionary = fileID_to_keys.get(fileID, {})
		var props: Dictionary = nodepath_to_keys.get(target_nodepath, {})
		if existing_node != null:
			log_debug("Applying mod to node " + str(existing_node) + " at path " + str(target_nodepath) + "!! Mod is " + str(props) + "/" + str(props.has("name")))
			virtual_unidot_object.apply_node_props(existing_node, props)
			if target_nodepath == NodePath(".") and props.has("name"):
				log_debug("Applying name " + str(props.get("name")))
				existing_node.name = props.get("name")
		else:
			log_fail("FAILED to get_node to apply mod to node at path " + str(target_nodepath) + "!! Mod is " + str(props), "empty" if uprops.is_empty() else uprops.keys()[0], virtual_unidot_object)

	# NOTE: We have duplicate code here for GameObject and then Transform
	# The issue is, we will be parented to a stripped GameObject or Transform, but we do not
	# know the corresponding ID of the other stripped object.
	# Additionally, while IDs are predictable in Prefab Variants, they are chosen arbitrarily
	# in Scenes, so we cannot guess the ID of the corresponding Transform from the GameObject.

	# Therefore, the only way seems to be to process all GameObjects, and
	# then process all Transforms, as if they are separate objects...

	var nodepath_bone_to_stripped_gameobject: Dictionary = {}.duplicate()
	var gameobject_fileid_to_attachment: Dictionary = {}.duplicate()
	var gameobject_fileid_to_body: Dictionary = {}.duplicate()
	var orig_state_body: CollisionObject3D = state.body
	for gameobject_asset in ps.gameobjects_by_parented_prefab.get(self.fileID, {}).values():
		# NOTE: transform_asset may be a GameObject, in case it was referenced by a Component.
		var par: UnidotGameObject = gameobject_asset
		var source_obj_ref = par.prefab_source_object
		var source_transform_id: int = gntfac.get(source_obj_ref[1], pgntfac.get(source_obj_ref[1], {})).get(4, 0)
		var transform_delta: Transform3D = target_prefab_meta.transform_fileid_to_rotation_delta.get(source_transform_id, target_prefab_meta.prefab_transform_fileid_to_rotation_delta.get(source_transform_id, Transform3D()))
		log_debug("Checking stripped GameObject " + str(par) + ": " + str(source_obj_ref) + " is it " + target_prefab_meta.guid)
		assert(target_prefab_meta.guid == source_obj_ref[2])
		var target_nodepath: NodePath = target_prefab_meta.fileid_to_nodepath.get(source_obj_ref[1], target_prefab_meta.prefab_fileid_to_nodepath.get(source_obj_ref[1], NodePath()))
		var target_skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone.get(source_obj_ref[1], target_prefab_meta.prefab_fileid_to_skeleton_bone.get(source_obj_ref[1], ""))
		nodepath_bone_to_stripped_gameobject[str(target_nodepath) + "/" + str(target_skel_bone)] = gameobject_asset
		log_debug("Get target node " + str(target_nodepath) + " bone " + str(target_skel_bone) + " from " + str(instanced_scene.scene_file_path))
		var target_parent_obj = instanced_scene.get_node(target_nodepath)
		var attachment: Node3D = target_parent_obj
		if attachment == null:
			log_fail("Unable to find node " + str(target_nodepath) + " on scene " + str(packed_scene.resource_path), "prefab_source", source_obj_ref)
			continue
		log_debug("Found gameobject: " + str(target_parent_obj.name))
		if not target_skel_bone.is_empty() or target_parent_obj is BoneAttachment3D:
			var godot_skeleton: Node3D = target_parent_obj
			if target_parent_obj is BoneAttachment3D:
				attachment = target_parent_obj
				godot_skeleton = target_parent_obj.get_parent()
			for comp in ps.components_by_stripped_id.get(gameobject_asset.fileID, []):
				if comp.type == "Rigidbody":
					var physattach: PhysicalBone3D = comp.create_physical_bone(state, godot_skeleton, target_skel_bone)
					state.body = physattach
					attachment = physattach
					state.add_fileID(attachment, gameobject_asset)
					comp.configure_node(physattach)
					gameobject_fileid_to_attachment[gameobject_asset.fileID] = attachment
					#state.fileid_to_nodepath[transform_asset.fileID] = gameobject_asset.fileID
			if attachment == null:
				# Will not include the Transform.
				if len(ps.components_by_stripped_id.get(gameobject_asset.fileID, [])) >= 1:
					attachment = BoneAttachment3D.new()
					attachment.name = target_skel_bone  # target_parent_obj.name if not stripped??
					attachment.bone_name = target_skel_bone
					state.add_child(attachment, godot_skeleton, null) # gameobject_asset)
					gameobject_fileid_to_attachment[gameobject_asset.fileID] = attachment
		for component in ps.components_by_stripped_id.get(gameobject_asset.fileID, []):
			if component.type == "MeshFilter":
				if not component.is_stripped:
					log_debug("Prefab found a non-stripped MeshFilter " + str(component.fileID))
					gameobject_asset.meshFilter = component
		if gameobject_asset.meshFilter == null:
			for component in ps.components_by_stripped_id.get(gameobject_asset.fileID, []):
				if component.type == "MeshCollider":
					log_debug("Found a MeshCollider " + str(component.fileID) + " without a MeshFilter")
					var source_fileID_mr: int = pgntfac.get(source_obj_ref[1], gntfac.get(source_obj_ref[1], {})).get(33, 0)
					if source_fileID_mr != 0:
						log_debug("Found a MeshFilter source id " + str(source_fileID_mr))
						var source_fileID_path: NodePath = target_prefab_meta.fileid_to_nodepath.get(source_fileID_mr, NodePath())
						if source_fileID_path != NodePath():
							log_debug("Found a MeshFilter source path " + str(source_fileID_path))
							var source_node: Node = instanced_scene.get_node(source_fileID_path)
							if source_node is MeshInstance3D:
								log_debug("Found a MeshInstance " + str(source_node) + " mesh " + str(source_node.mesh))
								component.source_mesh_instance = source_node
		var comp_map = {}
		for component in ps.components_by_stripped_id.get(gameobject_asset.fileID, []):
			if attachment == null:
				log_fail("Unable to create godot node " + component.type + " on null attachment ", "attachment", component)
			# FIXME: We do not currently store m_StaticEditorFlags on the GameObject
			# so there is no way to assign m_StaticEditorFlags on newly-created MeshFilter components.
			var tmp = component.create_godot_node(state, attachment)
			if tmp is AnimationPlayer or tmp is AnimationTree:
				animator_node_to_object[tmp] = component
			if tmp != null:
				component.configure_node(tmp)
				while tmp.get_parent() != null and tmp.get_parent() != attachment:
					tmp = tmp.get_parent()
				if tmp is Node3D:
					tmp.transform = transform_delta * tmp.transform
			var ckey = component.get_component_key()
			if not comp_map.has(ckey):
				comp_map[ckey] = component.fileID
		gameobject_fileid_to_body[gameobject_asset.fileID] = state.body
		state.body = orig_state_body
		state.add_component_map_to_prefabbed_gameobject(gameobject_asset.fileID, comp_map)
		if attachment != null and attachment is BoneAttachment3D and attachment.get_child_count() == 0:
			target_parent_obj.remove_child(attachment)
			attachment.queue_free()
			gameobject_fileid_to_attachment.erase(gameobject_asset.fileID)

#	var smrs: Array[UnidotSkinnedMeshRenderer]
	var smrs: Array
	# And now for the analogous code to process stripped Transforms.
	for transform_asset in ps.transforms_by_parented_prefab.get(self.fileID, {}).values():
		# NOTE: transform_asset may be a GameObject, in case it was referenced by a Component.
#		var par: UnidotTransform = transform_asset
		var par = transform_asset
		var source_obj_ref = par.prefab_source_object
		log_debug("Checking stripped Transform " + str(par) + ": " + str(source_obj_ref) + " is it " + target_prefab_meta.guid)
		assert(target_prefab_meta.guid == source_obj_ref[2])
		var target_nodepath: NodePath = target_prefab_meta.fileid_to_nodepath.get(source_obj_ref[1], target_prefab_meta.prefab_fileid_to_nodepath.get(source_obj_ref[1], NodePath()))
		var target_skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone.get(source_obj_ref[1], target_prefab_meta.prefab_fileid_to_skeleton_bone.get(source_obj_ref[1], ""))
		var gameobject_asset: UnidotGameObject = nodepath_bone_to_stripped_gameobject.get(str(target_nodepath) + "/" + str(target_skel_bone), null)
		log_debug("Get target node " + str(target_nodepath) + " bone " + str(target_skel_bone) + " from " + str(instanced_scene.scene_file_path))
		var target_parent_obj = instanced_scene.get_node(target_nodepath)
		var attachment: Node3D = target_parent_obj
		var already_has_attachment: bool = false
		if attachment == null:
			log_fail("Unable to find node " + str(target_nodepath) + " on scene " + str(packed_scene.resource_path), "prefab_source", source_obj_ref)
			continue
		log_debug("Found transform: " + str(target_parent_obj.name))
		if gameobject_asset != null:
			state.body = gameobject_fileid_to_body.get(gameobject_asset.fileID, state.body)
		if gameobject_asset != null and gameobject_fileid_to_attachment.has(gameobject_asset.fileID):
			log_debug("We already got one! " + str(gameobject_asset.fileID) + " " + str(target_skel_bone))
			attachment = state.scene_contents.get_node(state.fileid_to_nodepath.get(gameobject_asset.fileID))
			state.add_fileID(attachment, transform_asset)
			already_has_attachment = true
		elif !already_has_attachment and (not target_skel_bone.is_empty() or target_parent_obj is BoneAttachment3D):
			var godot_skeleton: Node3D = target_parent_obj
			if target_parent_obj is BoneAttachment3D:
				attachment = target_parent_obj
				godot_skeleton = target_parent_obj.get_parent()
			else:
				attachment = BoneAttachment3D.new()
				attachment.name = target_skel_bone  # target_parent_obj.name if not stripped??
				attachment.bone_name = target_skel_bone
				log_debug("Made a new attachment! " + str(target_skel_bone))
				state.add_child(attachment, godot_skeleton, transform_asset)

		var new_skelley: RefCounted = state.skelley_parents.get(transform_asset.fileID, null)
		if new_skelley != null:
			log_debug("It's Peanut Butter Skelley time: " + str(transform_asset))
			if new_skelley.godot_skeleton != null and new_skelley.godot_skeleton.get_parent() == null:
				if not state.active_avatars.is_empty():
					new_skelley.godot_skeleton.name = "GeneralSkeleton"
				attachment.add_child(new_skelley.godot_skeleton, true)
				new_skelley.godot_skeleton.owner = state.owner
				if not state.active_avatars.is_empty():
					new_skelley.godot_skeleton.unique_name_in_owner = true
			for smr in new_skelley.skinned_mesh_renderers:
				smrs.append(smr)

		var name_map = {}
		for child_transform in ps.child_transforms_by_stripped_id.get(transform_asset.fileID, []):
			if child_transform.gameObject != null and attachment != null:
				log_debug("Adding " + str(child_transform.gameObject.name) + " to " + str(attachment.name))
			# child_transform usually Transform; occasionally can be PrefabInstance
			if attachment == null:
				log_fail("Unable to recurse to child_transform " + str(child_transform) + " on null bone attachment", "children", self)
			log_debug("Attempting to recurse to transform " + str(child_transform))
			var prefab_data: Array = recurse_to_child_transform(state, child_transform, attachment)
			if child_transform.gameObject != null:
				name_map[child_transform.gameObject.name] = child_transform.gameObject.fileID
			if len(prefab_data) == 4:
				name_map[prefab_data[1]] = prefab_data[2]
				if gameobject_asset != null:
					state.add_prefab_to_parent_transform(transform_asset.fileID, prefab_data[0])
		state.add_name_map_to_prefabbed_transform(transform_asset.fileID, name_map)
		state.body = orig_state_body

	for skelley in state.prefab_state.skelleys_by_parented_prefab.get(self.fileID, []):
		for smr in skelley.skinned_mesh_renderers:
			smrs.append(smr)
	for smr in smrs:
		var smrnode: Node = smr.create_skinned_mesh(state)
		if smrnode != null:
			smr.log_debug("Finally added SkinnedMeshRenderer " + str(smr) + " into prefabbed Skeleton " + str(state.owner.get_path_to(smrnode)))
	for plugin in meta.get_enabled_plugins():
		plugin.setup_post_prefab(self, state, instanced_scene)
	for animtree in animator_node_to_object:
		var obj: RefCounted = animator_node_to_object[animtree]
		# var controller_object = pkgasset.parsed_meta.lookup(obj.keys["m_Controller"])
		# If not found, we can't recreate the animationLibrary
		obj.setup_post_children(animtree, null) # Unclear if/how sub-avatar meta should be supported

	# TODO: detect skeletons which overlap with existing prefab, and add bones to them.
	# TODO: implement modifications:
	# I think we should separate out the **CREATION OF STRUCTURE** from the **SETTING OF STATE**
	# If we do this, prefab modification properties would work the same way as normal properties:
	# prefab:
	#    instantiate scene
	#    assign property modifications
	# top-level (scene):
	#    build structure with create_godot_nodes
	#    now we have what is basically an instantiated scene.
	#    assign property modifications

	#calculate_prefab_nodepaths(state, instanced_scene, target_fileid, target_prefab_meta)
	#for target_fileid in target_prefab_meta.fileid_to_nodepath:
	#	var stripped_id = meta.xor_or_stripped(int(target_fileid), fileID)
	#	prefab_fileid_to_nodepath =
	#stripped_id_to_nodepath
	#for mod in self.modifications:
	#	# TODO: Assign godot properties for each modification
	#	pass

	# FIXME: If we're in a top-level scene with its own stripped components, then we should use those IDs, not xor.
	# The ID numbers might not match up 1-to-1.

	return [self.fileID, toplevel_rename, meta.xor_or_stripped(target_prefab_meta.prefab_main_gameobject_id, self.fileID), instanced_scene]

func get_transform() -> Object:  # Not really... but there usually isn't a stripped transform for the prefab instance itself.
	return self

var rootOrder: int:
	get:
		return 0  # no idea..

func get_gameObject() -> UnidotGameObject:
	return self

var parent_ref: Array:  # UnidotRef
	get:
		return keys.get("m_Modification", {}).get("m_TransformParent", [null, 0, "", 0])

# Special case: this is used to find a common ancestor for Skeletons. We stop at the prefab instance and do not go further.
var parent_no_stripped: UnidotObject:  # Array #UnidotRef
	get:
		return null  # meta.lookup(parent_ref)

var parent: UnidotObject:
	get:
		return meta.lookup(parent_ref)

func is_toplevel() -> bool:
	return not is_legacy_parent_prefab and parent_ref[1] == 0

var modifications: Array:
	get:
		return keys.get("m_Modification", {}).get("m_Modifications", [])

var removed_components: Array:
	get:
		return keys.get("m_Modification", {}).get("m_RemovedComponents", [])

var source_prefab: Array:  # UnidotRef
	get:
		# new: m_SourcePrefab; old: m_ParentPrefab
		return keys.get("m_SourcePrefab", keys.get("m_ParentPrefab", [null, 0, "", 0]))

var is_legacy_parent_prefab: bool:
	get:
		# Legacy prefabs will stick one of these at the root of the Prefab file. It serves no purpose
		# the legacy "prefab parent" object has a m_RootGameObject reference, but you can determine that
		# the same way modern prefabs do, the only GameObject whose Transform has m_Father == null
		return keys.get("m_IsPrefabParent", false)

