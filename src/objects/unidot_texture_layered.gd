class_name UnidotTextureLayered extends UnidotTexture

var depth: int:
	get:
		return keys["m_Depth"]

func gen_images(is_3d: bool = false) -> Array:
	var imgdata: PackedByteArray = self.get_image_data()
	log_debug("Depth is " + str(self.depth) + " len(imgdata) is " + str(len(imgdata)))
	if self.depth <= 0:
		return []
	var stride_per: int = len(imgdata) / self.depth
	if stride_per <= 0:
		log_fail("len(imgdata) per layer is 0")
		return []
	var images: Array = []
	var offset: int = 0
	var unaligned = (self.width * self.height * self.get_unaligned_size()) % 4
	var length_per: int = stride_per
	var unaligned_size: int = get_unaligned_size()
	if unaligned_size != 0:
		length_per = 0
		var mip_dim = max(self.width, self.height)
		var mip_w = self.width
		var mip_h = self.height
		while mip_dim != 0:
			length_per += mip_w * mip_h * unaligned_size
			mip_w = max(1, mip_w / 2)
			mip_h = max(1, mip_h / 2)
			mip_dim /= 2
			if is_3d or self.mipmaps == 0:
				break
	else:
		length_per = 0
		var tmp_img = Image.new()
		tmp_img.create(self.width, self.height, true, self.get_godot_format())
		var mip_idx = 0
		var mip_dim = max(self.width, self.height)
		var last_off = 0
		while mip_dim != 1:
			mip_dim /= 2
			length_per = tmp_img.get_mipmap_offset(mip_idx)
			mip_idx += 1
			if mip_dim == 1:
				length_per += length_per - last_off  # last two mipmaps are always the same for compressed.
				break
			last_off = length_per
	log_debug(str(length_per) + " -> " + str(stride_per))

	for i in range(self.depth):
		images.append(self.gen_image_layer(imgdata, offset, length_per))
		offset += stride_per
	return images
