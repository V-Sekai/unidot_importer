class_name UnidotTexture2D extends UnidotTexture

func get_godot_extension() -> String:
	return ".tex" # TODO: These really should be getting exported as .png?

func get_godot_type() -> String:
	return "Texture2D"

func create_godot_resource() -> Resource:
	var imgtex: ImageTexture = ImageTexture.new()
	imgtex.create_from_image(self.gen_image())
	return imgtex
