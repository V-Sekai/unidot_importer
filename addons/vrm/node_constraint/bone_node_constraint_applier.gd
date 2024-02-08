## Attach this node in the scene and it will process the array of constraint
## resources on either bones or nodes, whatever the constraints reference.
@tool
@icon("icons/bone_node_constraint_applier.svg")
class_name BoneNodeConstraintApplier
extends Node

const bone_node_constraint = preload("./bone_node_constraint.gd")

@export var constraints: Array[bone_node_constraint] = []
#@export_node_path("Skeleton3D") var skeleton_node_path: NodePath = ^"%GeneralSkeleton"
#var skeleton: Skeleton3D


func _ready() -> void:
	#skeleton = get_node(skeleton_node_path)
	for constraint in constraints:
		constraint.set_node_references_from_paths(self)


func _process(_delta: float) -> void:
	for constraint in constraints:
		constraint.evaluate()
