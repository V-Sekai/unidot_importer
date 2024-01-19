# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

const tarfile = preload("./tarfile.gd")

const package_import_dialog_class: GDScript = preload("./package_import_dialog.gd")

var package_import_dialog: RefCounted = null
var last_selected_dir: String = ""
var file_dialog_mode := EditorFileDialog.DISPLAY_LIST

var skeleton_editor: VBoxContainer
var controls : HBoxContainer
var merge_armature_button: Button
var mirror_pose_button: Button
var lock_bone_button: Button
var rename_bone_button: Button
var rename_bone_dropdown: OptionButton
var selected_skel: Skeleton3D
var merge_armature_selected_node: Node3D


func recursive_print(node: Node, indent: String = ""):
	var fnstr = "" if str(node.filename) == "" else (" (" + str(node.filename) + ")")
	print(indent + str(node.name) + ": owner=" + str(node.owner.name if node.owner != null else "") + fnstr)
	#print(indent + str(node.name) + str(node) + ": owner=" + str(node.owner.name if node.owner != null else "") + str(node.owner) + fnstr)
	var new_indent: String = indent + "  "
	for c in node.get_children():
		recursive_print(c, new_indent)


func queue_test():
	var queue_lib: GDScript = load("./queue_lib.gd")
	var q = queue_lib.new()
	q.run_test()


func show_reimport():
	if package_import_dialog != null and package_import_dialog.paused:
		package_import_dialog.show_importer_logs()
		return
	package_import_dialog = package_import_dialog_class.new()
	package_import_dialog.show_reimport(self)


func show_importer():
	if package_import_dialog != null and package_import_dialog.paused:
		package_import_dialog.show_importer_logs()
		return
	package_import_dialog = package_import_dialog_class.new()
	package_import_dialog.show_importer(self)

func show_importer_logs():
	if package_import_dialog != null:
		package_import_dialog.show_importer_logs()

func do_reimport_previous_files():
	if package_import_dialog != null:
		package_import_dialog.do_reimport_previous_files()

func recursive_print_scene():
	recursive_print(get_tree().edited_scene_root)


func anim_import():
	const uoa = preload("./object_adapter.gd")
	for anim_tres in get_editor_interface().get_selected_paths():
		var nod = get_editor_interface().get_selection().get_selected_nodes()[0] # as AnimationMixer
		var anim_raw = ResourceLoader.load(anim_tres)
		anim_raw.meta.initialize(preload("./asset_database.gd").new().get_singleton())
		for obj in anim_raw.objects:
			if obj.ends_with(":AnimationClip"):
				if nod != null:
					nod.get_animation_library("").remove_animation(anim_raw.objects[obj]["m_Name"])
				var ac = uoa.new().instantiate_unidot_object_from_utype(anim_raw.meta, obj.split(":")[0].to_int(), 74)
				ac.keys = anim_raw.objects[obj]
				var animator = uoa.new().instantiate_unidot_object_from_utype(anim_raw.meta, 1234, 95)
				#var animgo = uoa.new().instantiate_unidot_object_from_utype(anim_raw.meta, 1234, 1)
				#var animtr = uoa.new().instantiate_unidot_object_from_utype(anim_raw.meta, 1234, 4)
				var anim = ac.create_animation_clip_at_node(animator, null)
				anim.take_over_path(anim_raw.meta.path)
				ResourceSaver.save(anim, anim_raw.meta.path)
				if nod != null:
					nod.get_animation_library("").add_animation(anim_raw.objects[obj]["m_Name"], anim)

func _enter_tree():
	# print("run enter tree")
	var es = get_editor_interface().get_editor_settings()
	var ep = get_editor_interface().get_editor_paths()
	var data_parent = ep.get_data_dir().get_base_dir()
	if OS.get_name() == "macOS" and data_parent.get_base_dir().get_file().to_lower() == "library":
		data_parent = data_parent.get_base_dir()
	for f in DirAccess.get_directories_at(data_parent):
		if f.to_lower().begins_with("uni"):
			var subf_found = ""
			for subf in DirAccess.get_directories_at(data_parent.path_join(f)):
				if subf.to_lower().begins_with("asset store") and len(subf) > 11:
					subf_found = subf
			if not subf_found.is_empty():
				data_parent = data_parent.path_join(f).path_join(subf_found)
				break
	var fav = es.get_favorites()
	if fav.count(data_parent + "/") == 0:
		fav.append(data_parent + "/")
		es.set_favorites(fav)
	fav = es.get_recent_dirs()
	if fav.count(data_parent) == 0:
		fav.append(data_parent)
		es.set_recent_dirs(fav)

	add_tool_menu_item("Import .unitypackage or dir with Unidot...", self.show_importer)
	#add_tool_menu_item("Reimport previous files", self.do_reimport_previous_files)
	add_tool_menu_item("Reimport extracted .unitypackage...", self.show_reimport)
	add_tool_menu_item("Show last Unidot import logs", self.show_importer_logs)
	#add_tool_menu_item("Debug Anim", self.anim_import)
	#add_tool_menu_item("Queue Test...", self.queue_test)
	#add_tool_menu_item("Print scene nodes with owner...", self.anim_import) # self.recursive_print_scene)
	controls = HBoxContainer.new()
	merge_armature_button = Button.new()
	merge_armature_button.text = "Merge to Parent"
	merge_armature_button.hide()
	merge_armature_button.pressed.connect(merge_armature_button_clicked)
	controls.add_child(merge_armature_button)
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
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, controls)

func _exit_tree():
	# print("run exit tree")
	#remove_tool_menu_item("Print scene nodes with owner...")
	#remove_tool_menu_item("Reimport previous files")
	remove_tool_menu_item("Import .unitypackage or dir with Unidot...")
	remove_tool_menu_item("Reimport extracted .unitypackage...")
	remove_tool_menu_item("Show last Unidot import logs")
	#remove_tool_menu_item("Debug Anim")
	#remove_tool_menu_item("Queue Test...")
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


func _handles(p_object: Variant) -> bool:
	var node: Node3D = p_object as Node3D
	if node != null:
		if node is Skeleton3D:
			select_skeleton(node)
		else:
			mirror_pose_button.hide()
			lock_bone_button.hide()
			select_skeleton(null)
		for skel_node in node.find_children("*", "Skeleton3D", ):
			var skel := skel_node as Skeleton3D
			if skel == null or skel == node:
				continue
			var par: Node = node
			for i in range(3):
				par = par.get_parent()
				if par == null: break
				if par is Skeleton3D and par.name == "GeneralSkeleton" and par != skel:
					if skel.get_script() == null:
						merge_armature_selected_node = node
						merge_armature_button.show()
						return true
	merge_armature_selected_node = null
	merge_armature_button.hide()
	return false

func _make_visible(visible: bool):
	if merge_armature_button != null:
		pass

func merge_armature_button_clicked():
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

	for skel_node in new_child.find_children("*", "Skeleton3D"):
		var skel := skel_node as Skeleton3D
		if skel == null:
			continue
		skel.set_display_folded(true)
		if skel.get_script() == null:
			# print("Attaching merged_skeleton script to " + str(get_path_to(new_child)))
			var script: Resource = get_script()
			skel.set_script(load(script.resource_path.get_base_dir().path_join("runtime").path_join("merged_skeleton.gd")))


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


func disconn_possibly_freed():
	if selected_skel != null and selected_skel.has_signal(&"updated_skeleton_pose"):
		selected_skel.updated_skeleton_pose.disconnect(on_skeleton_poses_changed)


func select_skeleton(skel: Skeleton3D):
	var undo_redo := get_undo_redo()
	rename_bone_dropdown.hide()
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
		mirror_pose_button.show()
		lock_bone_button.show()
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
		mirror_pose_button.hide()
		lock_bone_button.hide()
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
	selected_skel.updated_skeleton_pose.connect(on_skeleton_poses_changed, CONNECT_DEFERRED)
	if lock_bone_mode:
		record_locked_bone_transforms()


func joint_selected(joint_tree: Tree):
	selected_bone_name = str(joint_tree.get_selected().get_text(0))
	var edited_object := get_editor_interface().get_inspector().get_edited_object()
	if edited_object != null and edited_object is Skeleton3D and edited_object != selected_skel:
		select_skeleton(edited_object as Skeleton3D)
	rename_bone_dropdown.size = Vector2(50, 0)
	rename_bone_dropdown.show()
	set_selected_joint_name(selected_bone_name)


func set_selected_joint_name(bone_name: String, from_undo: bool = false):
	selected_bone_name = bone_name
	if selected_skel.has_meta("renamed_bones"):
		rename_bone_dropdown.set_item_text(0, "Rebind " + selected_skel.get_meta("renamed_bones").get(selected_bone_name, selected_bone_name))
	else:
		rename_bone_dropdown.set_item_text(0, "Rebind " + selected_bone_name)
	rename_bone_dropdown.set_item_text(1, "Revert bone bind to " + selected_bone_name)
	rename_bone_dropdown.selected = 0
	selected_bone_idx = selected_skel.find_bone(selected_bone_name)
	# print("Selected bone " + str(selected_bone_name) + " index " + str(selected_bone_idx))
	if mirror_bone_mode:
		if from_undo:
			set_mirror_bone_mode(selected_bone_idx, true, selected_skel)
		else:
			mirror_pose_button_toggled(true)
	if lock_bone_mode:
		record_locked_bone_transforms()
	#if get_mirrored_bone_index(selected_skel, selected_bone_name) != -1:
		#mirror_pose_button.show()
	#else:
		#mirror_pose_button.hide()

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
	selected_skel.propagate_notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)

# Mirror mode and bone child locking implementation:
func perform_bone_mirror(changed_indices: PackedInt32Array):
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
	if disable_next_update:
		disable_next_update = false
		for i in range(selected_skel.get_bone_count()):
			last_pose_positions[i] = selected_skel.get_bone_pose_position(i)
			last_pose_rotations[i] = selected_skel.get_bone_pose_rotation(i)
			last_pose_scales[i] = selected_skel.get_bone_pose_scale(i)
		return
	if mirror_bone_mode:
		if force_mirror or not (last_pose_positions[last_mirror_bone_idx].is_equal_approx(selected_skel.get_bone_pose_position(last_mirror_bone_idx)) and
				last_pose_rotations[last_mirror_bone_idx].is_equal_approx(selected_skel.get_bone_pose_rotation(last_mirror_bone_idx)) and
				last_pose_scales[last_mirror_bone_idx].is_equal_approx(selected_skel.get_bone_pose_scale(last_mirror_bone_idx))):
			perform_bone_mirror(PackedInt32Array([last_mirror_bone_idx]))
	if lock_bone_mode or mirror_bone_mode:
		last_pose_positions.resize(selected_skel.get_bone_count())
		last_pose_rotations.resize(selected_skel.get_bone_count())
		last_pose_scales.resize(selected_skel.get_bone_count())
		var changed_indices: PackedInt32Array
		for i in range(selected_skel.get_bone_count()):
			if not (last_pose_positions[i].is_equal_approx(selected_skel.get_bone_pose_position(i)) and
					last_pose_rotations[i].is_equal_approx(selected_skel.get_bone_pose_rotation(i)) and
					last_pose_scales[i].is_equal_approx(selected_skel.get_bone_pose_scale(i))):
				changed_indices.append(i)
		if lock_bone_mode:
			perform_bone_lock(changed_indices)
		for i in range(selected_skel.get_bone_count()):
			last_pose_positions[i] = selected_skel.get_bone_pose_position(i)
			last_pose_rotations[i] = selected_skel.get_bone_pose_rotation(i)
			last_pose_scales[i] = selected_skel.get_bone_pose_scale(i)
