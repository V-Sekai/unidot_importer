class_name UnidotTerrainLayer extends UnidotObject

func get_godot_type() -> String:
	return "MeshLibrary"

func get_godot_extension() -> String:
	return ".terrainlayer.tres"

func create_godot_resource() -> Resource:
	var mat = StandardMaterial3D.new()
	var diffuse_tex: Texture2D = meta.get_godot_resource(keys.get("m_DiffuseTexture", [null, 0, null, null]))
	var tilesize: Vector2 = keys.get("m_TileSize", Vector2(1, 1))
	var tileoffset: Vector2 = keys.get("m_TileOffset", Vector2(0, 0))
	var spec: Color = keys.get("m_Specular", Color.TRANSPARENT)
	var metal: float = keys.get("m_Metallic", 0.0)
	var smooth: float = keys.get("m_Smoothness", 0.0)
	mat.albedo_texture = diffuse_tex
	mat.roughness = 1.0 - smooth
	mat.metallic = metal
	# mat.metallic_specular = spec.a
	mat.uv1_scale = Vector3(1.0 / tilesize.x, 1.0 / tilesize.y, 0.0)
	mat.uv1_offset = Vector3(tileoffset.x / tilesize.x, tileoffset.y / tilesize.x, 0.0)

	var normal_tex: Texture2D = meta.get_godot_resource(keys.get("m_NormalMapTexture", [null, 0, null, null]))
	var normalscale: float = keys.get("m_NormalScale", 1.0)
	mat.normal_enabled = normal_tex != null
	mat.normal_texture = normal_tex
	mat.normal_scale = normalscale

	# Mask not implemented for now.
	# m_DiffuseRemapMin: {x: 0, y: 0, z: 0, w: 0}
	# m_DiffuseRemapMax: {x: 1, y: 1, z: 1, w: 1}
	# m_MaskMapRemapMin: {x: 0, y: 0, z: 0, w: 0}
	# m_MaskMapRemapMax: {x: 1, y: 1, z: 1, w: 1}
	#var maskmap_tex: Texture2D = meta.get_godot_resource(keys.get("m_MaskMapTexture", [null,0,null,null]))
	return mat
