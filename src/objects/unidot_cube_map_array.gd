class_name UnidotCubemapArray extends UnidotTextureLayered

func get_godot_type() -> String:
	return "CubemapArray"

func create_godot_resource() -> Resource:
	var imgtex: CubemapArray = CubemapArray.new()
	imgtex.create_from_images(self.gen_images())
	return imgtex
