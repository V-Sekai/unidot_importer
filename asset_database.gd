@tool
extends Resource

const asset_meta_class: GDScript = preload("./asset_meta.gd")
const yaml_parser_class: GDScript = preload("./unity_object_parser.gd")
const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")

const ASSET_DATABASE_PATH: String = "res://unity_asset_database.tres"

var object_adapter = object_adapter_class.new()
var in_package_import: bool = false

@export var guid_to_path: Dictionary = {}
@export var path_to_meta: Dictionary = {}

# Must be non-null to hold material references
@export var truncated_shader_reference: Shader = null
@export var truncated_material_reference: Material = null
@export var null_material_reference: Material = null
@export var default_material_reference: Material = null


# SEMI-STATIC
func get_singleton() -> Object:
	var asset_database = load(ASSET_DATABASE_PATH)
	if asset_database == null:
		asset_database = self
		asset_database.preload_builtin_assets()
		asset_database.save()
		asset_database = load(ASSET_DATABASE_PATH)
	return asset_database


func save():
	ResourceSaver.save(self, ASSET_DATABASE_PATH)


# Log messages related to this asset
func log_debug(local_ref: Array, msg: String):
	print(".unidot. " + str(local_ref[2]) + ":" + str(local_ref[1]) + " : "+ msg)

# Anything that is unexpected but does not necessarily imply corruption.
# For example, successfully loaded a resource with default fileid
func log_warn(local_ref: Array, msg: String, field: String="", remote_ref: Array=[null,0,"",null]):
	var fieldstr = ""
	if not field.is_empty():
		fieldstr = "." + field
	if remote_ref:
		push_warning(".UNIDOT. " + str(local_ref[2]) + ":" + str(local_ref[1]) + fieldstr + " -> " + str(remote_ref[2]) + ":" + str(remote_ref[1]) + " : " + msg)
	push_warning(".UNIDOT. " + str(local_ref[2]) + ":" + str(local_ref[1]) + fieldstr + " : "+ msg)

# Anything that implies the asset will be corrupt / lost data.
# For example, some reference or field could not be assigned.
func log_fail(local_ref: Array, msg: String, field: String="", remote_ref: Array=[null,0,"",null]):
	var fieldstr = ""
	if not field.is_empty():
		fieldstr = "." + field
	if remote_ref:
		push_error("!UNIDOT! " + str(local_ref[2]) + ":" + str(local_ref[1]) + fieldstr + " -> " + str(remote_ref[2]) + ":" + str(remote_ref[1]) + " : " + msg)
	push_error("!UNIDOT! " + str(local_ref[2]) + ":" + str(local_ref[1]) + fieldstr + " : "+ msg)


func insert_meta(meta: Resource):  # asset_meta
	if meta.get_database_int() == null:
		meta.initialize(self)
	if meta.path.is_empty():
		log_fail([null,-1,meta.guid,-1], "meta " + str(meta) + " " + str(meta.guid) + " inserted with empty path")
		return
	if guid_to_path.has(meta.guid):
		var old_path = guid_to_path[meta.guid]
		if old_path != meta.path:
			push_warning(
				(
					"Desync between old_meta.path and guid_to_path for "
					+ str(meta.guid)
					+ " / "
					+ str(meta.path)
					+ " at "
					+ str(old_path)
				)
			)
			guid_to_path.erase(meta.guid)
			path_to_meta.erase(old_path)
	if path_to_meta.has(meta.path):
		var old_meta = path_to_meta[meta.path]
		if old_meta.guid != meta.guid:
			push_warning(
				(
					"Desync between old_meta.path and guid_to_path for "
					+ str(meta.guid)
					+ " / "
					+ str(meta.path)
					+ " with "
					+ str(old_meta.guid)
				)
			)
			guid_to_path.erase(old_meta.guid)
			path_to_meta.erase(meta.path)
	guid_to_path[meta.guid] = meta.path
	path_to_meta[meta.path] = meta


func rename_meta(meta: Resource, new_path: String):
	if new_path.is_empty():
		log_fail([null,-1,meta.guid,-1], "meta " + str(meta) + " " + str(meta.guid) + " renamed to empty")
		return
	if path_to_meta[meta.path] != meta:
		log_fail([null,-1,meta.guid,-1], "Renaming file not at the correct path")
	if guid_to_path[meta.guid] != meta.path:
		log_fail([null,-1,meta.guid,-1], "Renaming guid not at the correct path")
	path_to_meta.erase(meta.path)
	guid_to_path[meta.guid] = new_path
	path_to_meta[new_path] = meta
	meta.path = new_path


func get_meta_at_path(path: String) -> Resource:  # asset_meta
	var ret: Resource = path_to_meta.get(path)
	if ret != null:
		if ret.get_database_int() == null:
			ret.initialize(self)
	return ret


func get_meta_by_guid(guid: String) -> Resource:  # asset_meta
	var path = guid_to_path.get(guid, "")
	if not str(path).is_empty():
		return get_meta_at_path(path)
	return null


func guid_to_asset_path(guid: String) -> String:
	return guid_to_path.get(guid, "")


func create_dummy_meta(asset_path: String) -> Resource:  # asset_meta
	var meta = asset_meta_class.new()
	meta.set_log_database(self)
	meta.init_with_file(null, asset_path)
	meta.path = asset_path
	var hc: HashingContext = HashingContext.new()
	hc.start(HashingContext.HASH_MD5)
	hc.update("GodotDummyMetaGuid".to_ascii_buffer())
	hc.update(asset_path.to_ascii_buffer())
	meta.guid = hc.finish().hex_encode()
	return meta


func parse_meta(file: Object, path: String) -> Resource:  # asset_meta
	var ret: Resource = asset_meta_class.new()
	ret.set_log_database(self)
	ret.init_with_file(file, path)
	return ret


func preload_builtin_assets():
	truncated_shader_reference = Shader.new()
	truncated_shader_reference.code = "shader_type spatial;render_mode unshaded;void vertex() {VERTEX=vec3(1.0);}"
	truncated_shader_reference.resource_name = "Unidot Hidden Shader"
	truncated_material_reference = ShaderMaterial.new()
	truncated_material_reference.shader = truncated_shader_reference
	truncated_material_reference.resource_name = "Unidot Hidden Material"
	null_material_reference = StandardMaterial3D.new()
	null_material_reference.resource_name = "PINK"
	null_material_reference.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	null_material_reference.albedo_color = Color(1.0, 0.0, 1.0)
	default_material_reference = StandardMaterial3D.new()
	default_material_reference.resource_name = "Default-Material"

	var unity_builtin = asset_meta_class.new()
	unity_builtin.init_with_file(null, "Library/unity default resources")
	unity_builtin.initialize(self)
	unity_builtin.resource_name = unity_builtin.path
	unity_builtin.guid = "0000000000000000e000000000000000"
	guid_to_path[unity_builtin.guid] = unity_builtin.path
	path_to_meta[unity_builtin.path] = unity_builtin

	var stub = Resource.new()
	unity_builtin.override_resource(10001, "SpotCookie", stub)  # Spot lights default attenuation
	unity_builtin.override_resource(10100, "Font Material", StandardMaterial3D.new())  # GUI/Text Shader
	unity_builtin.override_resource(10102, "Arial", stub)  # Arial (font)
	var cube: BoxMesh = BoxMesh.new()
	cube.size = Vector3(1.0, 1.0, 1.0)
	unity_builtin.override_resource(10202, "Cube", cube)
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 2.0
	unity_builtin.override_resource(10206, "Cylinder", cylinder)
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 2.0 * sphere.radius
	unity_builtin.override_resource(10207, "Sphere", sphere)
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.5
	unity_builtin.override_resource(10208, "Capsule", capsule)
	var plane: PlaneMesh = PlaneMesh.new()
	plane.subdivide_depth = 10
	plane.subdivide_width = 10
	plane.size = Vector2(10.0, 10.0)
	#mesh = ArrayMesh.new()
	#mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane.surface_get_arrays(0), [], {})
	unity_builtin.override_resource(10209, "Plane", plane)
	var quad: PlaneMesh = PlaneMesh.new()
	quad.orientation = PlaneMesh.FACE_Z
	quad.size = Vector2(-1.0, 1.0)
	var quad_mesh: ArrayMesh = ArrayMesh.new()
	var quad_arrays: Array = quad.surface_get_arrays(0)
	# GODOT BUG: Quad mesh has incorrect normal if axis flipped.
	for i in range(len(quad_arrays[Mesh.ARRAY_NORMAL])):
		quad_arrays[Mesh.ARRAY_NORMAL][i] = Vector3(0, 0, -1)
	quad_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, quad_arrays, [], {})
	unity_builtin.override_resource(10210, "Quad", quad_mesh)

	var unity_extra = asset_meta_class.new()
	unity_extra.init_with_file(null, "Resources/unity_builtin_extra")
	unity_extra.initialize(self)
	unity_extra.resource_name = unity_extra.path
	unity_extra.guid = "0000000000000000f000000000000000"
	guid_to_path[unity_extra.guid] = unity_extra.path
	path_to_meta[unity_extra.path] = unity_extra

	var default_skybox: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	default_skybox.sky_top_color = Color(0.454902, 0.678431, 0.87451, 1)
	default_skybox.sky_horizon_color = Color(0.894118, 0.952941, 1, 1)
	default_skybox.sky_curve = 0.0731028
	default_skybox.ground_bottom_color = Color(0.454902, 0.470588, 0.490196, 1)
	default_skybox.ground_horizon_color = Color(1, 1, 1, 1)

	unity_extra.override_resource(10905, "UISprite", stub)
	unity_extra.override_resource(10302, "Default-Diffuse", default_material_reference)  # Legacy Shaders/Diffuse
	unity_extra.override_resource(10303, "Default-Material", default_material_reference)  # Standard
	unity_extra.override_resource(10304, "Default-Skybox", default_skybox)  # Skybox/Procedural
	unity_extra.override_resource(10306, "Default-Line", default_material_reference)  # Particles/Alpha Blended
	unity_extra.override_resource(10308, "Default-ParticleSystem", StandardMaterial3D.new())  # Particles/Standard Unlit
	unity_extra.override_resource(10754, "Sprites-Default", StandardMaterial3D.new())  # Sprites/Default
	unity_extra.override_resource(10758, "Sprites-Mask", StandardMaterial3D.new())  # Sprites/Mask
