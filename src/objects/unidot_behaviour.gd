class_name UnidotBehaviour extends UnidotComponent

func convert_properties_component(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = {}
	if uprops.has("m_Enabled"):
		outdict["visible"] = uprops.get("m_Enabled") != 0
	return outdict

var enabled: bool:
	get:
		return keys.get("m_Enabled", 0) != 0
