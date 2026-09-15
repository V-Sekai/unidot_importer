class_name UnidotMonoBehaviour extends UnidotBehaviour

var monoscript: Array:
	get:
		return keys.get("m_Script", [null, 0, null, null])

func get_godot_type() -> String:
	return "GDScript"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	var ret: Node = null
	for plugin in meta.get_enabled_plugins():
		var this_ret = plugin.handle_monobehaviour(self, state, new_parent, ret)
		if this_ret != null:
			ret = this_ret
	if ret != null:
		return ret
	return super.create_godot_node(state, new_parent)

# No need yet to override create_godot_node...
func create_godot_resource() -> Resource:
	for plugin in meta.get_enabled_plugins():
		var ret: Resource = plugin.handle_scripted_object(self)
		if ret != null:
			return ret
	if monoscript[1] == 11500000:
		if monoscript[2] == "8e6292b2c06870d4495f009f912b9600":
			return create_post_processing_profile()
	return null

func create_post_processing_profile() -> Environment:
	var env: Environment = Environment.new()
	for setting in keys.get("settings"):
		var sobj = meta.lookup(setting)
		match str(sobj.monoscript[2]):
			"adb84e30e02715445aeb9959894e3b4d":  # Tonemap
				env.set_meta("tonemap", sobj.keys)
			"48a79b01ea5641d4aa6daa2e23605641":  # Glow
				env.set_meta("glow", sobj.keys)
	return env
