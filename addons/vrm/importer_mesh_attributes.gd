@tool
extends ImporterMeshInstance3D

@export var layers: int
@export var first_person_flag: String


func _on_replacing_by(p_node: Node):
	if not (p_node is MeshInstance3D):
		push_error("ImporterMeshInstance3D was not replaced with MeshInstance3D")
	var mi: MeshInstance3D = p_node as MeshInstance3D
	mi.layers = layers
	mi.set_meta("vrm_first_person_flag", first_person_flag)


func _init():
	self.replacing_by.connect(_on_replacing_by)
