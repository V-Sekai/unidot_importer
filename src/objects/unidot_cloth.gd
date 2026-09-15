class_name UnidotCloth extends UnidotBehaviour

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	return null

func get_bone_transform(skel: Skeleton3D, bone_idx: int) -> Transform3D:
	var transform: Transform3D = Transform3D.IDENTITY
	while bone_idx != -1:
		transform = skel.get_bone_pose(bone_idx) * transform
		bone_idx = skel.get_bone_parent(bone_idx)
	return transform

func get_or_upgrade_bone_attachment(skel: Skeleton3D, state: RefCounted, bone_transform: UnidotTransform) -> BoneAttachment3D:
	var fileID: int = bone_transform.fileID
	var target_nodepath: NodePath = meta.fileid_to_nodepath.get(fileID, meta.prefab_fileid_to_nodepath.get(fileID, NodePath()))
	var ret: Node3D = skel
	if target_nodepath != NodePath():
		ret = state.scene_contents.get_node(target_nodepath)
	if ret is Skeleton3D:
		ret = BoneAttachment3D.new()
		ret.name = skel.get_bone_name(bone_transform.skeleton_bone_index)  # target_skel_bone
		state.add_child(ret, skel, bone_transform)
		state.remove_fileID_to_skeleton_bone(bone_transform.fileID)
		ret.bone_name = ret.name
		return ret
	else:
		return ret

func create_cloth_godot_node(state: RefCounted, new_parent: Node3D, component_name: String, smr: UnidotObject, mesh: Array, skel: Skeleton3D, bones: Array) -> SoftBody3D:
	var new_node: SoftBody3D = SoftBody3D.new()
	new_node.name = component_name
	state.add_child(new_node, new_parent, smr)
	state.add_fileID(new_node, self)
	if meta.get_database().enable_unidot_keys:
		new_node.editor_description = str(self)
	new_node.mesh = meta.get_godot_resource(mesh)
	new_node.ray_pickable = false
	new_node.linear_stiffness = self.linear_stiffness
	# new_node.angular_stiffness = self.angular_stiffness # Removed in 4.0 - how to set Bending stiffness??
	# parent_collision_ignore?????? # NodePath to a CollisionObject this SoftBody should avoid clipping. ????
	new_node.damping_coefficient = self.damping_coefficient
	new_node.drag_coefficient = self.drag_coefficient
	# m_CapsuleColliders ???
	# m_SphereColliders ???
	# m_Enabled # FIXME: No way to disable?!?!
	# FIXME: no GRAVITY?????
	# world velocity / world acceleration?
	# collision mass?
	# sleep threshold?
	if new_node.mesh == null:
		return new_node
	var max_dist: float = 0.01
	for coef in self.coefficients:
		var dist: float = coef.get("maxDistance", 1.0)
		if dist < 1.0e+10:
			max_dist = max(max_dist, dist)
	# We might not be able to use their "m_Coefficients" because it depends on vertex ordering
	# which might be well defined, but even if so, Unidot does some black magic to deduplicate vertices
	# across UV and normal seams. Does Godot also do this? If not, how does it keep the mesh from
	# falling apart at UV seams? If yes, how to map the two engines' algorithms here.
	var mesh_arrays: Array = new_node.mesh.surface_get_arrays(0)  # Godot SoftBody ignores other surfaces.
	var mesh_verts: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
	var mesh_bones: PackedInt32Array = mesh_arrays[Mesh.ARRAY_BONES]
	var mesh_weights: Array = Array(mesh_arrays[Mesh.ARRAY_WEIGHTS])
	var bone_per_vert: int = len(mesh_bones) / len(mesh_verts)
	var vertex_info_to_dedupe_index: Dictionary = {}.duplicate()
	var bone_idx_to_bone_transform: Dictionary = {}.duplicate()
	var bone_idx_to_attachment_path: Dictionary = {}.duplicate()
	var dedupe_vertices: PackedInt32Array = PackedInt32Array()
	var vert_idx: int = 0
	# De-duplication of vertices to deal with UV-seams and sharp normals.
	# Seems to match their logic (for meshes with only one surface at least!)
	# For example 1109/1200 or 104/129 verts
	# FIXME: I noticed some differences in vertex ordering in some cases. Hmm....
	var idx: int = 0
	var idxlen: int = len(mesh_verts)
	while idx < idxlen:
		var vert: Vector3 = mesh_verts[idx]
		var key = str(vert.x) + "," + str(vert.y) + "," + str(vert.z)
		if not bones.is_empty() and not mesh_bones.is_empty():
			key += str(0.5 * mesh_weights[idx * bone_per_vert] + mesh_bones[idx * bone_per_vert])
		if vertex_info_to_dedupe_index.has(key):
			dedupe_vertices.push_back(vertex_info_to_dedupe_index.get(key))
		else:
			vertex_info_to_dedupe_index[key] = vert_idx
			dedupe_vertices.push_back(vert_idx)
			vert_idx += 1
		idx += 1

	log_debug("Verts " + str(len(mesh_verts)) + " " + str(len(mesh_bones)) + " " + str(len(mesh_weights)) + " dedupe_len=" + str(vert_idx) + " orig_len=" + str(len(self.coefficients)))

	var pinned_points: PackedInt32Array = PackedInt32Array()
	var bones_paths: Array = [].duplicate()
	var offsets: Array = [].duplicate()
	var orig_coefficients = self.coefficients
	vert_idx = 0
	idxlen = (len(mesh_verts))
	while vert_idx < idxlen:
		var dedupe_idx = dedupe_vertices[vert_idx]
		if dedupe_idx >= len(orig_coefficients):
			vert_idx += 1
			continue
		var coef = orig_coefficients[dedupe_idx]
		if coef.get("maxDistance", max_dist) / max_dist < 0.01:
			pinned_points.push_back(vert_idx)
			if bones.is_empty():
				bones_paths.push_back(NodePath("."))
				offsets.push_back(mesh_verts[vert_idx])
			else:
				var most_weight: float = 0.0
				var most_bone: int = 0
				for boneidx in range(bone_per_vert):
					var weight: float = mesh_weights[vert_idx * bone_per_vert + boneidx]
					if weight >= most_weight:
						most_weight = weight
						most_bone = mesh_bones[vert_idx * bone_per_vert + boneidx]
				if not bone_idx_to_attachment_path.has(most_bone):
					var attachment: BoneAttachment3D = get_or_upgrade_bone_attachment(skel, state, meta.lookup(bones[most_bone]))
					bone_idx_to_bone_transform[most_bone] = (get_bone_transform(skel, skel.find_bone(attachment.bone_name)).affine_inverse())
					bone_idx_to_attachment_path[most_bone] = new_node.get_path_to(attachment)
				bones_paths.push_back(bone_idx_to_attachment_path.get(most_bone))
				offsets.push_back(bone_idx_to_bone_transform[most_bone] * mesh_verts[vert_idx])
		vert_idx += 1
	# It may be necessary to add BoneAttachment for each vertex, and
	# then, give a node path and vertex offset for the maximally weighted vertex.
	# This property isn't even documented, so IDK whatever.
	new_node.set("pinned_points", pinned_points)
	for i in range(len(pinned_points)):
		new_node.set("attachments/" + str(i) + "/spatial_attachment_path", bones_paths[i])
		new_node.set("attachments/" + str(i) + "/offset", offsets[i])
	return new_node

# TODO: convert to properties!

var coefficients:
	get:
		return keys.get("m_Coefficients", [])

var drag_coefficient:
	get:
		return keys.get("m_Friction", 0)

var damping_coefficient:
	get:
		return keys.get("m_Damping", 0)

var linear_stiffness:
	get:
		return keys.get("m_StretchingStiffness", 1)

var angular_stiffness:
	get:
		return keys.get("m_BendingStiffness", 1)
