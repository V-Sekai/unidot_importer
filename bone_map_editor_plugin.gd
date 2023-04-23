#**************************************************************************/
#*  bone_map_editor_plugin.cpp                                            */
#**************************************************************************/
#*                         This file is part of:                          */
#*                             GODOT ENGINE                               */
#*                        https:#godotengine.org                         */
#**************************************************************************/
#* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
#* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
#*                                                                        */
#* Permission is hereby granted, free of charge, to any person obtaining  */
#* a copy of this software and associated documentation files (the        */
#* "Software"), to deal in the Software without restriction, including    */
#* without limitation the rights to use, copy, modify, merge, publish,    */
#* distribute, sublicense, and/or sell copies of the Software, and to     */
#* permit persons to whom the Software is furnished to do so, subject to  */
#* the following conditions:                                              */
#*                                                                        */
#* The above copyright notice and this permission notice shall be         */
#* included in all copies or substantial portions of the Software.        */
#*                                                                        */
#* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
#* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
#* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
#* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
#* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
#* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
#* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
#**************************************************************************/

const SEG_NONE: int = 0
const SEG_LEFT: int = 1
const SEG_RIGHT: int = 2

static func search_bone_by_name(skeleton: Skeleton3D, p_picklist: PackedStringArray, p_segregation: int=SEG_NONE, p_parent: int=-1, p_child: int=-1, p_children_count: int=-1) -> int:
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
			while (len(bones_to_process) > offset):
				var idx: int = bones_to_process[offset]
				offset += 1
				var children: PackedInt32Array = skeleton.get_bone_children(idx)
				for child in children:
					bones_to_process.push_back(child)

				if (p_children_count == 0 && len(children) > 0):
					continue
				if (p_children_count > 0 && len(children) < p_children_count):
					continue

				var bn: String = skeleton.get_bone_name(idx)
				if (re.search(bn.to_lower()) != null && guess_bone_segregation(bn) == p_segregation):
					hit_list.push_back(bn)

			if hit_list.size() > 0:
				shortest = hit_list[0]
				for hit in hit_list:
					if len(hit) < len(shortest):
						shortest = hit # Prioritize parent.
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
						shortest = hit # Prioritize parent.

		if not shortest.is_empty():
			break;

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
	var picklist: PackedStringArray = PackedStringArray() # Use Vector<String> because match words have priority.
	var search_path: PackedInt32Array = PackedInt32Array()

	# 1. Guess Hips
	picklist.push_back("hip")
	picklist.push_back("pelvis")
	picklist.push_back("waist")
	picklist.push_back("torso")
	var hips: int = search_bone_by_name(skeleton, picklist)
	if (hips == -1):
		print("Auto Mapping couldn't guess Hips. Abort auto mapping.")
		return {} # If there is no Hips, we cannot guess bone after then.
	else:
		bone_map_dict[skeleton.get_bone_name(hips)] = "Hips"

	picklist.clear()

	# 2. Guess Root
	bone_idx = skeleton.get_bone_parent(hips)
	while (bone_idx >= 0):
		search_path.push_back(bone_idx)
		bone_idx = skeleton.get_bone_parent(bone_idx)

	if search_path.is_empty():
		bone_idx = -1
	elif len(search_path) == 1:
		bone_idx = search_path[0] # It is only one bone which can be root.
	else:
		var found: bool = false
		for spath in search_path:
			var re = RegEx.new()
			re.compile("root")
			if (re.search(skeleton.get_bone_name(spath).to_lower())):
				bone_idx = spath # Name match is preferred.
				found = true
				break
		if not found:
			for spath in search_path:
				if (skeleton.get_bone_global_rest(spath).origin.is_zero_approx()):
					bone_idx = spath # The bone existing at the origin is appropriate as a root.
					found = true
					break
		if not found:
			bone_idx = search_path[len(search_path) - 1] # Ambiguous, but most parental bone selected.

	if bone_idx == -1:
		pass
		# print("Auto Mapping couldn't guess Root.") # Root is not required, so continue.
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "Root"

	bone_idx = -1
	search_path.clear()

	# 3. Guess Neck
	picklist.push_back("neck")
	picklist.push_back("head") # For no neck model.
	picklist.push_back("face") # Same above.
	var neck: int = search_bone_by_name(skeleton, picklist, SEG_NONE, hips)
	picklist.clear()

	# 4. Guess Head
	picklist.push_back("head")
	picklist.push_back("face")
	var head: int = search_bone_by_name(skeleton, picklist, SEG_NONE, neck)
	if (head == -1):
		search_path = skeleton.get_bone_children(neck)
		if (search_path.size() == 1):
			head = search_path[0]; # Maybe only one child of the Neck is Head.


	if (head == -1):
		if (neck != -1):
			head = neck; # The head animation should have more movement.
			neck = -1;
			bone_map_dict[skeleton.get_bone_name(head)] = "Head"
		else:
			print("Auto Mapping couldn't guess Neck or Head.") # Continued for guessing on the other bones. But abort when guessing spines step.

	else:
		bone_map_dict[skeleton.get_bone_name(neck)] = "Neck"
		bone_map_dict[skeleton.get_bone_name(head)] = "Head"

	picklist.clear()
	search_path.clear()

	var neck_or_head: int = neck if neck != -1 else (head if head != -1 else -1)
	if (neck_or_head != -1):
		# 4-1. Guess Eyes
		picklist.push_back("eye(?!.*(brow|lash|lid))")
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_LEFT, neck_or_head)
		if (bone_idx == -1):
			print("Auto Mapping couldn't guess LeftEye.")
		else:
			bone_map_dict[skeleton.get_bone_name(bone_idx)] = "LeftEye"


		bone_idx = search_bone_by_name(skeleton, picklist, SEG_RIGHT, neck_or_head)
		if (bone_idx == -1):
			print("Auto Mapping couldn't guess RightEye.")
		else:
			bone_map_dict[skeleton.get_bone_name(bone_idx)] = "RightEye"

		picklist.clear()

		# 4-2. Guess Jaw
		picklist.push_back("jaw")
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_NONE, neck_or_head)
		if (bone_idx == -1):
			print("Auto Mapping couldn't guess Jaw.")
		else:
			bone_map_dict[skeleton.get_bone_name(bone_idx)] = "Jaw"

		bone_idx = -1;
		picklist.clear()


	# 5. Guess Foots
	picklist.push_back("foot")
	picklist.push_back("ankle")
	var left_foot: int = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips)
	if (left_foot == -1):
		print("Auto Mapping couldn't guess LeftFoot.")
	else:
		bone_map_dict[skeleton.get_bone_name(left_foot)] = "LeftFoot"

	var right_foot: int = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips)
	if (right_foot == -1):
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
	var left_lower_leg: int = -1;
	if (left_foot != -1):
		left_lower_leg = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips, left_foot)

	if (left_lower_leg == -1):
		print("Auto Mapping couldn't guess LeftLowerLeg.")
	else:
		bone_map_dict[skeleton.get_bone_name(left_lower_leg)] = "LeftLowerLeg"

	var right_lower_leg: int = -1;
	if (right_foot != -1):
		right_lower_leg = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips, right_foot)

	if (right_lower_leg == -1):
		print("Auto Mapping couldn't guess RightLowerLeg.")
	else:
		bone_map_dict[skeleton.get_bone_name(right_lower_leg)] = "RightLowerLeg"

	picklist.clear()

	# 5-2. Guess UpperLegs
	picklist.push_back("up.*leg")
	picklist.push_back("thigh")
	picklist.push_back("leg")
	if (left_lower_leg != -1):
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips, left_lower_leg)

	if (bone_idx == -1):
		print("Auto Mapping couldn't guess LeftUpperLeg.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "LeftUpperLeg"

	bone_idx = -1;
	if (right_lower_leg != -1):
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips, right_lower_leg)

	if (bone_idx == -1):
		print("Auto Mapping couldn't guess RightUpperLeg.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "RightUpperLeg"

	bone_idx = -1;
	picklist.clear()

	# 5-3. Guess Toes
	picklist.push_back("toe")
	picklist.push_back("ball")
	if (left_foot != -1):
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_LEFT, left_foot)
		if (bone_idx == -1):
			search_path = skeleton.get_bone_children(left_foot)
			if (search_path.size() == 1):
				bone_idx = search_path[0]; # Maybe only one child of the Foot is Toes.

			search_path.clear()


	if (bone_idx == -1):
		print("Auto Mapping couldn't guess LeftToes.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "LeftToes"

	bone_idx = -1;
	if (right_foot != -1):
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_RIGHT, right_foot)
		if (bone_idx == -1):
			search_path = skeleton.get_bone_children(right_foot)
			if (search_path.size() == 1):
				bone_idx = search_path[0]; # Maybe only one child of the Foot is Toes.

			search_path.clear()


	if (bone_idx == -1):
		print("Auto Mapping couldn't guess RightToes.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "RightToes"

	bone_idx = -1;
	picklist.clear()

	# 6. Guess Hands
	picklist.push_back("hand")
	picklist.push_back("wrist")
	picklist.push_back("palm")
	picklist.push_back("fingers")
	var left_hand_or_palm: int = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips, -1, 5)
	if (left_hand_or_palm == -1):
		# Ambiguous, but try again for fewer finger models.
		left_hand_or_palm = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips)

	var left_hand: int = left_hand_or_palm; # Check for the presence of a wrist, since bones with five children may be palmar.
	while (left_hand != -1):
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_LEFT, hips, left_hand)
		if (bone_idx == -1):
			break;

		left_hand = bone_idx;

	if (left_hand == -1):
		print("Auto Mapping couldn't guess LeftHand.")
	else:
		bone_map_dict[skeleton.get_bone_name(left_hand)] = "LeftHand"

	bone_idx = -1;
	var right_hand_or_palm: int = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips, -1, 5)
	if (right_hand_or_palm == -1):
		# Ambiguous, but try again for fewer finger models.
		right_hand_or_palm = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips)

	var right_hand: int = right_hand_or_palm;
	while (right_hand != -1):
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips, right_hand)
		if (bone_idx == -1):
			break;

		right_hand = bone_idx;

	if (right_hand == -1):
		print("Auto Mapping couldn't guess RightHand.")
	else:
		bone_map_dict[skeleton.get_bone_name(right_hand)] = "RightHand"

	bone_idx = -1;
	picklist.clear()
	print ("Now fingers")
	# 6-1. Guess Finger
	var named_finger_is_found: bool = false
	var fingers: PackedStringArray
	fingers.push_back("thumb|pollex")
	fingers.push_back("index|fore")
	fingers.push_back("middle")
	fingers.push_back("ring")
	fingers.push_back("little|pinkie|pinky")
	if (left_hand_or_palm != -1):
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
			if (finger != -1):
				while (finger != left_hand_or_palm && finger >= 0):
					search_path.push_back(finger)
					finger = skeleton.get_bone_parent(finger)

				search_path.reverse()
				if (search_path.size() == 1):
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
					named_finger_is_found = true;
				elif (search_path.size() == 2):
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = left_fingers_map[i][1]
					named_finger_is_found = true;
				elif (search_path.size() >= 3):
					search_path = search_path.slice(-3) # Eliminate the possibility of carpal bone.
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = left_fingers_map[i][1]
					bone_map_dict[skeleton.get_bone_name(search_path[2])] = left_fingers_map[i][2]
					named_finger_is_found = true;


			picklist.clear()
			search_path.clear()


		# It is a bit corner case, but possibly the finger names are sequentially numbered...
		if (!named_finger_is_found):
			picklist.push_back("finger")
			var finger_re = RegEx.new()
			finger_re.compile("finger")
			search_path = skeleton.get_bone_children(left_hand_or_palm)
			var finger_names: PackedStringArray
			for spath in search_path:
				var bn: String = skeleton.get_bone_name(spath)
				if finger_re.search(bn.to_lower()):
					finger_names.push_back(bn)
			finger_names.sort() # Order by lexicographic, normal use cases never have more than 10 fingers in one hand.
			search_path.clear()
			for i in range(len(finger_names)):
				if (i >= 5):
					break;

				var finger_root: int = skeleton.find_bone(finger_names[i])
				var finger: int = search_bone_by_name(skeleton, picklist, SEG_LEFT, finger_root, -1, 0)
				if (finger != -1):
					while (finger != finger_root && finger >= 0):
						search_path.push_back(finger)
						finger = skeleton.get_bone_parent(finger)


				search_path.push_back(finger_root)
				search_path.reverse()
				if (search_path.size() == 1):
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
				elif (search_path.size() == 2):
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = left_fingers_map[i][1]
				elif (search_path.size() >= 3):
					search_path = search_path.slice(-3) # Eliminate the possibility of carpal bone.
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = left_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = left_fingers_map[i][1]
					bone_map_dict[skeleton.get_bone_name(search_path[2])] = left_fingers_map[i][2]

				search_path.clear()

			picklist.clear()


	named_finger_is_found = false;
	if (right_hand_or_palm != -1):
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
			if (finger != -1):
				while (finger != right_hand_or_palm && finger >= 0):
					search_path.push_back(finger)
					finger = skeleton.get_bone_parent(finger)

				search_path.reverse()
				if (search_path.size() == 1):
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = right_fingers_map[i][0]
					named_finger_is_found = true;
				elif (search_path.size() == 2):
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = right_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = right_fingers_map[i][1]
					named_finger_is_found = true;
				elif (search_path.size() >= 3):
					search_path = search_path.slice(-3) # Eliminate the possibility of carpal bone.
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = right_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = right_fingers_map[i][1]
					bone_map_dict[skeleton.get_bone_name(search_path[2])] = right_fingers_map[i][2]
					named_finger_is_found = true;


			picklist.clear()
			search_path.clear()


		# It is a bit corner case, but possibly the finger names are sequentially numbered...
		if (!named_finger_is_found):
			picklist.push_back("finger")
			var finger_re = RegEx.new()
			finger_re.compile("finger")
			search_path = skeleton.get_bone_children(right_hand_or_palm)
			var finger_names: PackedStringArray
			for spath in search_path:
				var bn: String = skeleton.get_bone_name(spath)
				if finger_re.search(bn.to_lower()):
					finger_names.push_back(bn)


			finger_names.sort() # Order by lexicographic, normal use cases never have more than 10 fingers in one hand.
			search_path.clear()
			for i in range(len(finger_names)):
				if (i >= 5):
					break;

				var finger_root: int = skeleton.find_bone(finger_names[i])
				var finger: int = search_bone_by_name(skeleton, picklist, SEG_RIGHT, finger_root, -1, 0)
				if (finger != -1):
					while (finger != finger_root && finger >= 0):
						search_path.push_back(finger)
						finger = skeleton.get_bone_parent(finger)


				search_path.push_back(finger_root)
				search_path.reverse()
				if (search_path.size() == 1):
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = right_fingers_map[i][0]
				elif (search_path.size() == 2):
					bone_map_dict[skeleton.get_bone_name(search_path[0])] = right_fingers_map[i][0]
					bone_map_dict[skeleton.get_bone_name(search_path[1])] = right_fingers_map[i][1]
				elif (search_path.size() >= 3):
					search_path = search_path.slice(-3) # Eliminate the possibility of carpal bone.
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
	if (left_shoulder == -1):
		print("Auto Mapping couldn't guess LeftShoulder.")
	else:
		bone_map_dict[skeleton.get_bone_name(left_shoulder)] = "LeftShoulder"

	var right_shoulder: int = search_bone_by_name(skeleton, picklist, SEG_RIGHT, hips)
	if (right_shoulder == -1):
		print("Auto Mapping couldn't guess RightShoulder.")
	else:
		bone_map_dict[skeleton.get_bone_name(right_shoulder)] = "RightShoulder"

	picklist.clear()

	# 7-1. Guess LowerArms
	picklist.push_back("(low|fore).*arm")
	picklist.push_back("elbow")
	picklist.push_back("arm")
	var left_lower_arm: int = -1
	if (left_shoulder != -1 && left_hand_or_palm != -1):
		left_lower_arm = search_bone_by_name(skeleton, picklist, SEG_LEFT, left_shoulder, left_hand_or_palm)

	if (left_lower_arm == -1):
		print("Auto Mapping couldn't guess LeftLowerArm.")
	else:
		bone_map_dict[skeleton.get_bone_name(left_lower_arm)] = "LeftLowerArm"

	var right_lower_arm: int = -1
	if (right_shoulder != -1 && right_hand_or_palm != -1):
		right_lower_arm = search_bone_by_name(skeleton, picklist, SEG_RIGHT, right_shoulder, right_hand_or_palm)

	if (right_lower_arm == -1):
		print("Auto Mapping couldn't guess RightLowerArm.")
	else:
		bone_map_dict[skeleton.get_bone_name(right_lower_arm)] = "RightLowerArm"

	picklist.clear()

	# 7-2. Guess UpperArms
	picklist.push_back("up.*arm")
	picklist.push_back("arm")
	if (left_shoulder != -1 && left_lower_arm != -1):
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_LEFT, left_shoulder, left_lower_arm)

	if (bone_idx == -1):
		print("Auto Mapping couldn't guess LeftUpperArm.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "LeftUpperArm"

	bone_idx = -1;
	if (right_shoulder != -1 && right_lower_arm != -1):
		bone_idx = search_bone_by_name(skeleton, picklist, SEG_RIGHT, right_shoulder, right_lower_arm)

	if (bone_idx == -1):
		print("Auto Mapping couldn't guess RightUpperArm.")
	else:
		bone_map_dict[skeleton.get_bone_name(bone_idx)] = "RightUpperArm"

	bone_idx = -1;
	picklist.clear()

	# 8. Guess UpperChest or Chest
	if (neck_or_head == -1):
		print("Auto Mapping couldn't guess Neck or Head! Abort auto mapping.")
		return {} # Abort.

	var chest_or_upper_chest: int = skeleton.get_bone_parent(neck_or_head)
	var is_appropriate: bool = true;
	if left_shoulder != -1:
		bone_idx = skeleton.get_bone_parent(left_shoulder)
		var detect: bool = false
		while bone_idx != hips && bone_idx >= 0:
			if (bone_idx == chest_or_upper_chest):
				detect = true;
				break;

			bone_idx = skeleton.get_bone_parent(bone_idx)

		if (!detect):
			is_appropriate = false;

		bone_idx = -1;

	if right_shoulder != -1:
		bone_idx = skeleton.get_bone_parent(right_shoulder)
		var detect: bool = false;
		while bone_idx != hips && bone_idx >= 0:
			if (bone_idx == chest_or_upper_chest):
				detect = true
				break;

			bone_idx = skeleton.get_bone_parent(bone_idx)

		if (!detect):
			is_appropriate = false;

		bone_idx = -1;

	if (!is_appropriate):
		if (skeleton.get_bone_parent(left_shoulder) == skeleton.get_bone_parent(right_shoulder)):
			chest_or_upper_chest = skeleton.get_bone_parent(left_shoulder)
		else:
			chest_or_upper_chest = -1;


	if (chest_or_upper_chest == -1):
		print("Auto Mapping couldn't guess Chest or UpperChest. Abort auto mapping.")
		return {} # Will be not able to guess Spines.


	# 9. Guess Spines
	bone_idx = skeleton.get_bone_parent(chest_or_upper_chest)
	while (bone_idx != hips && bone_idx >= 0):
		search_path.push_back(bone_idx)
		bone_idx = skeleton.get_bone_parent(bone_idx)

	search_path.reverse()
	if (search_path.size() == 0):
		bone_map_dict[skeleton.get_bone_name(chest_or_upper_chest)] = "Spine" # Maybe chibi model...?
	elif (search_path.size() == 1):
		bone_map_dict[skeleton.get_bone_name(search_path[0])] = "Spine"
		bone_map_dict[skeleton.get_bone_name(chest_or_upper_chest)] = "Chest"
	elif (search_path.size() >= 2):
		bone_map_dict[skeleton.get_bone_name(search_path[0])] = "Spine"
		bone_map_dict[skeleton.get_bone_name(search_path[search_path.size() - 1])] = "Chest" # Probably UppeChest's parent is appropriate.
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
