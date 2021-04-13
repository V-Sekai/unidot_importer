@tool
extends Resource

const asset_meta_class: GDScript = preload("./asset_meta.gd")
const yaml_parser_class: GDScript = preload("./unity_object_parser.gd")
const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")

const ASSET_DATABASE_PATH: String = "res://unity_asset_database.tres"

var object_adapter = object_adapter_class.new()

@export var guid_to_path: Dictionary = {}
@export var path_to_meta: Dictionary = {}

# Must be non-null to hold material references
@export var truncated_shader_reference: Shader = null
@export var truncated_material_reference: Material = null
@export var null_material_reference: Material = null

# SEMI-STATIC
static func get_singleton() -> Object:

	var asset_database = load(ASSET_DATABASE_PATH)
	if asset_database == null:
		asset_database = new()
		asset_database.preload_builtin_assets()
		asset_database.save()
		asset_database = load(ASSET_DATABASE_PATH)
	return asset_database

func save():
	ResourceSaver.save(ASSET_DATABASE_PATH, self)

func insert_meta(meta: Resource): # asset_meta
	if meta.database == null:
		meta.initialize(self)
	guid_to_path[meta.guid] = meta.path
	path_to_meta[meta.path] = meta

func rename_meta(meta: Resource, new_path: String):
	if path_to_meta[meta.path] != meta:
		printerr("Renaming file not at the correct path")
	if guid_to_path[meta.guid] != meta.path:
		printerr("Renaming guid not at the correct path")
	path_to_meta.erase(meta.path)
	guid_to_path[meta.guid] = new_path
	path_to_meta[new_path] = meta
	meta.path = new_path

func get_meta_at_path(path: String) -> Resource: # asset_meta
	var ret: Resource = path_to_meta.get(path)
	if ret != null:
		if ret.database == null:
			ret.initialize(self)
	return ret

func get_meta_by_guid(guid: String) -> Resource: # asset_meta
	var path = guid_to_path.get(guid, "")
	if path != "":
		return get_meta_at_path(path)
	return null

func guid_to_asset_path(guid: String) -> String:
	return guid_to_path.get(guid, "")

static func create_dummy_meta(asset_path: String) -> Resource: # asset_meta
	var meta = asset_meta_class.new()
	meta.path = asset_path
	var hc: HashingContext = HashingContext.new()
	hc.start(HashingContext.HASH_MD5)
	hc.update("GodotDummyMetaGuid".to_ascii_buffer())
	hc.update(asset_path.to_ascii_buffer())
	meta.guid = hc.finish().hex_encode()
	return meta

static func parse_meta(file: Object, path: String) -> Resource: # asset_meta
	return asset_meta_class.parse_meta(file, path)

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
	null_material_reference.albedo_color = Color(1.0,0.0,1.0);

	var unity_builtin = asset_meta_class.new()
	unity_builtin.database = self
	unity_builtin.resource_name = "Library/unity default resources"
	unity_builtin.path = unity_builtin.resource_name
	unity_builtin.guid = "0000000000000000e000000000000000"
	guid_to_path[unity_builtin.guid] = unity_builtin.path
	path_to_meta[unity_builtin.path] = unity_builtin

	var stub = Resource.new()
	unity_builtin.override_resource(10001, "SpotCookie", stub) # Spot lights default attenuation
	unity_builtin.override_resource(10100, "Font Material", StandardMaterial3D.new()) # GUI/Text Shader
	unity_builtin.override_resource(10102, "Arial", stub) # Arial (font)
	var cube: BoxMesh = BoxMesh.new()
	cube.size = Vector3(1.0, 1.0, 1.0)
	unity_builtin.override_resource(10202 , "Cube", cube)
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
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(-1.0, 1.0)
	var quad_mesh: ArrayMesh = ArrayMesh.new()
	var quad_arrays: Array = quad.surface_get_arrays(0)
	# GODOT BUG: Quad mesh has incorrect normal if axis flipped.
	for i in range(len(quad_arrays[Mesh.ARRAY_NORMAL])):
		quad_arrays[Mesh.ARRAY_NORMAL][i] = Vector3(0,0,-1)
	quad_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, quad_arrays, [], {})
	unity_builtin.override_resource(10210, "Quad", quad_mesh)

	var unity_extra = asset_meta_class.new()
	unity_extra.database = self
	unity_extra.resource_name = "Resources/unity_builtin_extra"
	unity_extra.path = unity_extra.resource_name
	unity_extra.guid = "0000000000000000f000000000000000"
	guid_to_path[unity_extra.guid] = unity_extra.path
	path_to_meta[unity_extra.path] = unity_extra

	unity_extra.override_resource(10905, "UISprite", stub)
	unity_extra.override_resource(10302, "Default-Diffuse", StandardMaterial3D.new()) # Legacy Shaders/Diffuse
	unity_extra.override_resource(10303, "Default-Material", StandardMaterial3D.new()) # Standard
	unity_extra.override_resource(10304, "Default-Skybox", StandardMaterial3D.new()) # Skybox/Procedural
	unity_extra.override_resource(10306, "Default-Line", StandardMaterial3D.new()) # Particles/Alpha Blended
	unity_extra.override_resource(10308, "Default-ParticleSystem", StandardMaterial3D.new()) # Particles/Standard Unlit
	unity_extra.override_resource(10754, "Sprites-Default", StandardMaterial3D.new()) # Sprites/Default
	unity_extra.override_resource(10758, "Sprites-Mask", StandardMaterial3D.new()) # Sprites/Mask

