class_name UnidotTexture extends UnidotObject

const aligned_byte_buffer := preload("../../aligned_byte_buffer.gd")

func get_godot_extension() -> String:
	return ".tex.res"

func get_image_data() -> PackedByteArray:
	# hex_decode
	if typeof(self.keys["image data"]) == TYPE_PACKED_BYTE_ARRAY:
		return self.keys["image data"]
	var tld = self.keys["_typelessdata"]
	var hexdec: PackedByteArray = aligned_byte_buffer.new().hex_decode(tld)  # a bit slow :'-(
	log_debug("get_image_data _typelessdata LEN " + str(len(tld)) + " is " + str(len(hexdec)))
	return hexdec

var width: int:
	get:
		return self.keys["m_Width"]

var height: int:
	get:
		return self.keys["m_Height"]

var mipmaps: int:
	get:
		return self.keys["m_MipCount"]

func get_unaligned_size() -> int:
	var format_index: int = keys.get("m_TextureFormat", keys.get("m_Format", 0))
	match format_index:
		1, 63:
			return 1
		2, 7, 9, 13, 15, 62:
			return 2
		3:
			return 3
		73:
			return 6
		17, 19, 74:
			return 8
		20:
			return 16
		4, 5, 14, 16, 18, 72:
			return 4
		_:
			return 0  # Compressed formats. Untested...

func get_godot_format() -> int:
	var format_index: int = keys.get("m_TextureFormat", keys.get("m_Format", 0))
	match format_index:
		1:  # A8
			return Image.FORMAT_R8
		2:  # ARGB4444
			return Image.FORMAT_RGBA4444
		3:
			return Image.FORMAT_RGB8
		4:
			return Image.FORMAT_RGBA8
		5:  # ARGB32
			return Image.FORMAT_RGBA8
		7:
			return Image.FORMAT_RGB565
		9:  # R16 (16-bit int). not supported in Godot
			return Image.FORMAT_RH
		10:
			return Image.FORMAT_DXT1
		11:
			return Image.FORMAT_DXT3
		12:
			return Image.FORMAT_DXT5
		13:
			return Image.FORMAT_RGBA4444
		14:  # BGRA32
			return Image.FORMAT_RGBA8
		15:
			return Image.FORMAT_RH
		16:
			return Image.FORMAT_RGH
		17:
			return Image.FORMAT_RGBAH
		18:
			return Image.FORMAT_RF
		19:
			return Image.FORMAT_RGF
		20:
			return Image.FORMAT_RGBAF
		21:  # YUY2 for video playback
			return Image.FORMAT_RGBA8
		22:
			return Image.FORMAT_RGBE9995
		24:  # BC6H
			return Image.FORMAT_BPTC_RGBFU
		25:
			return Image.FORMAT_BPTC_RGBA
		26:  # BC4, compressed one-channel texture
			return Image.FORMAT_RGTC_R
		27:  # BC5, compressed two-channel texture
			return Image.FORMAT_RGTC_RG
		28:  # DXT1 crunched
			log_fail("ERROR: DXT1 Crunch not supported")
		29:  # DXT5 crunched
			log_fail("ERROR: DXT5 Crunch not supported")
		30:
			log_fail("ERROR: PVRTC RGB2 not supported")
		31:
			log_fail("ERROR: PVRTC RGBA2 not supported")
		32:
			log_fail("ERROR: PVRTC RGB4 not supported")
		33:
			log_fail("ERROR: PVRTC RGBA4 not supported")
		34:
			return Image.FORMAT_ETC
		41:
			return Image.FORMAT_ETC2_R11
		42:
			return Image.FORMAT_ETC2_R11S
		43:
			return Image.FORMAT_ETC2_RG11
		44:
			return Image.FORMAT_ETC2_RG11S
		45:
			return Image.FORMAT_ETC2_RGB8
		46:
			return Image.FORMAT_ETC2_RGB8A1
		47:
			return Image.FORMAT_ETC2_RGBA8
		62:  # RG16 int
			return Image.FORMAT_RG8
		63:  # R8 int
			return Image.FORMAT_R8
		64:  # ETC crunched
			log_fail("ERROR: ETC Crunch not supported")
		65:  # ETC2 crunched
			log_fail("ERROR: ETC2 Crunch not supported")
		72:  # RG32 int
			return Image.FORMAT_RGH
		73:  # RGB48 int
			return Image.FORMAT_RGBH
		74:  # RGB64 int
			return Image.FORMAT_RGBAH
		_:
			log_fail("ERROR: Format " + str(format_index) + " is not supported")
	return Image.FORMAT_RGBA8  # most common

func gen_image_layer(imgdata: PackedByteArray, byteoffset: int, length: int) -> Image:
	var format: int = self.get_godot_format()
	log_debug("Format for " + meta.path + " is " + str(format))
	var img: Image = Image.new()
	log_debug(str(len(imgdata)) + "," + str(byteoffset) + "," + str(byteoffset + length))
	if byteoffset != 0 or length != 0:
		imgdata = imgdata.slice(byteoffset, byteoffset + length)
	log_debug(" is now " + str(len(imgdata)))
	#elif length != 0:
	img.create_from_data(self.width, self.height, self.mipmaps > 1, format, imgdata)
	return img

func get_godot_type() -> String:
	return "Texture"

func gen_image() -> Image:
	var imgdata: PackedByteArray = self.get_image_data()
	return gen_image_layer(imgdata, 0, 0)
