# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# Originally based on bone_map_editor_plugin.cpp from Godot Engine
# Copyright (c) 2014-present Godot Engine contributors (see Godot AUTHORS.md).
# Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
# SPDX-License-Identifier: MIT
@tool

const SEG_NONE: int = 0
const SEG_LEFT: int = 1
const SEG_RIGHT: int = 2


static func search_bone_by_name(skeleton: Skeleton3D, p_picklist: PackedStringArray, p_segregation: int = SEG_NONE, p_parent: int = -1, p_child: int = -1, p_children_count: int = -1) -> int:
	print("Search bone by name " + str(p_picklist) + " from " + str(p_parent) + " " + str(p_child) + " " + str(p_children_count) + " " + str(p_segregation))
	# There may be multiple candidates hit by existing the subsidiary bone.
	# The one with the shortest name is probably the original.
	var hit_list: PackedStringArray = PackedStringArray()
	var shortest: String = ""

	for word in p_picklist:
		var re: RegEx = RegEx.new()
		re.compile(word)
		if p_child == -1:
			var bones_to_process: PackedInt32Array = skeleton.get_parentless_bones() if p_parent == -1 else skeleton.get_bone_children(p_parent)
			bones_to_process = bones_to_process.slice(0)
			var offset: int = 0
			while len(bones_to_process) > offset:
				var idx: int = bones_to_process[offset]
				offset += 1
				var children: PackedInt32Array = skeleton.get_bone_children(idx)
				for child in children:
					bones_to_process.push_back(child)

				if p_children_count == 0 && len(children) > 0:
					continue
				if p_children_count > 0 && len(children) < p_children_count:
					continue

				var bn: String = skeleton.get_bone_name(idx)
				if re.search(bn.to_lower()) != null && guess_bone_segregation(bn) == p_segregation:
					hit_list.push_back(bn)

			if hit_list.size() > 0:
				shortest = hit_list[0]
				for hit in hit_list:
					if len(hit) < len(shortest):
						shortest = hit  # Prioritize parent.
		else:
			var idx: int = skeleton.get_bone_parent(p_child)
			while idx != p_parent && idx >= 0:
				var children = skeleton.get_bone_children(idx)
				if p_children_count == 0 && len(children) > 0:
					continue
				if p_children_count > 0 && len(children) < p_children_count:
					continue

				var bn: String = skeleton.get_bone_name(idx)
				if re.search(bn.to_lower()) != null and guess_bone_segregation(bn) == p_segregation:
					hit_list.push_back(bn)
				idx = skeleton.get_bone_parent(idx)

			if hit_list.size() > 0:
				shortest = hit_list[0]
				for hit in hit_list:
					if len(hit) <= len(shortest):
						shortest = hit  # Prioritize parent.

		if not shortest.is_empty():
			break

	if shortest.is_empty():
		print("...Failed")
		return -1
	print("Found " + str(shortest))

	return skeleton.find_bone(shortest)


const left_words: Array[String] = ["(?<![a-zA-Z])left", "(?<![a-zA-Z0-9])l(?![a-zA-Z0-9])"]
const right_words: Array[String] = ["(?<![a-zA-Z])right", "(?<![a-zA-Z0-9])r(?![a-zA-Z0-9])"]


static func guess_bone_segregation(p_bone_name: String) -> int:
	var fixed_bn: String = p_bone_name.to_snake_case()

	for i in range(len(left_words)):
		var re_l: RegEx = RegEx.new()
		re_l.compile(left_words[i])
		if re_l.search(fixed_bn):
			return SEG_LEFT
		var re_r: RegEx = RegEx.new()
		re_r.compile(right_words[i])
		if re_r.search(fixed_bn):
			return SEG_RIGHT

	return SEG_NONE


static func auto_mapping_process_dictionary(skeleton: Skeleton3D) -> Dictionary:
	print("Run auto mapping.")
	var bone_map_dict: Dictionary = {}

	var bone_idx: int = -1
	var picklist: PackedStringArray = PackedStringArray()  # Use Vector<String> because match words have priority.
	var search_path: PackedInt32Array = PackedInt32Array()

	# 1. Guess Hips
	picklist.push_back("hip")
	picklist.push_back("pelvis")
	picklist.push_back("waist")
	picklist.push_back("torso")
	var hips: int = search_bone_by_name(skeleton, picklist)
	if hips == -1:
		print("Auto Mapping couldn't guess Hips. Abort auto mapping.")
		return {}  # If there is no Hips, we cannot guess bone after then.
	else:
		bone_map_dict[skeleton.get_bone_name(hips)] = "Hips"

	picklist.clear()

	# 2. Guess Root
	bone_idx = skeleton.get_bone_parent(hips)
	while bone_idx >= 0:
		search_path.push_back(bone_idx)
		bone_idx = skeleton.get_bone_parent(bone_idx)

	if search_path.is_empty():
		bone_idx = -1
	elif len(search_path) == 1:
		bone_idx = search_path[0]  # It is only one bone which can be root.
	else:
		var found: bool = false
		for spath in search_path:
			var re = RegEx.new()
			re.compile("root")
			if re.search(skeleton.get_bone_name(spath).to_lower()):
				bone_idx = spath  # Name match is preferred.
				found = true
				break
		if not found:
			for spath in search_path:
				if skeleton.get_bone_global_rest(spath).origin.is_zero_approx():
					bone_idx = spath  # The bone existing at the origin is appropriate as a root.
					found = true
					break
		if not found:
			bone_idx = search_path[len(search_path) - 1]  # Ambiguous, but most parental bone selected.

	if bone_idx == -1:
		pass
		# print("Auto Mapping couldn't guess Root.") # Root is not required, so continue.
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "Root"

	bone_idx = -1
	search_path.clear()

	# 3. Guess Neck
	picklist.push_back("neck")
	picklist.push_back("head")  # For no neck model.
	picklist.push_back("face")  # Same above.
	var neck: int = search_bone_by_name(skeleton, picklist, SEG_NONE, hips)
	picklist.clear()

	# 4. Guess Head
	picklist.push_back("head")
	picklist.push_back("face")
	var head: int = search_bone_by_name(skeleton, picklist, SEG_NONE, neck)
	if head == -1:
		search_path = skeleton.get_bone_children(neck)
		if search_path.size() == 1:
			head = search_path[0]  # Maybe only one child of the Neck is Head.

	if head == -1:
		if neck != -1:
			head = neck  # The head animation should have more movement.
			neck = -1
			bone_map_dict[skeleton.get_bone_name(head)] = "Head"
		else:
			print("Auto Mapping couldn't guess Neck or Head.")  # Continued for guessing on the other bones. But abort when guessing spines step.

	else:
		bone_map_dict[skeleton.get_bone_name(neck)] = "Neck"
		bone_map_dict[skeleton.get_bone_name(head)] = "Head"

	picklist.clear()
	search_path.clear()

	var neck_or_head: int = neck if neck != -1 else (head if head != -1 else -1)
	if neck_or_head != -1:
		# 4-1. Guess Eyes
		picklist.push_back("eye(?!.*(brow|lash|lid))")
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_LEFT, neck_or_head)
		if bone_idx == -1:
			print("Auto Mapping couldn't guess LeftEye.")
		else:
			bone_map_dict[skeleton.get_bone_name(bone_idx)] = "LeftEye"

		bone_idx = search_bone_by_name(skeleton, picklist, SEG_RIGHT, neck_or_head)
		if bone_idx == -1:
			print("Auto Mapping couldn't guess RightEye.")
		else:
			bone_map_dict[skeleton.get_bone_name(bone_idx)] = "RightEye"

		picklist.clear()

		# 4-2. Guess Jaw
		picklist.push_back("jaw")
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_NONE, neck_or_head)
		if bone_idx == -1:
			print("Auto Mapping couldn't guess Jaw.")
		else:
			bone_map_dict[skeleton.get_bone_name(bone_idx)] = "Jaw"

		bone_idx = -1
		picklist.clear()

	# 5. Guess Foots
	picklist.push_back("foot")
	picklist.push_back("ankle")
	var left_foot: int = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips)
	if left_foot == -1:
		print("Auto Mapping couldn't guess LeftFoot.")
	else:
		bone_map_dict[skeleton.get_bone_name(left_foot)] = "LeftFoot"

	var right_foot: int = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips)
	if right_foot == -1:
		print("Auto Mapping couldn't guess RightFoot.")
	else:
		bone_map_dict[skeleton.get_bone_name(right_foot)] = "RightFoot"

	picklist.clear()

	# 5-1. Guess LowerLegs
	picklist.push_back("(low|under).*leg")
	picklist.push_back("knee")
	picklist.push_back("shin")
	picklist.push_back("calf")
	picklist.push_back("leg")
	var left_lower_leg: int = -1
	if left_foot != -1:
		left_lower_leg = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips, left_foot)

	if left_lower_leg == -1:
		print("Auto Mapping couldn't guess LeftLowerLeg.")
	else:
		bone_map_dict[skeleton.get_bone_name(left_lower_leg)] = "LeftLowerLeg"

	var right_lower_leg: int = -1
	if right_foot != -1:
		right_lower_leg = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips, right_foot)

	if right_lower_leg == -1:
		print("Auto Mapping couldn't guess RightLowerLeg.")
	else:
		bone_map_dict[skeleton.get_bone_name(right_lower_leg)] = "RightLowerLeg"

	picklist.clear()

	# 5-2. Guess UpperLegs
	picklist.push_back("up.*leg")
	picklist.push_back("thigh")
	picklist.push_back("leg")
	if left_lower_leg != -1:
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips, left_lower_leg)

	if bone_idx == -1:
		print("Auto Mapping couldn't guess LeftUpperLeg.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "LeftUpperLeg"

	bone_idx = -1
	if right_lower_leg != -1:
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips, right_lower_leg)

	if bone_idx == -1:
		print("Auto Mapping couldn't guess RightUpperLeg.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "RightUpperLeg"

	bone_idx = -1
	picklist.clear()

	# 5-3. Guess Toes
	picklist.push_back("toe")
	picklist.push_back("ball")
	if left_foot != -1:
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_LEFT, left_foot)
		if bone_idx == -1:
			search_path = skeleton.get_bone_children(left_foot)
			if search_path.size() == 1:
				bone_idx = search_path[0]  # Maybe only one child of the Foot is Toes.

			search_path.clear()

	if bone_idx == -1:
		print("Auto Mapping couldn't guess LeftToes.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "LeftToes"

	bone_idx = -1
	if right_foot != -1:
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_RIGHT, right_foot)
		if bone_idx == -1:
			search_path = skeleton.get_bone_children(right_foot)
			if search_path.size() == 1:
				bone_idx = search_path[0]  # Maybe only one child of the Foot is Toes.

			search_path.clear()

	if bone_idx == -1:
		print("Auto Mapping couldn't guess RightToes.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "RightToes"

	bone_idx = -1
	picklist.clear()

	# 6. Guess Hands
	picklist.push_back("hand")
	picklist.push_back("wrist")
	picklist.push_back("palm")
	picklist.push_back("fingers")
	var left_hand_or_palm: int = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips, -1, 5)
	if left_hand_or_palm == -1:
		# Ambiguous, but try again for fewer finger models.
		left_hand_or_palm = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips)

	var left_hand: int = left_hand_or_palm  # Check for the presence of a wrist, since bones with five children may be palmar.
	while left_hand != -1:
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips, left_hand)
		if bone_idx == -1:
			break

		left_hand = bone_idx

	if left_hand == -1:
		print("Auto Mapping couldn't guess LeftHand.")
	else:
		bone_map_dict[skeleton.get_bone_name(left_hand)] = "LeftHand"

	bone_idx = -1
	var right_hand_or_palm: int = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips, -1, 5)
	if right_hand_or_palm == -1:
		# Ambiguous, but try again for fewer finger models.
		right_hand_or_palm = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips)

	var right_hand: int = right_hand_or_palm
	while right_hand != -1:
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips, right_hand)
		if bone_idx == -1:
			break

		right_hand = bone_idx

	if right_hand == -1:
		print("Auto Mapping couldn't guess RightHand.")
	else:
		bone_map_dict[skeleton.get_bone_name(right_hand)] = "RightHand"

	bone_idx = -1
	picklist.clear()
	print("Now fingers")
	# 6-1. Guess Finger
	var named_finger_is_found: bool = false
	var fingers: PackedStringArray
	fingers.push_back("thumb|pollex")
	fingers.push_back("index|fore")
	fingers.push_back("middle")
	fingers.push_back("ring")
	fingers.push_back("little|pinkie|pinky")
	if left_hand_or_palm != -1:
		var left_fingers_map: Array[PackedStringArray] = []
		left_fingers_map.resize(5)
		left_fingers_map[0].push_back("LeftThumbMetacarpal")
		left_fingers_map[0].push_back("LeftThumbProximal")
		left_fingers_map[0].push_back("LeftThumbDistal")
		left_fingers_map[1].push_back("LeftIndexProximal")
		left_fingers_map[1].push_back("LeftIndexIntermediate")
		left_fingers_map[1].push_back("LeftIndexDistal")
		left_fingers_map[2].push_back("LeftMiddleProximal")
		left_fingers_map[2].push_back("LeftMiddleIntermediate")
		left_fingers_map[2].push_back("LeftMiddleDistal")
		left_fingers_map[3].push_back("LeftRingProximal")
		left_fingers_map[3].push_back("LeftRingIntermediate")
		left_fingers_map[3].push_back("LeftRingDistal")
		left_fingers_map[4].push_back("LeftLittleProximal")
		left_fingers_map[4].push_back("LeftLittleIntermediate")
		left_fingers_map[4].push_back("LeftLittleDistal")
		for i in range(5):
			picklist.push_back(fingers[i])
			var finger: int = search_bone_by_name(skeleton, picklist, SEG_LEFT, left_hand_or_palm, -1, 0)
			if finger != -1:
				while finger != left_hand_or_palm && finger >= 0:
					search_path.push_back(finger)
					finger = skeleton.get_bone_parent(finger)

				search_path.reverse()
				if search_path.size() == 1:
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
					named_finger_is_found = true
				elif search_path.size() == 2:
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = left_fingers_map[i][1]
					named_finger_is_found = true
				elif search_path.size() >= 3:
					search_path = search_path.slice(-3)  # Eliminate the possibility of carpal bone.
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = left_fingers_map[i][1]
					bone_map_dict[skeleton.get_bone_name(search_path[2])] = left_fingers_map[i][2]
					named_finger_is_found = true

			picklist.clear()
			search_path.clear()

		# It is a bit corner case, but possibly the finger names are sequentially numbered...
		if !named_finger_is_found:
			picklist.push_back("finger")
			var finger_re = RegEx.new()
			finger_re.compile("finger")
			search_path = skeleton.get_bone_children(left_hand_or_palm)
			var finger_names: PackedStringArray
			for spath in search_path:
				var bn: String = skeleton.get_bone_name(spath)
				if finger_re.search(bn.to_lower()):
					finger_names.push_back(bn)
			finger_names.sort()  # Order by lexicographic, normal use cases never have more than 10 fingers in one hand.
			search_path.clear()
			for i in range(len(finger_names)):
				if i >= 5:
					break

				var finger_root: int = skeleton.find_bone(finger_names[i])
				var finger: int = search_bone_by_name(skeleton, picklist, SEG_LEFT, finger_root, -1, 0)
				if finger != -1:
					while finger != finger_root && finger >= 0:
						search_path.push_back(finger)
						finger = skeleton.get_bone_parent(finger)

				search_path.push_back(finger_root)
				search_path.reverse()
				if search_path.size() == 1:
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
				elif search_path.size() == 2:
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = left_fingers_map[i][1]
				elif search_path.size() >= 3:
					search_path = search_path.slice(-3)  # Eliminate the possibility of carpal bone.
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = left_fingers_map[i][1]
					bone_map_dict[skeleton.get_bone_name(search_path[2])] = left_fingers_map[i][2]

				search_path.clear()

			picklist.clear()

	named_finger_is_found = false
	if right_hand_or_palm != -1:
		var right_fingers_map: Array[PackedStringArray] = []
		right_fingers_map.resize(5)
		right_fingers_map[0].push_back("RightThumbMetacarpal")
		right_fingers_map[0].push_back("RightThumbProximal")
		right_fingers_map[0].push_back("RightThumbDistal")
		right_fingers_map[1].push_back("RightIndexProximal")
		right_fingers_map[1].push_back("RightIndexIntermediate")
		right_fingers_map[1].push_back("RightIndexDistal")
		right_fingers_map[2].push_back("RightMiddleProximal")
		right_fingers_map[2].push_back("RightMiddleIntermediate")
		right_fingers_map[2].push_back("RightMiddleDistal")
		right_fingers_map[3].push_back("RightRingProximal")
		right_fingers_map[3].push_back("RightRingIntermediate")
		right_fingers_map[3].push_back("RightRingDistal")
		right_fingers_map[4].push_back("RightLittleProximal")
		right_fingers_map[4].push_back("RightLittleIntermediate")
		right_fingers_map[4].push_back("RightLittleDistal")
		for i in range(5):
			picklist.push_back(fingers[i])
			var finger: int = search_bone_by_name(skeleton, picklist, SEG_RIGHT, right_hand_or_palm, -1, 0)
			if finger != -1:
				while finger != right_hand_or_palm && finger >= 0:
					search_path.push_back(finger)
					finger = skeleton.get_bone_parent(finger)

				search_path.reverse()
				if search_path.size() == 1:
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = right_fingers_map[i][0]
					named_finger_is_found = true
				elif search_path.size() == 2:
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = right_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = right_fingers_map[i][1]
					named_finger_is_found = true
				elif search_path.size() >= 3:
					search_path = search_path.slice(-3)  # Eliminate the possibility of carpal bone.
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = right_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = right_fingers_map[i][1]
					bone_map_dict[skeleton.get_bone_name(search_path[2])] = right_fingers_map[i][2]
					named_finger_is_found = true

			picklist.clear()
			search_path.clear()

		# It is a bit corner case, but possibly the finger names are sequentially numbered...
		if !named_finger_is_found:
			picklist.push_back("finger")
			var finger_re = RegEx.new()
			finger_re.compile("finger")
			search_path = skeleton.get_bone_children(right_hand_or_palm)
			var finger_names: PackedStringArray
			for spath in search_path:
				var bn: String = skeleton.get_bone_name(spath)
				if finger_re.search(bn.to_lower()):
					finger_names.push_back(bn)

			finger_names.sort()  # Order by lexicographic, normal use cases never have more than 10 fingers in one hand.
			search_path.clear()
			for i in range(len(finger_names)):
				if i >= 5:
					break

				var finger_root: int = skeleton.find_bone(finger_names[i])
				var finger: int = search_bone_by_name(skeleton, picklist, SEG_RIGHT, finger_root, -1, 0)
				if finger != -1:
					while finger != finger_root && finger >= 0:
						search_path.push_back(finger)
						finger = skeleton.get_bone_parent(finger)

				search_path.push_back(finger_root)
				search_path.reverse()
				if search_path.size() == 1:
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = right_fingers_map[i][0]
				elif search_path.size() == 2:
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = right_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = right_fingers_map[i][1]
				elif search_path.size() >= 3:
					search_path = search_path.slice(-3)  # Eliminate the possibility of carpal bone.
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = right_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = right_fingers_map[i][1]
					bone_map_dict[skeleton.get_bone_name(search_path[2])] = right_fingers_map[i][2]

				search_path.clear()

			picklist.clear()

	# 7. Guess Arms
	picklist.push_back("shoulder")
	picklist.push_back("clavicle")
	picklist.push_back("collar")
	var left_shoulder: int = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips)
	if left_shoulder == -1:
		print("Auto Mapping couldn't guess LeftShoulder.")
	else:
		bone_map_dict[skeleton.get_bone_name(left_shoulder)] = "LeftShoulder"

	var right_shoulder: int = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips)
	if right_shoulder == -1:
		print("Auto Mapping couldn't guess RightShoulder.")
	else:
		bone_map_dict[skeleton.get_bone_name(right_shoulder)] = "RightShoulder"

	picklist.clear()

	# 7-1. Guess LowerArms
	picklist.push_back("(low|fore).*arm")
	picklist.push_back("elbow")
	picklist.push_back("arm")
	var left_lower_arm: int = -1
	if left_shoulder != -1 && left_hand_or_palm != -1:
		left_lower_arm = search_bone_by_name(skeleton, picklist, SEG_LEFT, left_shoulder, left_hand_or_palm)

	if left_lower_arm == -1:
		print("Auto Mapping couldn't guess LeftLowerArm.")
	else:
		bone_map_dict[skeleton.get_bone_name(left_lower_arm)] = "LeftLowerArm"

	var right_lower_arm: int = -1
	if right_shoulder != -1 && right_hand_or_palm != -1:
		right_lower_arm = search_bone_by_name(skeleton, picklist, SEG_RIGHT, right_shoulder, right_hand_or_palm)

	if right_lower_arm == -1:
		print("Auto Mapping couldn't guess RightLowerArm.")
	else:
		bone_map_dict[skeleton.get_bone_name(right_lower_arm)] = "RightLowerArm"

	picklist.clear()

	# 7-2. Guess UpperArms
	picklist.push_back("up.*arm")
	picklist.push_back("arm")
	if left_shoulder != -1 && left_lower_arm != -1:
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_LEFT, left_shoulder, left_lower_arm)

	if bone_idx == -1:
		print("Auto Mapping couldn't guess LeftUpperArm.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "LeftUpperArm"

	bone_idx = -1
	if right_shoulder != -1 && right_lower_arm != -1:
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_RIGHT, right_shoulder, right_lower_arm)

	if bone_idx == -1:
		print("Auto Mapping couldn't guess RightUpperArm.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "RightUpperArm"

	bone_idx = -1
	picklist.clear()

	# 8. Guess UpperChest or Chest
	if neck_or_head == -1:
		print("Auto Mapping couldn't guess Neck or Head! Abort auto mapping.")
		return {}  # Abort.

	var chest_or_upper_chest: int = skeleton.get_bone_parent(neck_or_head)
	var is_appropriate: bool = true
	if left_shoulder != -1:
		bone_idx = skeleton.get_bone_parent(left_shoulder)
		var detect: bool = false
		while bone_idx != hips && bone_idx >= 0:
			if bone_idx == chest_or_upper_chest:
				detect = true
				break

			bone_idx = skeleton.get_bone_parent(bone_idx)

		if !detect:
			is_appropriate = false

		bone_idx = -1

	if right_shoulder != -1:
		bone_idx = skeleton.get_bone_parent(right_shoulder)
		var detect: bool = false
		while bone_idx != hips && bone_idx >= 0:
			if bone_idx == chest_or_upper_chest:
				detect = true
				break

			bone_idx = skeleton.get_bone_parent(bone_idx)

		if !detect:
			is_appropriate = false

		bone_idx = -1

	if !is_appropriate:
		if skeleton.get_bone_parent(left_shoulder) == skeleton.get_bone_parent(right_shoulder):
			chest_or_upper_chest = skeleton.get_bone_parent(left_shoulder)
		else:
			chest_or_upper_chest = -1

	if chest_or_upper_chest == -1:
		print("Auto Mapping couldn't guess Chest or UpperChest. Abort auto mapping.")
		return {}  # Will be not able to guess Spines.

	# 9. Guess Spines
	bone_idx = skeleton.get_bone_parent(chest_or_upper_chest)
	while bone_idx != hips && bone_idx >= 0:
		search_path.push_back(bone_idx)
		bone_idx = skeleton.get_bone_parent(bone_idx)

	search_path.reverse()
	if search_path.size() == 0:
		bone_map_dict[skeleton.get_bone_name(chest_or_upper_chest)] = "Spine"  # Maybe chibi model...?
	elif search_path.size() == 1:
		bone_map_dict[skeleton.get_bone_name(search_path[0])] = "Spine"
		bone_map_dict[skeleton.get_bone_name(chest_or_upper_chest)] = "Chest"
	elif search_path.size() >= 2:
		bone_map_dict[skeleton.get_bone_name(search_path[0])] = "Spine"
		bone_map_dict[skeleton.get_bone_name(search_path[search_path.size() - 1])] = "Chest"  # Probably UppeChest's parent is appropriate.
		bone_map_dict[skeleton.get_bone_name(chest_or_upper_chest)] = "UpperChest"

	bone_idx = -1
	search_path.clear()

	print("Finish auto mapping.")
	return bone_map_dict


static func auto_mapping_to_bone_map(skeleton: Skeleton3D, bone_map_dict: Dictionary, bone_map: BoneMap):
	bone_map.profile = SkeletonProfileHumanoid.new()
	for skeleton_bone_name in bone_map_dict:
		var profile_bone_name = bone_map_dict[skeleton_bone_name]
		bone_map.set_skeleton_bone_name(profile_bone_name, skeleton_bone_name)


static func gltf_matrix_to_trs(json_node: Dictionary) -> void:
	if json_node.has("matrix"):
		# Convert node to TRS notation.
		var mat: Array = json_node.get("matrix", [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
		var basis: Basis = Basis(Vector3(mat[0], mat[1], mat[2]), Vector3(mat[4], mat[5], mat[6]), Vector3(mat[8], mat[9], mat[10]))
		var position := Vector3(mat[12], mat[13], mat[14])
		var scale := basis.get_scale()
		var quat := basis.get_rotation_quaternion()
		json_node.erase("matrix")
		json_node["translation"] = [position.x, position.y, position.z]
		json_node["scale"] = [scale.x, scale.y, scale.z]
		json_node["rotation"] = [quat.x, quat.y, quat.z, quat.w]


static func gltf_to_skel_bone(json_node: Dictionary, skel: Skeleton3D, bone_idx: int) -> void:
	var tra: Array = json_node.get("translation", [0, 0, 0])
	var rot: Array = json_node.get("rotation", [0, 0, 0, 1])
	var sca: Array = json_node.get("scale", [1, 1, 1])
	skel.set_bone_pose_rotation(bone_idx, Quaternion(rot[0], rot[1], rot[2], rot[3]))
	skel.set_bone_pose_scale(bone_idx, Vector3(sca[0], sca[1], sca[2]))
	skel.set_bone_pose_position(bone_idx, Vector3(tra[0], tra[1], tra[2]))
	skel.set_bone_rest(bone_idx, skel.get_bone_pose(bone_idx))


static func silhouette_fix_gltf(json: Dictionary, bone_map: BoneMap, p_threshold: float) -> void:
	var profile: SkeletonProfile = bone_map.get_profile()
	# Build profile skeleton.
	var src_skeleton := Skeleton3D.new()
	var prof_skeleton := Skeleton3D.new()

	const blacklist: Dictionary = {"LeftFoot": true, "RightFoot": true, "LeftToes": true, "RightToes": true}

	# Add single bones.
	var bone_map_dict: Dictionary
	var profile_bones: Dictionary
	for i in range(profile.get_bone_size()):
		bone_map_dict[bone_map.get_skeleton_bone_name(profile.get_bone_name(i))] = profile.get_bone_name(i)
		profile_bones[profile.get_bone_name(i)] = true
		prof_skeleton.add_bone(profile.get_bone_name(i))
		prof_skeleton.set_bone_rest(i, profile.get_reference_pose(i))
	# Set parents.
	for i in range(profile.get_bone_size()):
		var parent : int = profile.find_bone(profile.get_bone_parent(i))
		if (parent >= 0):
			prof_skeleton.set_bone_parent(i, parent)

	var bone_parents_to_process: Array[Vector2i]
	for node_idx in PackedInt32Array(json["scenes"][json.get("scene", 0)]["nodes"]):
		bone_parents_to_process.push_back(Vector2i(-1, node_idx))
	for node_idx in range(len(json["nodes"])):
		var node_name: String = json["nodes"][node_idx].get("name", "")
		node_name = node_name.replace(":","_").replace("/","_")
		if bone_map_dict.has(node_name):
			node_name = bone_map_dict[node_name]
		else:
			node_name = str(node_idx) + "_" + node_name
		src_skeleton.add_bone(node_name)
	var process_i: int = 0
	while process_i < len(bone_parents_to_process):
		var parent_child: Vector2i = bone_parents_to_process[process_i]
		process_i += 1
		var parent_idx: int = parent_child.x
		var node_idx: int = parent_child.y
		for child_idx in PackedInt32Array(json["nodes"][node_idx].get("children", [])):
			bone_parents_to_process.push_back(Vector2i(node_idx, child_idx))
		if parent_idx != -1:
			src_skeleton.set_bone_parent(node_idx, parent_idx)
		gltf_matrix_to_trs(json["nodes"][node_idx]) # Convert glTF matrix format to TRS.
		gltf_to_skel_bone(json["nodes"][node_idx], src_skeleton, node_idx)

	var bones_to_process: PackedInt32Array
	bones_to_process.append_array(prof_skeleton.get_parentless_bones())
	process_i = 0
	while process_i < len(bones_to_process):
		var prof_idx: int = bones_to_process[process_i]
		process_i += 1
		var bone_children: PackedInt32Array = prof_skeleton.get_bone_children(prof_idx)
		bones_to_process.append_array(bone_children)
		var src_idx: int = src_skeleton.find_bone(prof_skeleton.get_bone_name(prof_idx))
		if src_idx < 0 or profile.get_tail_direction(prof_idx) == SkeletonProfile.TAIL_DIRECTION_END:
			continue

		# Calc virtual/looking direction with origins.
		var prof_tail: Vector3
		var src_tail: Vector3
		if profile.get_tail_direction(prof_idx) == SkeletonProfile.TAIL_DIRECTION_AVERAGE_CHILDREN:
			var prof_bone_children: PackedInt32Array = prof_skeleton.get_bone_children(prof_idx);
			if prof_bone_children.is_empty():
				continue
			var exist_all_children := true;
			for prof_child_idx in prof_bone_children:
				var src_child_idx: int = src_skeleton.find_bone(prof_skeleton.get_bone_name(prof_child_idx))
				if src_child_idx < 0:
					exist_all_children = false
					break
				prof_tail = prof_tail + prof_skeleton.get_bone_global_rest(prof_child_idx).origin
				src_tail = src_tail + src_skeleton.get_bone_global_rest(src_child_idx).origin

			if not exist_all_children:
				continue
			prof_tail = prof_tail / len(bone_children)
			src_tail = src_tail / len(bone_children)

		elif prof_skeleton.get_bone_name(prof_idx) == "Hips":
			var tmp_head: Vector3 = prof_skeleton.get_bone_global_rest(prof_idx).origin;
			var tmp_src_head: Vector3 = src_skeleton.get_bone_global_rest(src_idx).origin;
			var prof_tail_idx: int = prof_skeleton.find_bone(profile.get_bone_tail(prof_idx));
			if prof_tail_idx < 0:
				continue
			prof_tail = prof_skeleton.get_bone_global_rest(prof_tail_idx).origin
			src_tail = tmp_src_head + (prof_tail - tmp_head)

		elif profile.get_tail_direction(prof_idx) == SkeletonProfile.TAIL_DIRECTION_SPECIFIC_CHILD:
			var prof_tail_idx: int = prof_skeleton.find_bone(profile.get_bone_tail(prof_idx));
			if prof_tail_idx < 0:
				continue
			var src_tail_idx: int = src_skeleton.find_bone(prof_skeleton.get_bone_name(prof_tail_idx))
			if src_tail_idx < 0:
				continue
			prof_tail = prof_skeleton.get_bone_global_rest(prof_tail_idx).origin
			src_tail = src_skeleton.get_bone_global_rest(src_tail_idx).origin

		var prof_head: Vector3 = prof_skeleton.get_bone_global_rest(prof_idx).origin;
		var src_head: Vector3 = src_skeleton.get_bone_global_rest(src_idx).origin;

		var prof_dir: Vector3 = prof_tail - prof_head;
		var src_dir: Vector3 = src_tail - src_head;

		# Rotate rest.
		if absf(rad_to_deg(src_dir.angle_to(prof_dir))) > p_threshold and not blacklist.has(prof_skeleton.get_bone_name(prof_idx)):
			# Get rotation difference.
			var up_vec: Vector3 # Need to rotate other than roll axis.
			match (Vector3(abs(src_dir.x), abs(src_dir.y), abs(src_dir.z)).min_axis_index()):
				Vector3.AXIS_X:
					up_vec = Vector3(1, 0, 0)
				Vector3.AXIS_Y:
					up_vec = Vector3(0, 1, 0)
				Vector3.AXIS_Z:
					up_vec = Vector3(0, 0, 1)
			var src_b: Basis = Basis().looking_at(src_dir, up_vec);
			var prof_b: Basis = src_b.looking_at(prof_dir, up_vec);
			if prof_b.is_equal_approx(Basis()):
				continue # May not need to rotate.
			var diff_b: Basis = prof_b * src_b.inverse();

			# Apply rotation difference as global transform to skeleton.
			var src_pg: Basis
			var src_parent: int = src_skeleton.get_bone_parent(src_idx)
			if src_parent >= 0:
				src_pg = src_skeleton.get_bone_global_rest(src_parent).basis
			var fixed_rest_basis := src_pg.inverse() * diff_b * src_pg * src_skeleton.get_bone_rest(src_idx).basis

			# And now, modify both the bone pose/rest and the gltf json itself.
			src_skeleton.set_bone_pose_rotation(src_idx, fixed_rest_basis.get_rotation_quaternion())
			src_skeleton.set_bone_rest(src_idx, src_skeleton.get_bone_pose(src_idx))
			var quat := src_skeleton.get_bone_pose_rotation(src_idx)
			# Update glTF JSON
			json["nodes"][src_idx]["rotation"] = [quat.x, quat.y, quat.z, quat.w]
	# Now fix translation offsets:
	var hips_src_idx: int = src_skeleton.find_bone("Hips")
	if hips_src_idx != -1:
		var hips_global_origin := src_skeleton.get_bone_global_rest(hips_src_idx).origin
		var hips_parent_basis := Basis.IDENTITY
		var src_idx := src_skeleton.get_bone_parent(hips_src_idx)
		while src_idx != -1:
			if json["nodes"][src_idx].has("translation"):
				json["nodes"][src_idx].erase("translation")
			hips_parent_basis = src_skeleton.get_bone_pose(src_idx).basis * hips_parent_basis
			src_idx = src_skeleton.get_bone_parent(src_idx)
		var new_hips_origin := hips_parent_basis.inverse() * Vector3(0, hips_global_origin.y, 0)
		json["nodes"][hips_src_idx]["translation"] = [new_hips_origin.x, new_hips_origin.y, new_hips_origin.z]
	# Never added into the tree, so free them.
	src_skeleton.free()
	prof_skeleton.free()
