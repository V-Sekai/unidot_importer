class_name UnidotCubemap extends UnidotTextureLayered

func get_godot_type() -> String:
	return "Cubemap"

func create_godot_resource() -> Resource:
	var imgtex: Cubemap = Cubemap.new()
	imgtex.create_from_images(self.gen_images())
	return imgtex
