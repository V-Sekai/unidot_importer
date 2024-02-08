@tool
extends EditorPlugin


var skeleton_editor: VBoxContainer
var controls : HBoxContainer
var auto_scale_tpose_button: Button
var unmerge_armature_button: Button
var preserve_pose_button: Button
var apply_motion_scale_button: Button
var merge_compatible_armature_button: Button
var align_reset_armature_button: Button
var mirror_pose_button: Button
var lock_bone_button: Button
var rename_bone_button: Button
var rename_bone_dropdown: OptionButton
# Set when the user has clicked a Skeleton3D node
var selected_skel: Skeleton3D
# Set when the user has clicked a Node3D which has a child Skeleton3D and an ancestor Skeleton3D:
var merge_armature_selected_node: Node3D
var merge_armature_selected_skel: Skeleton3D
var merge_armature_selected_target_skel: Skeleton3D


# Bone locking and bone mirror state code
# This became a lot more complicated in order to correctly support undo/redo.
# Basically, we keep track of the state of the buttons in the undo log. Then, the mirror and lock will work the same in reverse.
var disable_next_update: bool
var lock_bone_mode: bool
var last_pose_positions: PackedVector3Array
var last_pose_rotations: Array[Quaternion]
var last_pose_scales: PackedVector3Array

var selected_bone_name: String
var selected_bone_idx: int = -1
var mirror_bone_mode: bool
var last_mirror_bone_idx: int = -1
var locked_bone_bunny_positions: PackedVector3Array
var locked_bone_bunny_rotations: Array[Quaternion]
var locked_bone_bunny_rot_scales: Array[Basis]

const merged_skeleton_script := preload("./merged_skeleton.gd")


func _enter_tree():
	# Initialization of the plugin goes here.
	controls = HBoxContainer.new()
	unmerge_armature_button = Button.new()
	unmerge_armature_button.text = "Unmerge Armature"
	unmerge_armature_button.hide()
	unmerge_armature_button.pressed.connect(unmerge_armature_button_clicked)
	controls.add_child(unmerge_armature_button)
	preserve_pose_button = Button.new()
	preserve_pose_button.text = "Align to Pose"
	preserve_pose_button.hide()
	preserve_pose_button.pressed.connect(preserve_pose_button_clicked)
	controls.add_child(preserve_pose_button)
	auto_scale_tpose_button = Button.new()
	auto_scale_tpose_button.text = "Auto Scale to T-Pose"
	auto_scale_tpose_button.hide()
	auto_scale_tpose_button.pressed.connect(auto_scale_tpose_button_clicked)
	controls.add_child(auto_scale_tpose_button)
	apply_motion_scale_button = Button.new()
	apply_motion_scale_button.text = "Apply Motion Scale"
	apply_motion_scale_button.hide()
	apply_motion_scale_button.pressed.connect(apply_motion_scale_button_clicked)
	controls.add_child(apply_motion_scale_button)
	align_reset_armature_button = Button.new()
	align_reset_armature_button.text = "Align to RESET Pose"
	align_reset_armature_button.hide()
	align_reset_armature_button.pressed.connect(align_reset_armature_button_clicked)
	controls.add_child(align_reset_armature_button)
	merge_compatible_armature_button = Button.new()
	merge_compatible_armature_button.text = "Merge Armature"
	merge_compatible_armature_button.hide()
	merge_compatible_armature_button.pressed.connect(merge_compatible_armature_button_clicked)
	controls.add_child(merge_compatible_armature_button)

	mirror_pose_button = Button.new()
	mirror_pose_button.toggle_mode = true
	mirror_pose_button.text = "Mirror Mode"
	mirror_pose_button.hide()
	mirror_pose_button.toggled.connect(mirror_pose_button_toggled)
	controls.add_child(mirror_pose_button)
	lock_bone_button = Button.new()
	lock_bone_button.toggle_mode = true
	lock_bone_button.text = "Lock Bone"
	lock_bone_button.hide()
	lock_bone_button.toggled.connect(lock_bone_button_toggled)
	controls.add_child(lock_bone_button)
	rename_bone_dropdown = OptionButton.new()
	rename_bone_dropdown.fit_to_longest_item = false
	rename_bone_dropdown.add_item("Current", -1)
	rename_bone_dropdown.add_item("Original", -2)
	rename_bone_dropdown.add_item("Custom bone name...", -3)
	var sph := SkeletonProfileHumanoid.new()
	for bone_idx in sph.bone_size:
		var bn := sph.get_bone_name(bone_idx)
		if bn.contains("Meta") or bn.contains("Proximal") or bn.contains("Intermed") or bn.contains("Distal"):
			continue
		rename_bone_dropdown.add_item(bn, bone_idx)
	for bone_idx in sph.bone_size:
		var bn := sph.get_bone_name(bone_idx)
		if not (bn.contains("Meta") or bn.contains("Proximal") or bn.contains("Intermed") or bn.contains("Distal")):
			continue
		rename_bone_dropdown.add_item(bn, bone_idx)
	rename_bone_dropdown.hide()
	rename_bone_dropdown.item_selected.connect(bone_name_changed)
	controls.add_child(rename_bone_dropdown)
	controls.hide()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, controls)


func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, controls)
	controls.queue_free()


func connect_skeleton_tree_signal():
	var editor_inspector = get_editor_interface().get_inspector()
	var skeleton_editor: VBoxContainer = null
	for childnode in editor_inspector.find_children("*", "Skeleton3DEditor", true, false):
		skeleton_editor = childnode as VBoxContainer
		for treenode in skeleton_editor.find_children("*", "Tree", true, false):
			var joint_tree := treenode as Tree
			if joint_tree != null:
				joint_tree.connect("item_selected", joint_selected.bind(joint_tree))


func _handles(p_object) -> bool:
	var node: Node3D = p_object as Node3D
	if node != null:
		if node is Skeleton3D:
			select_skeleton(node)
		else:
			hide_control(mirror_pose_button)
			hide_control(lock_bone_button)
			select_skeleton(null)
		for skel_node in node.find_children("*", "Skeleton3D", ):
			var skel := skel_node as Skeleton3D
			if skel == null or skel == node:
				continue
			var par: Node = node
			for i in range(3):
				par = par.get_parent()
				if par == null: break
				if par is Skeleton3D and par != skel:
					merge_armature_selected_node = node
					merge_armature_selected_skel = skel
					merge_armature_selected_target_skel = par
					update_buttons_for_selected_node()
					return false # We don't use _edit
	merge_armature_selected_node = null
	merge_armature_selected_skel = null
	merge_armature_selected_target_skel = null
	update_buttons_for_selected_node()
	return false


func update_buttons_for_selected_node():
	if merge_armature_selected_skel != null and merge_armature_selected_skel.get_script() == null:
		show_control(merge_compatible_armature_button)
		if (merge_armature_selected_skel.motion_scale != 0 and merge_armature_selected_target_skel.motion_scale != 0 and
			not is_equal_approx(merge_armature_selected_skel.motion_scale, merge_armature_selected_target_skel.motion_scale)):
			apply_motion_scale_button.text = "Scale %.3f" % (merge_armature_selected_target_skel.motion_scale / merge_armature_selected_skel.motion_scale)
			show_control(apply_motion_scale_button)
		else:
			hide_control(apply_motion_scale_button)
	else:
		hide_control(merge_compatible_armature_button)
		hide_control(apply_motion_scale_button)
	if merge_armature_selected_skel != null and merge_armature_selected_skel is merged_skeleton_script:
		show_control(auto_scale_tpose_button)
		show_control(align_reset_armature_button)
		show_control(preserve_pose_button)
		show_control(unmerge_armature_button)
	else:
		hide_control(auto_scale_tpose_button)
		hide_control(unmerge_armature_button)
		hide_control(align_reset_armature_button)
		hide_control(preserve_pose_button)


func show_control(control):
	control.show()
	if not controls.visible:
		controls.show()


func hide_control(control):
	if controls.visible:
		control.hide()
		var at_least_one: bool = false
		for child in controls.get_children():
			if child.visible:
				at_least_one = true
		if not at_least_one:
			controls.hide()


func unmerge_armature_button_clicked():
	if merge_armature_selected_node == null:
		return
	var new_child: Node3D = merge_armature_selected_node
	var undoredo := get_undo_redo()
	var created_act: bool = false
	for skel_node in new_child.find_children("*", "Skeleton3D"):
		var skel := skel_node as Skeleton3D
		if skel == null or not skel.has_method(&"detach_skeleton"):
			continue
		if not created_act:
			undoredo.create_action(&"Unerge armatures", UndoRedo.MERGE_ALL, skel)
			created_act = true
		undoredo.add_undo_method(skel, &"set_script", merged_skeleton_script)
		undoredo.add_do_method(skel, &"detach_skeleton")
		undoredo.add_do_method(skel, &"set_script", null)
		undoredo.add_undo_method(self, &"update_buttons_for_selected_node")
		undoredo.add_do_method(self, &"update_buttons_for_selected_node")
	if created_act:
		undoredo.commit_action()


func auto_scale_tpose_button_clicked():
	if merge_armature_selected_node == null:
		return
	var new_child: Node3D = merge_armature_selected_node
	var created_act: bool = false
	var undoredo := get_undo_redo()
	for skel_node in new_child.find_children("*", "Skeleton3D"):
		var skel := skel_node as Skeleton3D
		if skel == null:
			continue
		var par: Node3D = skel.get_parent_node_3d()
		while par != null:
			if par is Skeleton3D:
				break
			par = par.get_parent_node_3d()
		if par != null:
			# No undoredo yet.
			var target_skel := par as Skeleton3D
			if not created_act:
				undoredo.create_action(&"Reset armature poses", UndoRedo.MERGE_ALL, skel)
				created_act = true
			merged_skeleton_script.adjust_pose(skel, target_skel, undoredo)
	if created_act:
		undoredo.commit_action(false) # adjust_pose applies as it goes


func align_reset_armature_button_clicked():
	if merge_armature_selected_node == null:
		return
	var new_child: Node3D = merge_armature_selected_node
	var created_act: bool = false
	var undoredo := get_undo_redo()
	for skel_node in new_child.find_children("*", "Skeleton3D"):
		var skel := skel_node as Skeleton3D
		if skel == null:
			continue
		var par: Node3D = skel.get_parent_node_3d()
		while par != null:
			if par is Skeleton3D:
				break
			par = par.get_parent_node_3d()
		if par != null:
			# This one is difficult to implement undoredo support for, due to playing an animation
			var target_skel := par as Skeleton3D
			if not created_act:
				undoredo.create_action(&"Reset armature poses", UndoRedo.MERGE_ALL, skel)
				created_act = true
			merged_skeleton_script.perform_undoable_reset_bone_poses(undoredo, skel, false)
			play_all_reset_animations(undoredo, skel, target_skel)
			merged_skeleton_script.perform_undoable_reset_bone_poses(undoredo, target_skel, false)
			play_all_reset_animations(undoredo, target_skel, target_skel.owner)
			for bone in skel.get_parentless_bones():
				undoredo.add_undo_method(skel, &"set_bone_pose_scale", bone, skel.get_bone_pose_scale(bone))
				undoredo.add_do_method(skel, &"set_bone_pose_scale", bone, skel.get_bone_pose_scale(bone))
			merged_skeleton_script.preserve_pose(skel, target_skel, undoredo)
	if created_act:
		undoredo.commit_action(true)


func preserve_pose_button_clicked():
	if merge_armature_selected_node == null:
		return
	var new_child: Node3D = merge_armature_selected_node
	var created_act: bool = false
	var undoredo := get_undo_redo()
	for skel_node in new_child.find_children("*", "Skeleton3D"):
		var skel := skel_node as Skeleton3D
		if skel == null:
			continue
		var par: Node3D = skel.get_parent_node_3d()
		while par != null:
			if par is Skeleton3D:
				break
			par = par.get_parent_node_3d()
		if par != null:
			var target_skel := par as Skeleton3D
			if not created_act:
				undoredo.create_action(&"Preserve skeleton pose", UndoRedo.MERGE_ALL, skel)
				created_act = true
			merged_skeleton_script.preserve_pose(skel, target_skel, undoredo)
	if created_act:
		undoredo.commit_action(true)


func record_animation_transforms(root_node: Node, undoredo: EditorUndoRedoManager, reset_anim: Animation):
	for i in range(reset_anim.get_track_count()):
		var path: NodePath = reset_anim.track_get_path(i)
		var bone_name: String = path.get_concatenated_subnames()
		var bone_idx: int = -1
		var node: Node = root_node.get_node(NodePath(str(path.get_concatenated_names()))) as Node
		var node3d: Node3D = node as Node3D
		var skeleton: Skeleton3D = node as Skeleton3D
		if skeleton != null:
			bone_idx = skeleton.find_bone(bone_name)
		match reset_anim.track_get_type(i):
			Animation.TYPE_POSITION_3D:
				var pos: Vector3 = reset_anim.position_track_interpolate(i, 0.0)
				if node3d != null:
					if bone_name.is_empty():
						undoredo.add_undo_property(node3d, &"position", node3d.position)
						undoredo.add_do_property(node3d, &"position", pos)
					elif skeleton != null:
						undoredo.add_undo_method(skeleton, &"set_bone_pose_position", bone_idx, skeleton.get_bone_pose_position(bone_idx))
						undoredo.add_do_method(skeleton, &"set_bone_pose_position", bone_idx, skeleton.motion_scale * pos)
			Animation.TYPE_ROTATION_3D:
				var quat: Quaternion = reset_anim.rotation_track_interpolate(i, 0.0)
				if node3d != null:
					if bone_name.is_empty():
						undoredo.add_undo_property(node3d, &"quaternion", node3d.quaternion)
						undoredo.add_do_property(node3d, &"quaternion", quat)
					elif skeleton != null:
						undoredo.add_undo_method(skeleton, &"set_bone_pose_rotation", bone_idx, skeleton.get_bone_pose_rotation(bone_idx))
						undoredo.add_do_method(skeleton, &"set_bone_pose_rotation", bone_idx, quat)
			Animation.TYPE_SCALE_3D:
				var scl: Vector3 = reset_anim.scale_track_interpolate(i, 0.0)
				if node3d != null:
					if bone_name.is_empty():
						undoredo.add_undo_property(node3d, &"scale", node3d.scale)
						undoredo.add_do_property(node3d, &"scale", scl)
					elif skeleton != null:
						undoredo.add_undo_method(skeleton, &"set_bone_pose_scale", bone_idx, skeleton.get_bone_pose_scale(bone_idx))
						undoredo.add_do_method(skeleton, &"set_bone_pose_scale", bone_idx, scl)
			Animation.TYPE_BLEND_SHAPE:
				var bs: float = reset_anim.blend_shape_track_interpolate(i, 0.0)
				var mesh: MeshInstance3D = node as MeshInstance3D
				if mesh != null and not bone_name.is_empty():
					var prop := StringName("blend_shapes/" + bone_name)
					var cur_val: Variant = mesh.get(prop)
					if typeof(cur_val) == TYPE_FLOAT:
						undoredo.add_undo_property(mesh, prop, cur_val)
						undoredo.add_do_property(node3d, prop, bs)
					else:
						push_warning("Blend Shape property " + str(path) + " is not float: " + str(cur_val))


func play_all_reset_animations(undoredo: EditorUndoRedoManager, node: Node3D, toplevel_node: Node):
	while node != null:
		for anim_player in node.find_children("*", "AnimationPlayer", false, true):
			if anim_player.has_animation(&"RESET"):
				var root_node: Node = anim_player.get_node(anim_player.root_node)
				var reset_anim: Animation = anim_player.get_animation(&"RESET")
				if reset_anim != null and root_node != null:
					record_animation_transforms(root_node, undoredo, reset_anim)
		if node == toplevel_node:
			break
		node = node.get_parent_node_3d()


func apply_motion_scale_button_clicked():
	if merge_armature_selected_node == null:
		return
	var new_child: Node3D = merge_armature_selected_node
	var created_act: bool = false
	var undoredo := get_undo_redo()
	for skel_node in new_child.find_children("*", "Skeleton3D"):
		var skel := skel_node as Skeleton3D
		if skel == null:
			continue
		var par: Node3D = skel.get_parent_node_3d()
		while par != null:
			if par is Skeleton3D:
				break
			par = par.get_parent_node_3d()
		var target_skel := par as Skeleton3D
		if target_skel != null:
			if skel.motion_scale != 0 and target_skel.motion_scale != 0 and not is_equal_approx(skel.motion_scale, target_skel.motion_scale):
				if not created_act:
					undoredo.create_action(&"Apply motion scale", UndoRedo.MERGE_ALL, skel)
					created_act = true
				var scale_ratio: float = target_skel.motion_scale / skel.motion_scale
				undoredo.add_undo_property(skel, &"motion_scale", skel.motion_scale)
				undoredo.add_do_property(skel, &"motion_scale", target_skel.motion_scale)
				undoredo.add_undo_method(self, &"update_buttons_for_selected_node")
				undoredo.add_do_method(self, &"update_buttons_for_selected_node")
				for bone in skel.get_parentless_bones():
					var new_scale: Vector3 = skel.get_bone_pose_scale(bone) * scale_ratio
					undoredo.add_undo_method(skel, &"set_bone_pose_scale", bone, skel.get_bone_pose_scale(bone))
					undoredo.add_do_method(skel, &"set_bone_pose_scale", bone, new_scale)
					var rest_mat: Transform3D = skel.get_bone_rest(bone)
					undoredo.add_undo_method(skel, &"set_bone_rest", bone, rest_mat)
					rest_mat.basis = rest_mat.basis.scaled(Vector3.ONE * scale_ratio)
					undoredo.add_do_method(skel, &"set_bone_rest", bone, rest_mat)
	if created_act:
		undoredo.commit_action(true)
	hide_control(apply_motion_scale_button)


func merge_compatible_armature_button_clicked():
	if merge_armature_selected_node == null:
		return
	var new_child: Node3D = merge_armature_selected_node
	if not new_child.scene_file_path.is_empty():
		new_child.owner.set_editable_instance(new_child, true)
		new_child.set_display_folded(false)
		new_child.name = new_child.name # WAT. the scene tree doesn't update otherwise.

	for anim in new_child.find_children("*", "AnimationPlayer"):
		anim.reset_on_save = false
	for anim in new_child.find_children("*", "AnimationTree"):
		anim.active = false
	# New 4.2 types:
	for anim in new_child.find_children("*", "AnimationMixer"):
		anim.set("reset_on_save", false)
		anim.set("active", false)

	var showing_warning: bool = false
	for skel_node in new_child.find_children("*", "Skeleton3D"):
		var skel := skel_node as Skeleton3D
		if skel == null:
			continue
		skel.set_display_folded(true)
		if skel.get_script() == null:
			var par: Node3D = skel.get_parent_node_3d()
			while par != null:
				if par is Skeleton3D:
					break
				par = par.get_parent_node_3d()
			if par != null:
				var relative_basis := Basis.IDENTITY
				var tmpnode: Node3D = skel
				while tmpnode != null and tmpnode != par:
					relative_basis = tmpnode.basis * relative_basis
					tmpnode = tmpnode.get_parent_node_3d()
				print(relative_basis)
				if not relative_basis.is_equal_approx(Basis.IDENTITY) and not showing_warning:
					var cd := ConfirmationDialog.new()
					print("DO SHOW A WARNING")
					cd.title = "Merge Armature"
					if relative_basis.get_rotation_quaternion().is_equal_approx(Quaternion.IDENTITY):
						cd.dialog_text = (
							"The skeleton you are merging has a non-identity scale.\n" +
							"This may lead to glitches with additional bones and dynamics.\n\n" +
							"It is recommended to enable humanoid retargeting on the Skeleton3D in the import settings."
						)
					else:
						cd.dialog_text = (
							"The skeleton you are merging has not been retargeted and is unsupported.\n" +
							"Many features will function incorrectly.\n\n" +
							"Please enable humanoid retargeting on the Skeleton3D in the import settings."
						)
					cd.ok_button_text = "Continue anyway"
					cd.transient = true
					cd.confirmed.connect(_confirmed_merge_armature)
					add_child(cd)
					cd.popup_centered()
					showing_warning = true
	if not showing_warning:
		_confirmed_merge_armature()

func _confirmed_merge_armature():
	var created_act := false
	var undoredo := get_undo_redo()

	for skel_node in merge_armature_selected_node.find_children("*", "Skeleton3D"):
		var skel := skel_node as Skeleton3D
		if skel == null:
			continue
		skel.set_display_folded(true)
		if skel.get_script() == null:
			var par: Node3D = skel.get_parent_node_3d()
			while par != null:
				if par is Skeleton3D:
					break
				par = par.get_parent_node_3d()
			if par != null:
				var target_skel := par as Skeleton3D
				if not created_act:
					created_act = true
					undoredo.create_action(&"Merge armatures", UndoRedo.MERGE_DISABLE, skel)
				var rel_scale := Vector3.ONE
				var scale_par: Node3D = skel.get_parent()
				while scale_par != target_skel:
					undoredo.add_undo_property(scale_par, &"transform", scale_par.transform)
					undoredo.add_do_property(scale_par, &"transform", Transform3D.IDENTITY)
					rel_scale *= scale_par.scale
					scale_par = scale_par.get_parent()
				var scale_ratio: float = sqrt(3) / rel_scale.length()
				undoredo.add_undo_property(skel, &"transform", skel.transform)
				undoredo.add_do_property(skel, &"transform", Transform3D.IDENTITY)
				# Clear out any motion scale difference.
				undoredo.add_undo_property(skel, &"motion_scale", skel.motion_scale)
				undoredo.add_do_property(skel, &"motion_scale", target_skel.motion_scale)
				for bone in skel.get_parentless_bones():
					var new_scale: Vector3 = skel.get_bone_pose_scale(bone) / scale_ratio
					undoredo.add_undo_method(skel, &"set_bone_pose_scale", bone, skel.get_bone_pose_scale(bone))
					undoredo.add_do_method(skel, &"set_bone_pose_scale", bone, new_scale)
				undoredo.add_undo_method(skel, &"detach_skeleton")
				undoredo.add_undo_method(skel, &"set_script", skel.get_script())
				undoredo.add_do_method(skel, &"set_script", merged_skeleton_script)
				undoredo.add_undo_method(self, &"update_buttons_for_selected_node")
				undoredo.add_do_method(self, &"update_buttons_for_selected_node")
	if created_act:
		undoredo.commit_action()


func get_mirrored_bone_name(bone_name: String) -> String:
	var target_bone_name := ""
	if bone_name.begins_with("Left"):
		target_bone_name = "Right" + bone_name.substr(4)
	elif bone_name.begins_with("Right"):
		target_bone_name = "Left" + bone_name.substr(5)
	elif bone_name.contains("Left"):
		target_bone_name = bone_name.replace("Left", "Right")
	elif bone_name.contains("Right"):
		target_bone_name = bone_name.replace("Right", "Left")
	elif bone_name.contains("left"):
		target_bone_name = bone_name.replace("left", "right")
	elif bone_name.contains("right"):
		target_bone_name = bone_name.replace("right", "left")
	elif bone_name.contains("左"):
		target_bone_name = bone_name.replace("左", "右")
	elif bone_name.contains("右"):
		target_bone_name = bone_name.replace("右", "左")
	elif bone_name.contains("L"):
		target_bone_name = bone_name.replace("L", "R")
	elif bone_name.contains("R"):
		target_bone_name = bone_name.replace("R", "L")
	return target_bone_name


func mirror_pose_button_toggled(toggle: bool):
	var undo_redo := get_undo_redo()
	if toggle and selected_skel != null:
		undo_redo.create_action("Mirror Pose turned on at " + str(selected_bone_name), UndoRedo.MERGE_ALL, selected_skel)
		undo_redo.add_undo_method(self, &"set_mirror_bone_mode", last_mirror_bone_idx, mirror_bone_mode, selected_skel)
		if selected_bone_idx != -1:
			undo_redo.add_undo_method(selected_skel, &"set_bone_pose_position", selected_bone_idx, selected_skel.get_bone_pose_position(selected_bone_idx))
			undo_redo.add_undo_method(selected_skel, &"set_bone_pose_rotation", selected_bone_idx, selected_skel.get_bone_pose_rotation(selected_bone_idx))
			undo_redo.add_undo_method(selected_skel, &"set_bone_pose_scale", selected_bone_idx, selected_skel.get_bone_pose_scale(selected_bone_idx))
			var mirrored_bone_idx = selected_skel.find_bone(get_mirrored_bone_name(selected_bone_name))
			if mirrored_bone_idx != -1 and (mirrored_bone_idx != last_mirror_bone_idx or not mirror_bone_mode):
				undo_redo.add_undo_method(selected_skel, &"set_bone_pose_position", mirrored_bone_idx, selected_skel.get_bone_pose_position(mirrored_bone_idx))
				undo_redo.add_undo_method(selected_skel, &"set_bone_pose_rotation", mirrored_bone_idx, selected_skel.get_bone_pose_rotation(mirrored_bone_idx))
				undo_redo.add_undo_method(selected_skel, &"set_bone_pose_scale", mirrored_bone_idx, selected_skel.get_bone_pose_scale(mirrored_bone_idx))
		undo_redo.add_do_method(self, &"set_mirror_bone_mode", selected_bone_idx, true, selected_skel)
		undo_redo.commit_action()
	else:
		undo_redo.create_action("Mirror Pose turned off", UndoRedo.MERGE_ALL, selected_skel)
		undo_redo.add_undo_method(self, &"set_mirror_bone_mode", last_mirror_bone_idx, mirror_bone_mode, selected_skel)
		undo_redo.add_do_method(self, &"set_mirror_bone_mode", selected_bone_idx, false, selected_skel)
		undo_redo.commit_action()


func set_mirror_bone_mode(bone_idx: int, toggle: bool, skel: Skeleton3D = null):
	if skel != null and skel != selected_skel:
		set_selected_skel(skel)
	mirror_pose_button.set_pressed_no_signal(toggle and bone_idx == selected_bone_idx)
	mirror_bone_mode = toggle
	last_mirror_bone_idx = bone_idx
	if mirror_bone_mode and bone_idx != -1:
		on_skeleton_poses_changed(true)


func lock_bone_button_toggled(toggle: bool):
	var undo_redo := get_undo_redo()
	if selected_skel != null:
		undo_redo.create_action("Lock Bone turned " + ("on" if toggle else "off"), UndoRedo.MERGE_ALL, selected_skel)
		undo_redo.add_undo_method(self, &"set_lock_bone_mode", lock_bone_mode, selected_skel)
		undo_redo.add_do_method(self, &"set_lock_bone_mode", toggle, selected_skel)
		undo_redo.commit_action()
	#set_lock_bone_mode(toggle)


func set_lock_bone_mode(toggle: bool, skel: Skeleton3D = null):
	if skel != null and skel != selected_skel:
		set_selected_skel(skel)
	lock_bone_mode = toggle
	lock_bone_button.set_pressed_no_signal(toggle)
	record_locked_bone_transforms()


func record_locked_bone_transforms():
	locked_bone_bunny_positions.resize(selected_skel.get_bone_count())
	locked_bone_bunny_rotations.resize(selected_skel.get_bone_count())
	locked_bone_bunny_rot_scales.resize(selected_skel.get_bone_count())
	for i in range(selected_skel.get_bone_count()):
		var par_i := selected_skel.get_bone_parent(i)
		if par_i != -1:
			locked_bone_bunny_positions[i] = selected_skel.get_bone_pose(par_i) * selected_skel.get_bone_pose_position(i)
			locked_bone_bunny_rotations[i] = selected_skel.get_bone_pose_rotation(par_i).normalized() * selected_skel.get_bone_pose_rotation(i).normalized()
			locked_bone_bunny_rot_scales[i] = Basis.from_scale(selected_skel.get_bone_pose_scale(par_i)) * selected_skel.get_bone_pose(i).basis


func disconn_possibly_freed():
	if selected_skel != null and is_instance_valid(selected_skel) and selected_skel.has_signal(&"updated_skeleton_pose"):
		selected_skel.updated_skeleton_pose.disconnect(on_skeleton_poses_changed)


func select_skeleton(skel: Skeleton3D):
	var undo_redo := get_undo_redo()
	hide_control(rename_bone_dropdown)
	if skel != null and skel.has_signal(&"updated_skeleton_pose"):
		connect_skeleton_tree_signal.call_deferred()
		if lock_bone_mode or mirror_bone_mode:
			undo_redo.create_action("Select skeleton", UndoRedo.MERGE_ALL, skel)
			undo_redo.add_undo_method(self, &"set_selected_skel", selected_skel)
			if selected_skel != null:
				if not selected_bone_name.is_empty():
					undo_redo.add_undo_method(self, &"set_selected_joint_name", selected_bone_name, true)
				if lock_bone_mode:
					undo_redo.add_undo_method(self, &"set_lock_bone_mode", true, selected_skel)
				if mirror_bone_mode:
					undo_redo.add_undo_method(self, &"set_mirror_bone_mode", selected_bone_idx, true, selected_skel)
			undo_redo.add_do_method(self, &"set_selected_skel", skel)
			if skel:
				if lock_bone_mode:
					undo_redo.add_do_method(self, &"set_lock_bone_mode", true, skel)
				if mirror_bone_mode:
					undo_redo.add_do_method(self, &"set_mirror_bone_mode", -1, true, skel)
			undo_redo.commit_action()
		else:
			set_selected_skel(skel)
		show_control(mirror_pose_button)
		show_control(lock_bone_button)
	elif selected_skel != null and (lock_bone_mode or mirror_bone_mode):
		undo_redo.create_action("Select skeleton", UndoRedo.MERGE_ALL, skel)
		undo_redo.add_undo_method(self, &"set_selected_skel", selected_skel)
		if not selected_bone_name.is_empty():
			undo_redo.add_undo_method(self, &"set_selected_joint_name", selected_bone_name, true)
		if lock_bone_mode:
			undo_redo.add_undo_method(self, &"set_lock_bone_mode", true, selected_skel)
		if mirror_bone_mode:
			undo_redo.add_undo_method(self, &"set_mirror_bone_mode", selected_bone_idx, true, selected_skel)
		undo_redo.add_do_method(self, &"set_selected_skel", null)
		undo_redo.commit_action()


func set_selected_skel(skel: Variant):
	if skel != selected_skel:
		disconn_possibly_freed()
		hide_control(mirror_pose_button)
		hide_control(lock_bone_button)
		mirror_bone_mode = false
		lock_bone_mode = false
		mirror_pose_button.set_pressed_no_signal(false)
		lock_bone_button.set_pressed_no_signal(false)
	if skel == null:
		selected_skel = null
		return
	selected_skel = skel
	last_pose_positions.resize(selected_skel.get_bone_count())
	last_pose_rotations.resize(selected_skel.get_bone_count())
	last_pose_scales.resize(selected_skel.get_bone_count())
	for i in range(selected_skel.get_bone_count()):
		last_pose_positions[i] = selected_skel.get_bone_pose_position(i)
		last_pose_rotations[i] = selected_skel.get_bone_pose_rotation(i)
		last_pose_scales[i] = selected_skel.get_bone_pose_scale(i)
	if not selected_skel.updated_skeleton_pose.is_connected(on_skeleton_poses_changed):
		selected_skel.updated_skeleton_pose.connect(on_skeleton_poses_changed, CONNECT_DEFERRED)
	if lock_bone_mode:
		record_locked_bone_transforms()


func joint_selected(joint_tree: Tree):
	selected_bone_name = str(joint_tree.get_selected().get_text(0))
	if get_editor_interface().get_inspector().has_method(&"get_edited_object"):
		var edited_object = get_editor_interface().get_inspector().get_edited_object()
		if edited_object != null and edited_object is Skeleton3D and edited_object != selected_skel:
			select_skeleton(edited_object as Skeleton3D)
	rename_bone_dropdown.size = Vector2(50, 0)
	show_control(rename_bone_dropdown)
	set_selected_joint_name(selected_bone_name)


func set_selected_joint_name(bone_name: String, from_undo: bool = false):
	selected_bone_name = bone_name
	print("Selected " + selected_bone_name + " -> " + str(selected_skel.has_meta("renamed_bones")))
	if selected_skel.has_meta("renamed_bones"):
		rename_bone_dropdown.set_item_text(0, "Rebind " + selected_skel.get_meta("renamed_bones").get(selected_bone_name, selected_bone_name))
	else:
		rename_bone_dropdown.set_item_text(0, "Rebind " + selected_bone_name)
	rename_bone_dropdown.set_item_text(1, "Revert bone bind to " + selected_bone_name)
	rename_bone_dropdown.selected = 0
	selected_bone_idx = selected_skel.find_bone(selected_bone_name)
	# print("Selected bone " + str(selected_bone_name) + " index " + str(selected_bone_idx))
	if lock_bone_mode:
		record_locked_bone_transforms()
	if mirror_bone_mode:
		if from_undo:
			set_mirror_bone_mode(selected_bone_idx, true, selected_skel)
		else:
			mirror_pose_button_toggled(true)


func bone_name_changed(idx):
	var new_id := rename_bone_dropdown.get_item_id(idx)
	var orig_name: String = selected_bone_name
	if not selected_skel.has_meta("renamed_bones"):
		selected_skel.set_meta("renamed_bones", {})
	var new_name: String = selected_skel.get_meta("renamed_bones").get(orig_name, orig_name)
	if new_id == -1:
		return
	elif new_id == -2:
		new_name = orig_name
	elif new_id == -3:
		var ad := ConfirmationDialog.new()
		var line_edit := LineEdit.new()
		line_edit.placeholder_text = orig_name
		line_edit.text = new_name
		ad.add_child(line_edit)
		ad.register_text_enter(line_edit)
		ad.ok_button_text = "Rename " + str(orig_name)
		ad.confirmed.connect(bone_name_confirmed.bind(ad, line_edit))
		ad.canceled.connect(ad.queue_free)
		add_child(ad)
		ad.show()
		ad.popup_centered_clamped()
		return
	elif new_id > 0:
		var sph := SkeletonProfileHumanoid.new()
		new_name = sph.get_bone_name(new_id)
	print("Rebind " + selected_bone_name + " / " + new_name)
	rename_bone_name(new_name)


func bone_name_confirmed(ad: ConfirmationDialog, line_edit: LineEdit):
	if not line_edit.text.strip_edges().is_empty():
		rename_bone_name(line_edit.text.strip_edges())
	ad.queue_free()


func rename_bone_name(new_name: String):
	selected_skel.get_meta("renamed_bones")[selected_bone_name] = new_name
	rename_bone_dropdown.set_item_text(0, new_name)
	rename_bone_dropdown.selected = 0
	var unique_skins = selected_skel.get(&"unique_skins") as Array[Skin]
	if not unique_skins:
		return
	for skin in unique_skins:
		var orig_skin_meta := skin.get_meta(&"orig_skin") as Skin
		if orig_skin_meta != null:
			for i in range(orig_skin_meta.get_bind_count()):
				var bn := orig_skin_meta.get_bind_name(i)
				if bn.is_empty():
					var bb := orig_skin_meta.get_bind_bone(i)
					if bb == -1:
						continue
					bn = selected_skel.get_bone_name(bb)
				if bn == selected_bone_name:
					skin.set_bind_name(i, new_name)
	# Force an update of our state.
	selected_skel.set("last_pose_positions", PackedVector3Array())
	last_pose_positions = PackedVector3Array()
	selected_skel.propagate_notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)


# Mirror mode and bone child locking implementation:
func perform_bone_mirror(changed_indices: PackedInt32Array) -> PackedInt32Array:
	var new_changed: PackedInt32Array
	for bone_idx in changed_indices:
		var mirrored_bone_name = get_mirrored_bone_name(selected_skel.get_bone_name(bone_idx))
		if mirrored_bone_name.is_empty():
			continue
		var mirrored_bone_idx = selected_skel.find_bone(mirrored_bone_name)
		if mirrored_bone_idx == -1:
			continue
		# print("Mirroring pose from " + str(selected_skel.get_bone_name(bone_idx)) + " to " + str(mirrored_bone_name))
		var pos := selected_skel.get_bone_pose_position(bone_idx)
		pos.x = -pos.x
		var orig_pos := selected_skel.get_bone_pose_position(mirrored_bone_idx)
		var quat := selected_skel.get_bone_pose_rotation(bone_idx)
		quat.x = -quat.x
		quat.w = -quat.w
		var orig_quat := selected_skel.get_bone_pose_rotation(mirrored_bone_idx)
		var scale := selected_skel.get_bone_pose_scale(bone_idx)
		var orig_scale := selected_skel.get_bone_pose_scale(mirrored_bone_idx)
		if not pos.is_equal_approx(orig_pos) or not quat.is_equal_approx(orig_quat) or not scale.is_equal_approx(orig_scale):
			disable_next_update = true
			selected_skel.set_bone_pose_position(mirrored_bone_idx, pos)
			selected_skel.set_bone_pose_rotation(mirrored_bone_idx, quat)
			selected_skel.set_bone_pose_scale(mirrored_bone_idx, scale)
			new_changed.append(mirrored_bone_idx)
	return new_changed


func perform_bone_lock(changed_indices: PackedInt32Array):
	for lock_current_bone_idx in changed_indices:
		var bone_children := selected_skel.get_bone_children(lock_current_bone_idx)
		var new_scale := selected_skel.get_bone_pose_scale(lock_current_bone_idx)
		var orig_scale := last_pose_scales[lock_current_bone_idx]
		#if ((orig_scale.x < 0 or orig_scale.y < 0 or orig_scale.z < 0 or orig_scale.is_zero_approx()) or
			#(new_scale.x < 0 or new_scale.y < 0 or new_scale.z < 0 or new_scale.is_zero_approx()) or
			#bone_children.is_empty()):
		if orig_scale.is_zero_approx() or new_scale.is_zero_approx() or bone_children.is_empty():
			continue
		var new_pos := selected_skel.get_bone_pose_position(lock_current_bone_idx)
		var new_rot := selected_skel.get_bone_pose_rotation(lock_current_bone_idx)
		var new_xform := selected_skel.get_bone_pose(lock_current_bone_idx)
		var orig_pos := last_pose_positions[lock_current_bone_idx]
		var orig_rot := last_pose_rotations[lock_current_bone_idx]
		disable_next_update = true
		if not orig_pos.is_equal_approx(new_pos) or not orig_scale.is_equal_approx(new_scale) or not orig_rot.is_equal_approx(new_rot):
			# position changed.
			for child_idx in bone_children:
				disable_next_update = true
				selected_skel.set_bone_pose_position(child_idx, new_xform.affine_inverse() * locked_bone_bunny_positions[child_idx])
		if not orig_rot.is_equal_approx(new_rot):
			# Pos or rotation changed.
			for child_idx in bone_children:
				disable_next_update = true
				selected_skel.set_bone_pose_rotation(child_idx, new_rot.normalized().inverse() * locked_bone_bunny_rotations[child_idx].normalized())
		if not orig_scale.is_equal_approx(new_scale) or not orig_rot.is_equal_approx(new_rot):
			# Scale changed.
			for child_idx in bone_children:
				disable_next_update = true
				selected_skel.set_bone_pose_scale(child_idx, (Basis.from_scale(new_xform.basis.get_scale()).inverse() * locked_bone_bunny_rot_scales[child_idx]).get_scale())
				#selected_skel.set_bone_pose_scale(child_idx, (Basis(selected_skel.get_bone_pose_rotation(child_idx).inverse()) * Basis.from_scale(new_scale).inverse() * locked_bone_bunny_rot_scales[child_idx]).get_scale())
				#set_bone_pose_scale(child_idx, (new_xform.basis.inverse() * orig_xform.basis * get_bone_pose(child_idx).basis).get_scale())
		last_pose_positions[lock_current_bone_idx] = new_pos
		last_pose_rotations[lock_current_bone_idx] = new_rot
		last_pose_scales[lock_current_bone_idx] = new_scale


func on_skeleton_poses_changed(force_mirror: bool = false):
	var changed_indices: PackedInt32Array
	if lock_bone_mode or mirror_bone_mode:
		last_pose_positions.resize(selected_skel.get_bone_count())
		last_pose_rotations.resize(selected_skel.get_bone_count())
		last_pose_scales.resize(selected_skel.get_bone_count())
		for i in range(selected_skel.get_bone_count()):
			if (last_pose_positions[i] != selected_skel.get_bone_pose_position(i) or
					last_pose_rotations[i] != selected_skel.get_bone_pose_rotation(i) or
					last_pose_scales[i] != selected_skel.get_bone_pose_scale(i)):
				changed_indices.append(i)
	# Godot may infinite loop if two NOTIFICATION_UPDATE_SKELETON somehow get deferred and we then
	# perform anything that hits the dirty flag (such as set_bone_pose_position or skin changes)
	# To prevent this, we have to abort early to prevent queuing another NOTIFICIATION_UPDATE_SKELETON.
	if not force_mirror and (disable_next_update or changed_indices.is_empty()):
		disable_next_update = false
		return
	if mirror_bone_mode:
		if force_mirror or not (last_pose_positions[last_mirror_bone_idx].is_equal_approx(selected_skel.get_bone_pose_position(last_mirror_bone_idx)) and
				last_pose_rotations[last_mirror_bone_idx].is_equal_approx(selected_skel.get_bone_pose_rotation(last_mirror_bone_idx)) and
				last_pose_scales[last_mirror_bone_idx].is_equal_approx(selected_skel.get_bone_pose_scale(last_mirror_bone_idx))):
			changed_indices.append_array(perform_bone_mirror(PackedInt32Array([last_mirror_bone_idx])))
	if lock_bone_mode or mirror_bone_mode:
		if lock_bone_mode:
			perform_bone_lock(changed_indices)
		for i in range(selected_skel.get_bone_count()):
			last_pose_positions[i] = selected_skel.get_bone_pose_position(i)
			last_pose_rotations[i] = selected_skel.get_bone_pose_rotation(i)
			last_pose_scales[i] = selected_skel.get_bone_pose_scale(i)
