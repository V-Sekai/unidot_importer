class_name UnidotTexture2DArray extends UnidotTextureLayered

func get_godot_type() -> String:
	return "Texture2DArray"

func create_godot_resource() -> Resource:
	var imgtex: Texture2DArray = Texture2DArray.new()
	imgtex.create_from_images(self.gen_images())
	return imgtex
