class_name UnidotModelImporter extends UnidotAssetImporter

func get_main_object_id() -> int:
	return 100100000  # a model is a type of Prefab

const SINGULAR_TO_GODOT_BONE_MAP: Dictionary = {
	"Spine": "Spine",
	"UpperChest": "UpperChest",
	"Chest": "Chest",
	"Head": "Head",
	"Hips": "Hips",
	"Jaw": "Jaw",
	"Neck": "Neck",
}

const HANDED_TO_GODOT_BONE_MAP: Dictionary = {
	" Index Distal": "IndexDistal",
	" Index Intermediate": "IndexIntermediate",
	" Index Proximal": "IndexProximal",
	" Little Distal": "LittleDistal",
	" Little Intermediate": "LittleIntermediate",
	" Little Proximal": "LittleProximal",
	" Middle Distal": "MiddleDistal",
	" Middle Intermediate": "MiddleIntermediate",
	" Middle Proximal": "MiddleProximal",
	" Ring Distal": "RingDistal",
	" Ring Intermediate": "RingIntermediate",
	" Ring Proximal": "RingProximal",
	" Thumb Distal": "ThumbDistal",
	" Thumb Intermediate": "ThumbProximal",
	" Thumb Proximal": "ThumbMetacarpal",
	"Eye": "Eye",
	"Foot": "Foot",
	"Hand": "Hand",
	"LowerArm": "LowerArm",
	"LowerLeg": "LowerLeg",
	"Shoulder": "Shoulder",
	"Toes": "Toes",
	"UpperArm": "UpperArm",
	"UpperLeg": "UpperLeg",
}

static func generate_bone_map_dict_no_root(log_obj: UnidotObject, humanDescriptionHuman: Array, humanNameKey := "m_HumanName", boneNameKey := "m_BoneName"):
	var bone_map_dict: Dictionary = {}
	for human in humanDescriptionHuman:
		var human_name: String = human[humanNameKey]
		var bone_name: String = human[boneNameKey]
		if human_name.begins_with("Left") or human_name.begins_with("Right"):
			var leftright = "Left" if human_name.begins_with("Left") else "Right"
			var human_key: String = human_name.substr(len(leftright))
			if human_key in HANDED_TO_GODOT_BONE_MAP:
				bone_map_dict[bone_name] = leftright + HANDED_TO_GODOT_BONE_MAP[human_key]
			else:
				log_obj.log_warn("Unrecognized " + str(leftright) + " humanName " + str(human_name) + " boneName " + str(bone_name))
		else:
			if human_name in SINGULAR_TO_GODOT_BONE_MAP:
				bone_map_dict[bone_name] = SINGULAR_TO_GODOT_BONE_MAP[human_name]
			else:
				log_obj.log_warn("Unrecognized humanName " + str(human_name) + " boneName " + str(bone_name))
	return bone_map_dict

func generate_bone_map_dict_from_human() -> Dictionary:
	if not meta.autodetected_bone_map_dict.is_empty():
		return meta.autodetected_bone_map_dict
	var humanDescription: Dictionary = self.keys["humanDescription"]
	var bone_map_dict: Dictionary = generate_bone_map_dict_no_root(self, humanDescription["human"], "humanName", "boneName")

	if not meta.internal_data.get("humanoid_root_bone", "").is_empty():
		bone_map_dict[meta.internal_data.get("humanoid_root_bone", "")] = "Root"
	meta.humanoid_bone_map_dict = bone_map_dict
	return bone_map_dict

func generate_bone_map_from_human() -> BoneMap:
	var bone_map: BoneMap = BoneMap.new()
	bone_map.profile = SkeletonProfileHumanoid.new()
	var bone_map_dict: Dictionary = generate_bone_map_dict_from_human()
	for skeleton_bone_name in bone_map_dict:
		var profile_bone_name = bone_map_dict[skeleton_bone_name]
		bone_map.set_skeleton_bone_name(profile_bone_name, skeleton_bone_name.replace("/", "_").replace(":", "_"))
	return bone_map
