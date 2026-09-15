class_name UnidotSkinnedMeshRenderer extends UnidotMeshRenderer

const ENABLE_CLOTH := false

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	if len(bones) == 0:
		var cloth: UnidotCloth = gameObject.GetComponent("Cloth")
		if cloth != null:
			return create_cloth_godot_node(state, new_parent, type, cloth)
		return create_godot_node_orig(state, new_parent, type)
	else:
		return null

func create_cloth_godot_node(state: RefCounted, new_parent: Node3D, component_name: String, cloth: UnidotCloth) -> Node:
	if not ENABLE_CLOTH:
		return create_godot_node_orig(state, new_parent, component_name)
	var new_node: MeshInstance3D = cloth.create_cloth_godot_node(state, new_parent, component_name, self, self.get_mesh(), null, [])
	var idx: int = 0
	for m in keys.get("m_Materials", []):
		new_node.set_surface_override_material(idx, meta.get_godot_resource(m))
		idx += 1
	return new_node

func get_skelley(state: RefCounted) -> RefCounted: # Skelley
	var bones: Array = self.bones
	if len(self.bones) == 0:
		return null
	var first_bone_obj: RefCounted = meta.lookup(bones[0])
	#if first_bone_obj.is_stripped:
	#	log_fail("Cannot create skinned mesh on stripped skeleton!")
	#	return null
	log_debug("SkinnedMeshRenderer: Looking up " + str(first_bone_obj) + " for " + str(self.gameObject))
	var skelley: RefCounted = state.fileID_to_skelley.get(first_bone_obj.fileID, null)  # Skelley
	if skelley == null:
		log_fail("Unable to find Skelley to add a mesh " + str(self) + " for " + str(first_bone_obj), "bones", first_bone_obj)
	return skelley

func create_skinned_mesh(state: RefCounted) -> Node:
	var skelley: RefCounted = get_skelley(state) # Skelley
	if skelley == null:
		return null
	var gdskel: Skeleton3D = skelley.godot_skeleton
	if gdskel == null:
		log_fail("Unable to find skeleton to add a mesh " + name + " for " + str(meta.lookup(bones[0])), "bones", meta.lookup(bones[0]))
		return null
	var component_name: String = type
	if not self.gameObject.is_stripped:
		component_name = self.gameObject.name
	var cloth: UnidotCloth = gameObject.GetComponent("Cloth")
	var ret: MeshInstance3D = null
	if cloth != null:
		ret = create_cloth_godot_node(state, gdskel, component_name, cloth)
	else:
		ret = create_godot_node_orig(state, gdskel, component_name)
	# ret.skeleton = NodePath("..") # default?
	# TODO: skin??
	ret.skin = edit_skin(component_name, get_skin(), gdskel)
	# TODO: duplicate skin and assign the correct bone names to match self.bones array
	ret.lod_bias = 128 # Disable builtin LODs on skinned meshes due to multiple bugs.
	return ret

var bones: Array:
	get:
		return keys.get("m_Bones", [])

func edit_skin(component_name: String, skin_ref: Array, gdskel: Skeleton3D) -> Skin:
	var original_is_humanoid: bool = false
	var skin: Skin = meta.get_godot_resource(skin_ref)
	if skin == null:
		log_fail("Unable to edit_skin null to skeleton " + str(gdskel), "skin", skin_ref)
		return null
	var skin_humanoid_rotation_delta: Dictionary
	if skin.has_meta("humanoid_rotation_delta"):
		skin_humanoid_rotation_delta = skin.get_meta("humanoid_rotation_delta")
	if skin == null:
		log_fail("Mesh " + component_name + " has bones " + str(len(bones)) + " has null skin", "skin")
	elif len(bones) != skin.get_bind_count():
		log_fail("Mesh " + component_name + "has bones " + str(len(bones)) + " mismatched with bind bones " + str(skin.get_bind_count()), "bones")

	var edited: bool = false
	for idx in range(len(bones)):
		var bone_transform: UnidotTransform = meta.lookup(bones[idx])
		if bone_transform == null:
			log_warn("Mesh " + component_name + " has null bone " + str(idx), "bones")
			continue
		if bone_transform.skeleton_bone_index != -1 and skin.get_bind_bone(idx) != bone_transform.skeleton_bone_index:
			edited = true
			break
		var bone_fileID = bone_transform.fileID
		if meta.transform_fileid_to_rotation_delta.has(bone_fileID) or meta.prefab_transform_fileid_to_rotation_delta.has(bone_fileID):
			if !skin_humanoid_rotation_delta.get(skin.get_bind_name(idx), Transform3D.IDENTITY).is_equal_approx(meta.transform_fileid_to_rotation_delta.get(bone_fileID, meta.prefab_transform_fileid_to_rotation_delta.get(bone_fileID))):
				edited = true
				break
	if edited:
		skin = skin.duplicate()
		for idx in range(len(bones)):
			var bone_transform: UnidotTransform = meta.lookup(bones[idx])
			if bone_transform == null:
				log_warn("Mesh " + component_name + " has null bone " + str(idx), "bones")
				continue
			if bone_transform.skeleton_bone_index != -1:
				skin.set_bind_bone(idx, bone_transform.skeleton_bone_index)
				skin.set_bind_name(idx, gdskel.get_bone_name(bone_transform.skeleton_bone_index))
			var bone_fileID = bone_transform.fileID
			if meta.transform_fileid_to_rotation_delta.has(bone_fileID) or meta.prefab_transform_fileid_to_rotation_delta.has(bone_fileID):
				var skin_rotation_delta: Transform3D = skin_humanoid_rotation_delta.get(skin.get_bind_name(idx), Transform3D.IDENTITY)
				var rotation_delta: Transform3D = meta.transform_fileid_to_rotation_delta.get(bone_fileID, meta.prefab_transform_fileid_to_rotation_delta.get(bone_fileID))
				if !rotation_delta.is_equal_approx(skin_rotation_delta):
					log_debug("skin " + str(idx) + " : This fileID is a humanoid bone rotation offset=" + str(rotation_delta.basis.get_rotation_quaternion()) + " scale " + str(rotation_delta.basis.get_scale()) + " pos " + str(rotation_delta.origin))
					skin.set_bind_pose(idx, rotation_delta * skin_rotation_delta.affine_inverse() * skin.get_bind_pose(idx))
	return skin

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = super.convert_properties(node, uprops)
	if uprops.has("m_Mesh"):
		var mesh_ref: Array = get_ref(uprops, "m_Mesh")
		outdict["_mesh_ref"] = mesh_ref
		var new_mesh: Mesh = meta.get_godot_resource(mesh_ref)
		outdict["_mesh"] = new_mesh  # property track?
		var skin_ref: Array = mesh_ref
		skin_ref = [null, -skin_ref[1], skin_ref[2], skin_ref[3]]
		outdict["skin"] = edit_skin(node.name, skin_ref, node.get_parent() as Skeleton3D)

		# TODO: blend shapes

		# TODO: m_Bones modifications? what even is the syntax. I think we shouldn't allow changes to bones.
	return outdict

func get_skin() -> Array:  # UnidotRef
	var ret: Array = keys.get("m_Mesh", [null, 0, "", null])
	return [null, -ret[1], ret[2], ret[3]]

func get_mesh() -> Array:  # UnidotRef
	return keys.get("m_Mesh", [null, 0, "", null])
