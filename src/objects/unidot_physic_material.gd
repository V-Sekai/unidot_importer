# TODO: should this be PhysicsMaterial? seems like it
class_name UnidotPhysicMaterial extends UnidotObject

func get_godot_type() -> String:
	return "PhysicsMaterial"

func get_godot_extension() -> String:
	return ".phymat"

func create_godot_resource() -> Resource:
	var mat := PhysicsMaterial.new()
	mat.bounce = keys.get("bounciness", 0.0)
	mat.friction = keys.get("dynamicFriction", 1.0)
	# Average, Minimum, Multiply, Maximum
	# Godot's "rough" behavior is closest to Maximum so we use that.
	mat.rough = (keys.get("frictionCombine", 0) == 3)
	# Minimum or Multiply are probably closest to the absorbent behavior.
	mat.absorbent = (keys.get("bounceCombine", 0) % 3 != 0)
	return mat
