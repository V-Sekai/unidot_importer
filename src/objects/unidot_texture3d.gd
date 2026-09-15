class_name UnidotTexture3D extends UnidotTextureLayered

func get_godot_type() -> String:
	return "Texture3D"

func create_godot_resource() -> Resource:
	var imgtex: ImageTexture3D = ImageTexture3D.new()
	imgtex.create(self.get_godot_format(), self.width, self.height, self.depth, false, self.gen_images(true))
	return imgtex
