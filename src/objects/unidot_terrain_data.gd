class_name UnidotTerrainData extends UnidotObject

var mesh_data: ArrayMesh = null
var collision_mesh: ConcavePolygonShape3D = null
var terrain_mat: Material = null
var other_resources: Dictionary = {}
var scale: Vector3 = Vector3.ONE
var resolution: int = 0

func get_godot_type() -> String:
	return "HeightMapShape3D"

func resolve_godot_resource(fileRef: Array) -> Resource:
	if fileRef[2] == null or fileRef[2] == meta.guid:
		return other_resources[fileRef[1]]
	return meta.get_godot_resource(fileRef)

func find_meshinst(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		log_debug("Returning " + str(node.name))
		return node
	for n in node.get_children():
		var res: MeshInstance3D = find_meshinst(n)
		if res != null:
			return res
	return null

func gen_multimeshes() -> Array:
	var tree_prototype_matrices: Array[Transform3D]
	var multimeshes: Array[MultiMesh]
	var material_overrides: Array  # can't use typed array if some elements are null
	var transform_counts: PackedInt32Array = PackedInt32Array().duplicate()
	var detail_data: Dictionary = keys.get("m_DetailDatabase", {})
	var bend_factors: Array[float]
	for detail in detail_data.get("m_TreePrototypes", []):
		var target_ref: Array = detail.get("prefab", [null, 0, null, null])
		var tree_scene: Node = meta.get_godot_node(target_ref)
		var meshinst: MeshInstance3D = null
		var mesh: Mesh = null
		if tree_scene != null:
			recursive_log_debug(tree_scene, " %d>   " % [len(multimeshes)])
			meshinst = find_meshinst(tree_scene)  # tree_scene.find_nodes("*", "MeshInstance3D")
		if meshinst != null:
			mesh = meshinst.mesh
			if meshinst.material_override != null:
				material_overrides.append(meshinst.material_override)
			elif meshinst.get_surface_override_material_count() >= 1 and meshinst.get_surface_override_material(0) != null:
				if meshinst.get_surface_override_material_count() == 1:
					material_overrides.append(meshinst.get_surface_override_material(0))
				else:
					log_warn("Godot Multimesh does not implement per-surface override materials! Attempt to overwrite the mesh materials directly.")
					for idx in range(meshinst.get_surface_override_material_count()):
						mesh.surface_set_material(idx, meshinst.get_surface_override_material(idx))
					material_overrides.append(null)
			else:
				material_overrides.append(null)
			var xform: Transform3D = meshinst.transform
			var tmpnode: Node3D = meshinst.get_parent_node_3d()
			while tmpnode != null:
				xform = tmpnode.transform * xform
				tmpnode = tmpnode.get_parent_node_3d()
			tree_prototype_matrices.append(xform)
		else:
			tree_prototype_matrices.append(Transform3D.IDENTITY)
			material_overrides.append(null)
		var mm: MultiMesh = MultiMesh.new()
		mm.resource_name = (str(meta.lookup_meta(target_ref).resource_name).get_file().get_basename() if tree_scene != null else "")
		if mm.resource_name == "":
			mm.resource_name = StringName("tree%d" % [len(multimeshes)])
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		bend_factors.append(detail.get("bendFactor", 0.0))  # not yet implemented.
		multimeshes.append(mm)
		transform_counts.append(0)
		if tree_scene != null:
			tree_scene.queue_free()
	# instances:
	# {'position': {'x': 0.378, 'y': 0.0074, 'z': 0.716}, 'widthScale': 0.73, 'heightScale': 0.73,
	# 'rotation': 2.5, 'color': {'rgba': 4293848814}, 'lightmapColor': {'rgba': 4294967295}, 'index': 5}
	for inst in detail_data.get("m_TreeInstances", []):
		var idx: int = inst["index"]
		transform_counts[idx] += 1
	for idx in range(len(multimeshes)):
		multimeshes[idx].instance_count = transform_counts[idx]
		transform_counts[idx] = 0
	for inst in detail_data.get("m_TreeInstances", []):
		var idx: int = inst["index"]
		var wid: float = inst.get("widthScale", 1.0)
		var hei: float = inst.get("heightScale", 1.0)
		var rot: float = inst.get("rotation", 0.0)
		var pos: Vector3 = inst["position"] * scale * Vector3(resolution, 1.0, resolution)
		var col: Color = inst.get("color", Color.WHITE)
		var bas: Basis = Basis.from_euler(Vector3(0, rot, 0)).scaled(Vector3(wid, hei, wid))
		var xform: Transform3D = Transform3D(bas, pos) * tree_prototype_matrices[idx]
		xform = Transform3D.FLIP_X.inverse() * xform * Transform3D.FLIP_X
		multimeshes[idx].set_instance_transform(transform_counts[idx], xform)
		multimeshes[idx].set_instance_color(transform_counts[idx], col)
		transform_counts[idx] += 1
	return [multimeshes, material_overrides]

func recursive_log_debug(node: Node, indent: String = ""):
	var fnstr = "" if str(node.scene_file_path) == "" else (" (" + str(node.scene_file_path) + ")")
	log_debug(indent + str(node.name) + ": owner=" + str(node.owner.name if node.owner != null else "") + fnstr)
	#log_debug(indent + str(node.name) + str(node) + ": owner=" + str(node.owner.name if node.owner != null else "") + str(node.owner) + fnstr)
	var new_indent: String = indent + "  "
	for c in node.get_children():
		recursive_log_debug(c, new_indent)

func get_extra_resources() -> Dictionary:
	var dict = (
		{
			self.fileID ^ 0x1234567: ".terrain.material",
			self.fileID ^ 0xdeca604: ".terrain.mesh",
			self.fileID ^ 0xc0111de4: ".terrain.shape",
		}
		. duplicate()
	)
	var found_splatmap: bool = false
	for other_id in meta.fileid_to_utype:
		if other_id != self.fileID:
			var other_object: UnidotObject = meta.parsed.assets.get(other_id)
			if meta.parsed.assets.has(other_id):
				var res: Resource = meta.parsed.assets.get(other_id).create_godot_resource()
				if res != null:
					other_resources[other_id] = res
					if other_object.type.begins_with("Texture"):
						if found_splatmap:
							dict[other_id] = "." + str(other_id) + ".res"
						else:
							dict[other_id] = ".splatmap.res"
							found_splatmap = true
					else:
						dict[other_id] = other_object.get_godot_extension()

	#var vertices: PackedVector3Array = PackedVector3Array().duplicate()
	var heightmap: Dictionary = keys.get("m_Heightmap")
	self.resolution = heightmap["m_Resolution"]
	var vertex_count = resolution * resolution
	var index_count = (resolution - 1) * (resolution - 1)
	assert(resolution * resolution == len(heightmap["m_Heights"]))
	var heights: PackedInt32Array = heightmap.get("m_Heights")
	self.scale = heightmap.get("m_Scale")
	#var surface = SurfaceTool.new()
	#surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices: PackedVector3Array = PackedVector3Array().duplicate()
	vertices.resize(resolution * resolution)
	var uvs: PackedVector2Array = PackedVector2Array().duplicate()
	uvs.resize(resolution * resolution)
	var indices_tris: PackedInt32Array = PackedInt32Array().duplicate()
	indices_tris.resize((resolution - 1) * (resolution - 1) * 6 + (resolution - 1) * 3)
	var idx: int = 0
	for resy in range(resolution):
		for resx in range(resolution):
			var heightint: int = heights[resy * resolution + resx]
			vertices[idx] = scale * Vector3(-1.0 * resx, heightint / 32767.0, 1.0 * resy)
			uvs[idx] = Vector2((1.0 * resx) / resolution, (1.0 * resy) / resolution)
			#surface.set_uv(Vector2((1.0 * resx) / resolution, (1.0 * resy) / resolution))
			#surface.add_vertex(vertices[idx])
			idx += 1
	idx = 0
	# Big hack because we are using SurfaceTool to generate vertices.
	# SurfaceTool outputs vertices in index order. We want to ensure each vertex is referenced once in order.
	# This seems to only affect the first row, because the second row is already referenced in order below.
	for resx in range(resolution - 1):
		indices_tris[idx] = resx
		indices_tris[idx + 1] = resx + 1
		indices_tris[idx + 2] = resx
		idx += 3
	for resy in range(resolution - 1):
		for resx in range(resolution - 1):
			var baseidx: int = resy * resolution + resx
			indices_tris[idx] = (baseidx + resolution)
			indices_tris[idx + 1] = (baseidx + resolution + 1)
			indices_tris[idx + 2] = (baseidx)
			indices_tris[idx + 3] = (baseidx)
			indices_tris[idx + 4] = (baseidx + resolution + 1)
			indices_tris[idx + 5] = (baseidx + 1)
			#surface.add_index(baseidx + resolution)
			#surface.add_index(baseidx)
			#surface.add_index(baseidx + resolution + 1)
			#surface.add_index(baseidx + resolution + 1)
			#surface.add_index(baseidx)
			#surface.add_index(baseidx + 1)
			idx += 6
	var temp_mesh: ArrayMesh = ArrayMesh.new()
	var really_temp_arrays: Array = []
	really_temp_arrays.resize(Mesh.ARRAY_MAX)
	really_temp_arrays[Mesh.ARRAY_VERTEX] = vertices
	really_temp_arrays[Mesh.ARRAY_TEX_UV] = uvs
	really_temp_arrays[Mesh.ARRAY_INDEX] = indices_tris
	temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, really_temp_arrays)
	var mesh_arrays: Array
	if len(vertices) < 10000000:
		var surface = SurfaceTool.new()
		surface.create_from(temp_mesh, 0)  # Missing API here to create directly from arrays!!!! :'-(
		# generate_normals does not support triangle strip.
		surface.generate_normals()
		surface.generate_tangents()
		# Missing API: No way to clear indices or convert to triangle strip?
		temp_mesh = surface.commit()
		collision_mesh = temp_mesh.create_trimesh_shape()
		mesh_arrays = temp_mesh.surface_get_arrays(0)
	else:
		mesh_arrays = really_temp_arrays
	# Missing API: No way to make SurfaceTool from arrays???
	# I guess we just do it ourselves
	var indices_optimized: PackedInt32Array = PackedInt32Array().duplicate()
	indices_optimized.resize((resolution) * ((resolution - 1) / 2) * 4)
	indices_optimized.fill(0)
	# Triangle strip:
	idx = 0
	for resy in range(0, resolution - 1, 2):
		for resx in range(resolution):
			indices_optimized[idx] = (resy * resolution + resx)
			indices_optimized[idx + 1] = ((resy + 1) * resolution + resx)
			idx += 2
		for resx in range(resolution - 1, -1, -1):
			indices_optimized[idx] = ((resy + 2) * resolution + resx)
			indices_optimized[idx + 1] = ((resy + 1) * resolution + resx)
			idx += 2
	assert(len(indices_optimized) == idx)
	mesh_arrays[Mesh.ARRAY_INDEX] = indices_optimized

	#mesh_data = temp_mesh
	mesh_data = ArrayMesh.new()
	mesh_data.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, mesh_arrays)
	terrain_mat = self.gen_terrain_mat()

	mesh_data.resource_name = self.keys.get("m_Name", meta.resource_name) + "_mesh"
	mesh_data.surface_set_name(0, "TerrainSurf")
	mesh_data.surface_set_material(0, terrain_mat)

	return dict

func gen_terrain_mat() -> Material:
	var terrain_mat: Material = null
	var mat = ShaderMaterial.new()
	var matshader = Shader.new()
	matshader.code = '''
shader_type spatial;
	'''
	var splat_database = keys.get("m_SplatDatabase", {})
	var terrain_layers: Array = splat_database.get("m_TerrainLayers", [])
	var alpha_textures: Array = splat_database.get("m_AlphaTextures", [])
	if len(terrain_layers) == 0:
		terrain_layers.append(null)
	if len(alpha_textures) > 0:
		var normal_enabled = []
		var any_normal_enabled = false
		for terrain_layer in terrain_layers:
			var layer_mat: StandardMaterial3D = resolve_godot_resource(terrain_layer)
			var this_normal_enabled: bool = layer_mat.normal_enabled if layer_mat != null else true
			normal_enabled.append(this_normal_enabled)
			any_normal_enabled = any_normal_enabled or this_normal_enabled

		var shader_code: String = "shader_type spatial;\n"
		for i in range(len(terrain_layers)):
			shader_code += "uniform sampler2D albedo%d: source_color, hint_default_%s;\n" % [i, "white" if i == 0 else "black"]
		for i in range(len(terrain_layers)):
			if normal_enabled[i]:
				shader_code += "uniform sampler2D normal%d: hint_normal;\n" % [i]
		for splati in range(len(alpha_textures)):
			shader_code += "uniform sampler2D splat%d;\n" % [splati * 4]
		for i in range(len(terrain_layers)):
			shader_code += "uniform vec4 smoothMetalNormal%d = vec4(0);\n" % [i]
			shader_code += "uniform vec4 scaleOffset%d = vec4(1,1,0,0);\n" % [i]
		shader_code += "\n\nvoid fragment() {\n"
		shader_code += "\tvec4 splat, albedo0col = vec4(0), albedo = vec4(0); vec2 thisUV, normalXY = vec2(0);\n"
		shader_code += "\tvec4 smoothMetalNormal = vec4(0); float normalStrength = 0.0; float strength = 0.0;\n\n"
		for splati in range(len(alpha_textures)):
			shader_code += "\tsplat = texture(splat%d, UV);\n" % [splati * 4]
			for idx in range(min(len(terrain_layers) - splati * 4, 4)):
				var i = splati * 4 + idx
				shader_code += "\tthisUV = UV * scaleOffset%d.xy + scaleOffset%d.zw;\n" % [i, i]
				if i == 0:
					shader_code += ("\talbedo0col = splat[%d] * texture(albedo%d, thisUV); albedo = splat[%d] * albedo0col;\n" % [idx, i, idx])
				else:
					shader_code += "\talbedo += splat[%d] * texture(albedo%d, thisUV);\n" % [idx, i]
				shader_code += "\tstrength += splat[%d];\n" % [idx]
				if normal_enabled[i]:
					shader_code += "\tnormalStrength += splat[%d] * smoothMetalNormal%d.z;\n" % [idx, i]
					shader_code += ("\tnormalXY += splat[%d] * smoothMetalNormal%d.z * (texture(albedo%d, thisUV).xy * 2.0 - 1.0);\n" % [idx, i, i])
				shader_code += "\tsmoothMetalNormal += splat[%d] * smoothMetalNormal%d;\n\n" % [idx, i]
		shader_code += "\tsmoothMetalNormal = max(0.0, 1.0 - strength) * smoothMetalNormal0 + min(1.0, 1.0 / strength) * smoothMetalNormal;\n"
		shader_code += "\tALBEDO = max(0.0, 1.0 - strength) * albedo0col.xyz + min(1.0, 1.0 / strength) * albedo.xyz;\n"
		shader_code += "\tROUGHNESS = 1.0 - albedo.w * smoothMetalNormal.x;\n"
		shader_code += "\tMETALLIC = smoothMetalNormal.y;\n"
		if any_normal_enabled:
			shader_code += "\tnormalXY = mix(vec2(0.0), normalXY / normalStrength, smoothstep(0.01, 0.1, normalStrength));\n"
			shader_code += "\tNORMAL_MAP = vec3(normalXY.xy, sqrt(1.0 - dot(normalXY, normalXY)));\n"
			shader_code += "\tNORMAL_MAP_DEPTH = normalStrength;\n"
		shader_code += "}\n"
		matshader.code = shader_code
		mat.shader = matshader
		var i: int = 0
		for terrain_layer in terrain_layers:
			var layer_mat: StandardMaterial3D = resolve_godot_resource(terrain_layer)
			if layer_mat == null:
				continue
			mat.set_shader_parameter("albedo%d" % [i], layer_mat.albedo_texture)
			var normal_scale = 0.0
			if layer_mat.normal_enabled:
				mat.set_shader_parameter("normal%d" % [i], layer_mat.normal_texture)
				normal_scale = layer_mat.normal_scale
			var roughness = layer_mat.roughness
			var metallic = layer_mat.metallic
			var uv1_scale: Vector2 = Vector2(layer_mat.uv1_scale.x, layer_mat.uv1_scale.y) * Vector2(scale.x, scale.z) * resolution
			var uv1_offset = layer_mat.uv1_offset
			mat.set_shader_parameter("smoothMetalNormal%d" % [i], Plane(1.0 - roughness, metallic, normal_scale, 0.0))
			mat.set_shader_parameter("scaleOffset%d" % [i], Plane(uv1_scale.x, uv1_scale.y, uv1_offset.x, uv1_offset.y))
			i += 1
		i = 0
		for splat_texture_obj in alpha_textures:
			var splat_texture: Texture2D = resolve_godot_resource(splat_texture_obj)
			mat.set_shader_parameter("splat%d" % [i], splat_texture)
			i += 1
		mat.resource_name = self.keys.get("m_Name", meta.resource_name) + "_material"
		terrain_mat = mat
	else:
		terrain_mat = terrain_layers[0]
	return terrain_mat

func create_godot_resource() -> Resource:
	var packed_scene = PackedScene.new()
	var rootnode = Node3D.new()
	# rootnode.top_level = true  # ideally only ignore rotation, scale.
	rootnode.name = self.keys.get("m_Name", meta.resource_name)
	var meshinst: MeshInstance3D = MeshInstance3D.new()
	meshinst.name = "TerrainMesh"
	meshinst.mesh = mesh_data
	rootnode.add_child(meshinst)
	meshinst.owner = rootnode  # must happen after add_child
	var multimeshes_and_materials = self.gen_multimeshes()
	var multimeshes: Array[MultiMesh] = multimeshes_and_materials[0]
	var material_overrides: Array = multimeshes_and_materials[1]
	var i = 0
	for mm in multimeshes:
		var multimesh: MultiMesh = mm
		var mminst: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mminst.name = multimesh.resource_name
		mminst.multimesh = multimesh
		mminst.material_override = material_overrides[i]
		rootnode.add_child(mminst, true)
		mminst.owner = rootnode  # must happen after add_child
		i += 1
	var err = packed_scene.pack(rootnode)
	if err != OK:
		log_fail("Error packing terrain scene. " + str(err))
		return null
	return packed_scene

func get_godot_extension() -> String:
	return ".terrain.tscn"

func get_extra_resource(fileID: int) -> Resource:
	if fileID == self.fileID ^ 0x1234567:
		return self.terrain_mat
	if fileID == self.fileID ^ 0xdeca604:
		return self.mesh_data
	if fileID == self.fileID ^ 0xc0111de4:
		return self.collision_mesh
	if other_resources.has(fileID):
		return other_resources.get(fileID)
	assert(fileID == 0)
	return null
