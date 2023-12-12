extends RefCounted

var ep = EditorPlugin.new()
var editor_interface = ep.get_editor_interface()
var editor_filesystem = editor_interface.get_resource_filesystem()

func _init():
	ep.queue_free()

func save_resource(created_res: Resource, new_pathname: String):
	var existed: bool = FileAccess.file_exists(new_pathname)
	if not new_pathname.begins_with("res://"):
		new_pathname = "res://" + new_pathname
	if existed:
		created_res.take_over_path(new_pathname)
	elif new_pathname.ends_with(".tscn"):
		# Godot is giving an error in ResourceSaver.save() that it can't read the uid from the file while it's writing (get_uid)
		# Why and how?!
		# Let's experiment with manual UID generation...
		# pkgasset.parsed_meta.
		# ResourceUID.id_to_text(calc_md5(pkgasset.guid))
		var new_uid = ResourceUID.create_id()
		ResourceUID.add_id(new_uid, new_pathname)
		var fa: FileAccess = FileAccess.open(new_pathname, FileAccess.WRITE)
		fa.store_string('[gd_scene format=3 uid="' + ResourceUID.id_to_text(new_uid) + '"]\n\n[node name="Node3D" type="Node3D"]\n')
		fa.flush()
		fa.close()
		fa = null
		editor_filesystem.update_file(new_pathname)
		existed = true
	else:
		var new_uid = ResourceUID.create_id()
		ResourceUID.add_id(new_uid, new_pathname)
	created_res.resource_path = new_pathname
	ResourceSaver.save(created_res, new_pathname, ResourceSaver.FLAG_COMPRESS)
	# Needed to update the UID database so references can be made more reliably.
	if not existed:
		editor_filesystem.update_file(new_pathname)
