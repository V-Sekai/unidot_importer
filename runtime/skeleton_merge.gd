@tool
class_name SkeletonMerge
extends Node3D

const merged_skeleton_script := preload("./merged_skeleton.gd")

var cached_children: Dictionary
var cached_children_list: Array[Node]
var cached_count: int


func _notification(what):
	match(what):
		NOTIFICATION_CHILD_ORDER_CHANGED:
			var new_child_count: int = get_child_count()
			if new_child_count == cached_count + 1:
				cached_count = new_child_count
				var new_child_maybe: Node = get_child(get_child_count() - 1)
				if not cached_children.has(new_child_maybe):
					cached_children[new_child_maybe] = true
					cached_children_list.append(new_child_maybe)
					if new_child_maybe is Node3D:
						child_added.call_deferred(new_child_maybe as Node3D)
				else:
					cached_children_list = get_children()
					for test_child in cached_children_list:
						if not cached_children.has(test_child):
							cached_children[test_child] = true
							if new_child_maybe is Node3D:
								child_added.call_deferred(test_child as Node3D)
			elif new_child_count == cached_count - 1:
				cached_count = new_child_count
				if cached_children_list[-1].get_parent() != self:
					cached_children.erase(cached_children_list[-1])
					cached_children_list.remove_at(len(cached_children_list) - 1)
				else:
					for test_child in cached_children_list:
						if test_child.get_parent() != self:
							cached_children.erase(test_child)
					cached_children_list = get_children()
			elif new_child_count == cached_count:
				cached_children_list = get_children()
			else:
				push_error("NOTIFICATION_CHILD_ORDER_CHANGED count went from " + str(cached_count) + " to " + str(new_child_count))
				cached_count = new_child_count
			#print("Got NOTIFICATION_CHILD_ORDER_CHANGED. Lists now are:")
			#print(cached_children.keys())
			#print(cached_children_list)


func _init():
	if not Engine.is_editor_hint():
		set_script(null)


func child_added(new_child: Node3D):
	if not new_child.scene_file_path.is_empty():
		new_child.owner.set_editable_instance(new_child, true)
		new_child.set_display_folded(true)
	var found_skel: bool = false
	for skel in new_child.find_children("GeneralSkeleton", "Skeleton3D", true):
		found_skel = true
		if skel.get_script() == null:
			print("Attaching merged_skeleton script to " + str(get_path_to(new_child)))
			skel.set_script(merged_skeleton_script)
