# -!- coding: utf-8 -!-
#
# Copyright 2022-2023 lox9973
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#	 http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
extends RefCounted

enum HumanBodyBones {
	Hips = 0,
	LeftUpperLeg = 1,
	RightUpperLeg = 2,
	LeftLowerLeg = 3,
	RightLowerLeg = 4,
	LeftFoot = 5,
	RightFoot = 6,
	Spine = 7,
	Chest = 8,
	UpperChest = 54,
	Neck = 9,
	Head = 10,
	LeftShoulder = 11,
	RightShoulder = 12,
	LeftUpperArm = 13,
	RightUpperArm = 14,
	LeftLowerArm = 15,
	RightLowerArm = 16,
	LeftHand = 17,
	RightHand = 18,
	LeftToes = 19,
	RightToes = 20,
	LeftEye = 21,
	RightEye = 22,
	Jaw = 23,
	LeftThumbProximal = 24,
	LeftThumbIntermediate = 25,
	LeftThumbDistal = 26,
	LeftIndexProximal = 27,
	LeftIndexIntermediate = 28,
	LeftIndexDistal = 29,
	LeftMiddleProximal = 30,
	LeftMiddleIntermediate = 31,
	LeftMiddleDistal = 32,
	LeftRingProximal = 33,
	LeftRingIntermediate = 34,
	LeftRingDistal = 35,
	LeftLittleProximal = 36,
	LeftLittleIntermediate = 37,
	LeftLittleDistal = 38,
	RightThumbProximal = 39,
	RightThumbIntermediate = 40,
	RightThumbDistal = 41,
	RightIndexProximal = 42,
	RightIndexIntermediate = 43,
	RightIndexDistal = 44,
	RightMiddleProximal = 45,
	RightMiddleIntermediate = 46,
	RightMiddleDistal = 47,
	RightRingProximal = 48,
	RightRingIntermediate = 49,
	RightRingDistal = 50,
	RightLittleProximal = 51,
	RightLittleIntermediate = 52,
	RightLittleDistal = 53,
}

const GodotHumanNames : Array[String] = [
	"Hips",
	"LeftUpperLeg", "RightUpperLeg",
	"LeftLowerLeg", "RightLowerLeg",
	"LeftFoot", "RightFoot",
	"Spine",
	"Chest",
	"Neck",
	"Head",
	"LeftShoulder", "RightShoulder",
	"LeftUpperArm", "RightUpperArm",
	"LeftLowerArm", "RightLowerArm",
	"LeftHand", "RightHand",
	"LeftToes", "RightToes",
	"LeftEye", "RightEye",
	"Jaw",
	"LeftThumbMetacarpal", "LeftThumbProximal", "LeftThumbDistal",
	"LeftIndexProximal", "LeftIndexIntermediate", "LeftIndexDistal",
	"LeftMiddleProximal", "LeftMiddleIntermediate", "LeftMiddleDistal",
	"LeftRingProximal", "LeftRingIntermediate", "LeftRingDistal",
	"LeftLittleProximal", "LeftLittleIntermediate", "LeftLittleDistal",
	"RightThumbMetacarpal", "RightThumbProximal", "RightThumbDistal",
	"RightIndexProximal", "RightIndexIntermediate", "RightIndexDistal",
	"RightMiddleProximal", "RightMiddleIntermediate", "RightMiddleDistal",
	"RightRingProximal", "RightRingIntermediate", "RightRingDistal",
	"RightLittleProximal", "RightLittleIntermediate", "RightLittleDistal",
	"UpperChest",
]

const BoneName : Array[String] = [
	"Hips",
	"LeftUpperLeg", "RightUpperLeg",
	"LeftLowerLeg", "RightLowerLeg",
	"LeftFoot", "RightFoot",
	"Spine",
	"Chest",
	"Neck",
	"Head",
	"LeftShoulder", "RightShoulder",
	"LeftUpperArm", "RightUpperArm",
	"LeftLowerArm", "RightLowerArm",
	"LeftHand", "RightHand",
	"LeftToes", "RightToes",
	"LeftEye", "RightEye",
	"Jaw",
	"Left Thumb Proximal", "Left Thumb Intermediate", "Left Thumb Distal",
	"Left Index Proximal", "Left Index Intermediate", "Left Index Distal",
	"Left Middle Proximal", "Left Middle Intermediate", "Left Middle Distal",
	"Left Ring Proximal", "Left Ring Intermediate", "Left Ring Distal",
	"Left Little Proximal", "Left Little Intermediate", "Left Little Distal",
	"Right Thumb Proximal", "Right Thumb Intermediate", "Right Thumb Distal",
	"Right Index Proximal", "Right Index Intermediate", "Right Index Distal",
	"Right Middle Proximal", "Right Middle Intermediate", "Right Middle Distal",
	"Right Ring Proximal", "Right Ring Intermediate", "Right Ring Distal",
	"Right Little Proximal", "Right Little Intermediate", "Right Little Distal",
	"UpperChest",
]

const MuscleName : Array[String] = [
	"Spine Front-Back", "Spine Left-Right", "Spine Twist Left-Right",
	"Chest Front-Back", "Chest Left-Right", "Chest Twist Left-Right",
	"UpperChest Front-Back", "UpperChest Left-Right", "UpperChest Twist Left-Right",
	"Neck Nod Down-Up", "Neck Tilt Left-Right", "Neck Turn Left-Right",
	"Head Nod Down-Up", "Head Tilt Left-Right", "Head Turn Left-Right",
	"Left Eye Down-Up", "Left Eye In-Out",
	"Right Eye Down-Up", "Right Eye In-Out",
	"Jaw Close", "Jaw Left-Right",
	"Left Upper Leg Front-Back", "Left Upper Leg In-Out", "Left Upper Leg Twist In-Out",
	"Left Lower Leg Stretch", "Left Lower Leg Twist In-Out",
	"Left Foot Up-Down", "Left Foot Twist In-Out", "Left Toes Up-Down",
	"Right Upper Leg Front-Back", "Right Upper Leg In-Out", "Right Upper Leg Twist In-Out",
	"Right Lower Leg Stretch", "Right Lower Leg Twist In-Out",
	"Right Foot Up-Down", "Right Foot Twist In-Out", "Right Toes Up-Down",
	"Left Shoulder Down-Up", "Left Shoulder Front-Back", "Left Arm Down-Up",
	"Left Arm Front-Back", "Left Arm Twist In-Out",
	"Left Forearm Stretch", "Left Forearm Twist In-Out",
	"Left Hand Down-Up", "Left Hand In-Out",
	"Right Shoulder Down-Up", "Right Shoulder Front-Back", "Right Arm Down-Up",
	"Right Arm Front-Back", "Right Arm Twist In-Out",
	"Right Forearm Stretch", "Right Forearm Twist In-Out",
	"Right Hand Down-Up", "Right Hand In-Out",
	"LeftHand.Thumb.1 Stretched", "LeftHand.Thumb.Spread", "LeftHand.Thumb.2 Stretched", "LeftHand.Thumb.3 Stretched",
	"LeftHand.Index.1 Stretched", "LeftHand.Index.Spread", "LeftHand.Index.2 Stretched", "LeftHand.Index.3 Stretched",
	"LeftHand.Middle.1 Stretched", "LeftHand.Middle.Spread", "LeftHand.Middle.2 Stretched", "LeftHand.Middle.3 Stretched",
	"LeftHand.Ring.1 Stretched", "LeftHand.Ring.Spread", "LeftHand.Ring.2 Stretched", "LeftHand.Ring.3 Stretched",
	"LeftHand.Little.1 Stretched", "LeftHand.Little.Spread", "LeftHand.Little.2 Stretched", "LeftHand.Little.3 Stretched",
	"RightHand.Thumb.1 Stretched", "RightHand.Thumb.Spread", "RightHand.Thumb.2 Stretched", "RightHand.Thumb.3 Stretched",
	"RightHand.Index.1 Stretched", "RightHand.Index.Spread", "RightHand.Index.2 Stretched", "RightHand.Index.3 Stretched",
	"RightHand.Middle.1 Stretched", "RightHand.Middle.Spread", "RightHand.Middle.2 Stretched", "RightHand.Middle.3 Stretched",
	"RightHand.Ring.1 Stretched", "RightHand.Ring.Spread", "RightHand.Ring.2 Stretched", "RightHand.Ring.3 Stretched",
	"RightHand.Little.1 Stretched", "RightHand.Little.Spread", "RightHand.Little.2 Stretched", "RightHand.Little.3 Stretched"
]

const TraitMapping : Dictionary = {
	"Left Thumb 1 Stretched": "LeftHand.Thumb.1 Stretched",
	"Left Thumb Spread": "LeftHand.Thumb.Spread",
	"Left Thumb 2 Stretched": "LeftHand.Thumb.2 Stretched",
	"Left Thumb 3 Stretched": "LeftHand.Thumb.3 Stretched",
	"Left Index 1 Stretched": "LeftHand.Index.1 Stretched",
	"Left Index Spread": "LeftHand.Index.Spread",
	"Left Index 2 Stretched": "LeftHand.Index.2 Stretched",
	"Left Index 3 Stretched": "LeftHand.Index.3 Stretched",
	"Left Middle 1 Stretched": "LeftHand.Middle.1 Stretched",
	"Left Middle Spread": "LeftHand.Middle.Spread",
	"Left Middle 2 Stretched": "LeftHand.Middle.2 Stretched",
	"Left Middle 3 Stretched": "LeftHand.Middle.3 Stretched",
	"Left Ring 1 Stretched": "LeftHand.Ring.1 Stretched",
	"Left Ring Spread": "LeftHand.Ring.Spread",
	"Left Ring 2 Stretched": "LeftHand.Ring.2 Stretched",
	"Left Ring 3 Stretched": "LeftHand.Ring.3 Stretched",
	"Left Little 1 Stretched": "LeftHand.Little.1 Stretched",
	"Left Little Spread": "LeftHand.Little.Spread",
	"Left Little 2 Stretched": "LeftHand.Little.2 Stretched",
	"Left Little 3 Stretched": "LeftHand.Little.3 Stretched",
	"Right Thumb 1 Stretched": "RightHand.Thumb.1 Stretched",
	"Right Thumb Spread": "RightHand.Thumb.Spread",
	"Right Thumb 2 Stretched": "RightHand.Thumb.2 Stretched",
	"Right Thumb 3 Stretched": "RightHand.Thumb.3 Stretched",
	"Right Index 1 Stretched": "RightHand.Index.1 Stretched",
	"Right Index Spread": "RightHand.Index.Spread",
	"Right Index 2 Stretched": "RightHand.Index.2 Stretched",
	"Right Index 3 Stretched": "RightHand.Index.3 Stretched",
	"Right Middle 1 Stretched": "RightHand.Middle.1 Stretched",
	"Right Middle Spread": "RightHand.Middle.Spread",
	"Right Middle 2 Stretched": "RightHand.Middle.2 Stretched",
	"Right Middle 3 Stretched": "RightHand.Middle.3 Stretched",
	"Right Ring 1 Stretched": "RightHand.Ring.1 Stretched",
	"Right Ring Spread": "RightHand.Ring.Spread",
	"Right Ring 2 Stretched": "RightHand.Ring.2 Stretched",
	"Right Ring 3 Stretched": "RightHand.Ring.3 Stretched",
	"Right Little 1 Stretched": "RightHand.Little.1 Stretched",
	"Right Little Spread": "RightHand.Little.Spread",
	"Right Little 2 Stretched": "RightHand.Little.2 Stretched",
	"Right Little 3 Stretched": "RightHand.Little.3 Stretched",
}

const IKPrefixNames : Array[String] = ["Root", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]
const IKSuffixNames : Dictionary = {"T.x": 0, "T.y": 1, "T.z": 2, "Q.x": 0, "Q.y": 1, "Q.z": 2, "Q.w": 3}

const BoneCount := len(BoneName)
const MuscleCount := len(MuscleName)

const MuscleFromBone : Array[Array] = [
	[-1,-1,-1],
	[23,22,21], [31,30,29],
	[25,-1,24], [33,-1,32],
	[-1,27,26], [-1,35,34],
	[2,1,0],
	[5,4,3],
	[11,10,9],
	[14,13,12],
	[-1,38,37], [-1,47,46],
	[41,40,39], [50,49,48],
	[43,-1,42], [52,-1,51],
	[-1,45,44], [-1,54,53],
	[-1,-1,28], [-1,-1,36],
	[-1,16,15], [-1,18,17],
	[-1,20,19],
	[-1,56,55], [-1,-1,57], [-1,-1,58],
	[-1,60,59], [-1,-1,61], [-1,-1,62],
	[-1,64,63], [-1,-1,65], [-1,-1,66],
	[-1,68,67], [-1,-1,69], [-1,-1,70],
	[-1,72,71], [-1,-1,73], [-1,-1,74],
	[-1,76,75], [-1,-1,77], [-1,-1,78],
	[-1,80,79], [-1,-1,81], [-1,-1,82],
	[-1,84,83], [-1,-1,85], [-1,-1,86],
	[-1,88,87], [-1,-1,89], [-1,-1,90],
	[-1,92,91], [-1,-1,93], [-1,-1,94],
	[8,7,6],
]

const MuscleDefaultMax : Array[float] = [ # HumanTrait.GetMuscleDefaultMax
	40, 40, 40, 40, 40, 40, 20, 20, 20, 40, 40, 40, 40, 40, 40,
	15, 20, 15, 20, 10, 10,
	50, 60, 60, 80, 90, 50, 30, 50,
	50, 60, 60, 80, 90, 50, 30, 50,
	30, 15, 100, 100, 90, 80, 90, 80, 40,
	30, 15, 100, 100, 90, 80, 90, 80, 40,
	20, 25, 35, 35, 50, 20, 45, 45, 50, 7.5, 45, 45, 50, 7.5, 45, 45, 50, 20, 45, 45,
	20, 25, 35, 35, 50, 20, 45, 45, 50, 7.5, 45, 45, 50, 7.5, 45, 45, 50, 20, 45, 45,
]

const MuscleDefaultMin : Array[float] = [ # HumanTrait.GetMuscleDefaultMin
	-40,-40,-40,-40,-40,-40,-20,-20,-20,-40,-40,-40,-40,-40,-40,
	-10,-20,-10,-20,-10,-10,
	-90,-60,-60,-80,-90,-50,-30,-50,
	-90,-60,-60,-80,-90,-50,-30,-50,
	-15,-15,-60,-100,-90,-80,-90,-80,-40,
	-15,-15,-60,-100,-90,-80,-90,-80,-40,
	-20,-25,-40,-40,-50,-20,-45,-45,-50,-7.5,-45,-45,-50,-7.5,-45,-45,-50,-20,-45,-45,
	-20,-25,-40,-40,-50,-20,-45,-45,-50,-7.5,-45,-45,-50,-7.5,-45,-45,-50,-20,-45,-45,
]

const HumanParents: Array[int] = [
	-1,  0,  0,  1,  2,  3,  4,  0,  7, 54,  9, 54, 54, 11, 12, 13, 14, 15, 16,  5, 
	 6, 10, 10, 10, 17, 24, 25, 17, 27, 28, 17, 30, 31, 17, 33, 34, 17, 36, 37, 18, 
	39, 40, 18, 42, 43, 18, 45, 46, 18, 48, 49, 18, 51, 52,  8,
];

# Right-handed PreQ values for Godot's standard humanoid rig.
const preQ_exported: Array[Quaternion] = [
	Quaternion(0, 0, 0, 1), # Hips
	Quaternion(-0.62644, -0.34855, 0.59144, 0.36918), # LeftUpperLeg
	Quaternion(-0.59144, -0.36918, 0.62644, 0.34855), # RightUpperLeg
	Quaternion(-0.69691, 0.04422, -0.7145, 0.04313), # LeftLowerLeg
	Quaternion(-0.7145, 0.04313, -0.69691, 0.04422), # RightLowerLeg
	Quaternion(0.5, -0.5, -0.5, 0.5), # LeftFoot
	Quaternion(0.5, -0.5, -0.5, 0.5), # RightFoot
	Quaternion(0.46815, -0.52994, 0.46815, -0.52994), # Spine
	Quaternion(0.52661, -0.47189, 0.52661, -0.47189), # Chest
	Quaternion(0.46642, -0.5316, 0.46748, -0.5304), # Neck
	Quaternion(-0.5, 0.5, -0.5, 0.5), # Head
	Quaternion(0.03047, -0.00261, -0.9959, -0.08517), # LeftShoulder
	Quaternion(-0.00261, 0.03047, 0.08518, 0.9959), # RightShoulder
	Quaternion(0.505665, -0.400775, 0.749395, -0.148645), # LeftUpperArm
	Quaternion(-0.400775, 0.505665, 0.148645, -0.749395), # RightUpperArm
	Quaternion(-0.998935, 0.046125, 0.001085, 0.000045), # LeftLowerArm
	Quaternion(-0.04613, 0.99894, 0.00005, 0.00108), # RightLowerArm
	Quaternion(-0.02914, -0.029083, 0.707276, -0.705735), # LeftHand
	Quaternion(0.029083, 0.02914, -0.705735, 0.707276), # RightHand
	Quaternion(-0.500002, 0.500002, -0.500002, 0.500002), # LeftToes
	Quaternion(-0.500002, 0.500002, -0.500002, 0.500002), # RightToes
	Quaternion(0.70711, 0, -0.70711, 0), # LeftEye
	Quaternion(0.70711, 0, -0.70711, 0), # RightEye
	Quaternion(0, 0, 0, 1), # Jaw
	Quaternion(-0.957335, 0.251575, 0.073965, 0.121475), # LeftThumbMetacarpal
	Quaternion(-0.435979, 0.550073, -0.413528, 0.579935), # LeftThumbProximal
	Quaternion(-0.435979, 0.550073, -0.413528, 0.579935), # LeftThumbDistal
	Quaternion(-0.70292, 0.26496, 0.53029, -0.39305), # LeftIndexProximal
	Quaternion(-0.67155, 0.2898, 0.5998, -0.32447), # LeftIndexIntermediate
	Quaternion(-0.67155, 0.2898, 0.5998, -0.32447), # LeftIndexDistal
	Quaternion(-0.66667, 0.29261, 0.5877, -0.3529), # LeftMiddleProximal
	Quaternion(-0.660575, 0.278445, 0.633985, -0.290115), # LeftMiddleIntermediate
	Quaternion(-0.660575, 0.278445, 0.633985, -0.290115), # LeftMiddleDistal
	Quaternion(-0.60736, 0.34862, 0.64221, -0.31169), # LeftRingProximal
	Quaternion(-0.629695, 0.327165, 0.621835, -0.331305), # LeftRingIntermediate
	Quaternion(-0.629695, 0.327165, 0.621835, -0.331305), # LeftRingDistal
	Quaternion(-0.584415, 0.369825, 0.660045, -0.293315), # LeftLittleProximal
	Quaternion(-0.608895, 0.338425, 0.641505, -0.321215), # LeftLittleIntermediate
	Quaternion(-0.608895, 0.338425, 0.641505, -0.321215), # LeftLittleDistal
	Quaternion(0.251455, -0.957385, -0.121415, -0.073715), # RightThumbMetacarpal
	Quaternion(0.550156, -0.435959, -0.579765, 0.413695), # RightThumbProximal
	Quaternion(0.550156, -0.435959, -0.579765, 0.413695), # RightThumbDistal
	Quaternion(0.264955, -0.702925, 0.393045, -0.530295), # RightIndexProximal
	Quaternion(0.289805, -0.671545, 0.324465, -0.599805), # RightIndexIntermediate
	Quaternion(0.289805, -0.671545, 0.324465, -0.599805), # RightIndexDistal
	Quaternion(0.292615, -0.666665, 0.352895, -0.587705), # RightMiddleProximal
	Quaternion(0.278455, -0.660575, 0.290125, -0.633985), # RightMiddleIntermediate
	Quaternion(0.278455, -0.660575, 0.290125, -0.633985), # RightMiddleDistal
	Quaternion(0.34862, -0.60736, 0.31169, -0.64221), # RightRingProximal
	Quaternion(0.327165, -0.629695, 0.331295, -0.621845), # RightRingIntermediate
	Quaternion(0.327165, -0.629695, 0.331295, -0.621845), # RightRingDistal
	Quaternion(0.36982, -0.58442, 0.29332, -0.66004), # RightLittleProximal
	Quaternion(0.33843, -0.6089, 0.32123, -0.6415), # RightLittleIntermediate
	Quaternion(0.33843, -0.6089, 0.32123, -0.6415), # RightLittleDistal
	Quaternion(0.56563, -0.42434, 0.56563, -0.42434), # UpperChest
]

# Right-handed PostQ values for Godot's standard humanoid rig.
const postQ_inverse_exported: Array[Quaternion] = [
	Quaternion(0, 0, 0, 1), # Hips
	Quaternion(0.48977, -0.50952, 0.51876, 0.48105), # LeftUpperLeg
	Quaternion(0.51876, -0.48105, 0.48977, 0.50952), # RightUpperLeg
	Quaternion(-0.51894, 0.48097, 0.50616, 0.49312), # LeftLowerLeg
	Quaternion(-0.50616, 0.49312, 0.51894, 0.48097), # RightLowerLeg
	Quaternion(-0.707107, 0, -0.707107, 0), # LeftFoot
	Quaternion(-0.707107, 0, -0.707107, 0), # RightFoot
	Quaternion(-0.46815, 0.52994, -0.46815, -0.52994), # Spine
	Quaternion(-0.52661, 0.47189, -0.52661, -0.47189), # Chest
	Quaternion(-0.46642, 0.5316, -0.46748, -0.5304), # Neck
	Quaternion(0.5, -0.5, 0.5, 0.5), # Head
	Quaternion(-0.523995, 0.469295, -0.557075, -0.441435), # LeftShoulder
	Quaternion(0.46929, -0.524, -0.44143, -0.55708), # RightShoulder
	Quaternion(0.513635, -0.486185, -0.509345, -0.490275), # LeftUpperArm
	Quaternion(0.486185, -0.513635, 0.490275, 0.509345), # RightUpperArm
	Quaternion(0.519596, -0.479517, -0.520728, -0.478471), # LeftLowerArm
	Quaternion(0.479517, -0.519596, 0.478471, 0.520728), # RightLowerArm
	Quaternion(0.520725, -0.478465, -0.479515, -0.519595), # LeftHand
	Quaternion(0.478465, -0.520725, 0.519595, 0.479515), # RightHand
	Quaternion(-0.500002, 0.500002, 0.500002, 0.500002), # LeftToes
	Quaternion(-0.500002, 0.500002, 0.500002, 0.500002), # RightToes
	Quaternion(-0.500002, 0.500002, 0.500002, 0.500002), # LeftEye
	Quaternion(-0.500002, 0.500002, 0.500002, 0.500002), # RightEye
	Quaternion(0, 0.707107, 0.707107, 0), # Jaw
	Quaternion(0.56005, -0.437881, 0.528429, 0.464077), # LeftThumbMetacarpal
	Quaternion(0.541247, -0.458295, 0.513379, 0.483179), # LeftThumbProximal
	Quaternion(0.541247, -0.458295, 0.513379, 0.483179), # LeftThumbDistal
	Quaternion(0.53845, -0.45868, -0.46056, -0.53625), # LeftIndexProximal
	Quaternion(0.53604, -0.46316, -0.47877, -0.51857), # LeftIndexIntermediate
	Quaternion(0.53604, -0.46316, -0.47877, -0.51857), # LeftIndexDistal
	Quaternion(0.52555, -0.47434, -0.492, -0.50669), # LeftMiddleProximal
	Quaternion(0.536385, -0.463085, -0.514795, -0.482515), # LeftMiddleIntermediate
	Quaternion(0.536385, -0.463085, -0.514795, -0.482515), # LeftMiddleDistal
	Quaternion(0.50517, -0.49482, -0.50264, -0.49731), # LeftRingProximal
	Quaternion(0.494155, -0.505555, -0.487985, -0.511945), # LeftRingIntermediate
	Quaternion(0.494155, -0.505555, -0.487985, -0.511945), # LeftRingDistal
	Quaternion(0.502345, -0.497645, -0.501995, -0.497995), # LeftLittleProximal
	Quaternion(0.47756, -0.52241, -0.50314, -0.49585), # LeftLittleIntermediate
	Quaternion(0.47756, -0.52241, -0.50314, -0.49585), # LeftLittleDistal
	Quaternion(0.437905, -0.559994, -0.463881, -0.528644), # RightThumbMetacarpal
	Quaternion(0.458337, -0.5412, -0.483, -0.513558), # RightThumbProximal
	Quaternion(0.458337, -0.5412, -0.483, -0.513558), # RightThumbDistal
	Quaternion(0.45868, -0.53845, 0.53625, 0.46056), # RightIndexProximal
	Quaternion(0.463165, -0.536035, 0.518565, 0.478775), # RightIndexIntermediate
	Quaternion(0.463165, -0.536035, 0.518565, 0.478775), # RightIndexDistal
	Quaternion(0.47434, -0.52555, 0.50669, 0.492), # RightMiddleProximal
	Quaternion(0.4631, -0.53638, 0.48252, 0.5148), # RightMiddleIntermediate
	Quaternion(0.4631, -0.53638, 0.48252, 0.5148), # RightMiddleDistal
	Quaternion(0.49482, -0.50517, 0.49731, 0.50264), # RightRingProximal
	Quaternion(0.505555, -0.494155, 0.511935, 0.487995), # RightRingIntermediate
	Quaternion(0.505555, -0.494155, 0.511935, 0.487995), # RightRingDistal
	Quaternion(0.49764, -0.50235, 0.498, 0.50199), # RightLittleProximal
	Quaternion(0.52241, -0.47756, 0.49586, 0.50313), # RightLittleIntermediate
	Quaternion(0.52241, -0.47756, 0.49586, 0.50313), # RightLittleDistal
	Quaternion(-0.56563, 0.42434, -0.56563, -0.42434), # UpperChest
]

const sgn: Array[Vector3] = [
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,-1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(-1,-1,1),
	Vector3(-1,1,-1),
	Vector3(1,-1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,-1),
	Vector3(1,1,-1),
	Vector3(1,1,-1),
	Vector3(1,1,-1),
	Vector3(-1,-1,-1),
	Vector3(-1,1,-1),
	Vector3(-1,1,-1),
	Vector3(-1,1,-1),
	Vector3(-1,1,-1),
	Vector3(-1,1,-1),
	Vector3(-1,-1,-1),
	Vector3(-1,1,-1),
	Vector3(-1,1,-1),
	Vector3(-1,1,-1),
	Vector3(-1,1,-1),
	Vector3(-1,1,-1),
	Vector3(-1,-1,1),
	Vector3(-1,1,1),
	Vector3(-1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,-1),
	Vector3(1,1,-1),
	Vector3(1,-1,-1),
	Vector3(1,1,1),
	Vector3(-1,1,1),
	Vector3(-1,1,1),
	Vector3(1,1,1),
	Vector3(1,-1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,-1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,1,1),
	Vector3(1,-1,-1),
	Vector3(1,1,-1),
	Vector3(1,1,-1),
]

# Reference t-pose PreQ with all bones Y-up (identity quaternion)
# CAUTION: These are **left handed**
const PreQ_VRM_Tpose : Array[Quaternion] = [
	Quaternion(+0.00000,+0.00000,+0.00000,+1.00000), # Hips
	Quaternion(-0.62644,+0.34855,-0.59144,+0.36918), # LeftUpperLeg
	Quaternion(-0.59144,+0.36918,-0.62644,+0.34855), # RightUpperLeg
	Quaternion(-0.04422,+0.69691,-0.04313,+0.71450), # LeftLowerLeg
	Quaternion(-0.04313,+0.71450,-0.04422,+0.69691), # RightLowerLeg
	Quaternion(-0.50000,+0.50000,-0.50000,+0.50000), # LeftFoot
	Quaternion(-0.50000,+0.50000,-0.50000,+0.50000), # RightFoot
	Quaternion(+0.46815,+0.52994,-0.46815,-0.52994), # Spine
	Quaternion(+0.52661,+0.47189,-0.52661,-0.47189), # Chest
	Quaternion(+0.46642,+0.53160,-0.46748,-0.53040), # Neck
	Quaternion(-0.50000,-0.50000,+0.50000,+0.50000), # Head
	Quaternion(+0.03047,+0.00261,+0.99590,-0.08517), # LeftShoulder
	Quaternion(-0.00261,-0.03047,-0.08518,+0.99590), # RightShoulder
	Quaternion(+0.24793,-0.00420,+0.90224,-0.35282), # LeftUpperArm
	Quaternion(+0.00420,-0.24793,-0.35282,+0.90224), # RightUpperArm
	Quaternion(+0.47584,+0.52201,+0.52305,-0.47697), # LeftLowerArm
	Quaternion(-0.52202,-0.47584,-0.47697,+0.52305), # RightLowerArm
	Quaternion(+0.04117,+0.00004,+0.99915,-0.00109), # LeftHand
	Quaternion(-0.00004,-0.04117,-0.00109,+0.99915), # RightHand
	Quaternion(+0.70711,+0.00000,+0.70711,+0.00000), # LeftToes
	Quaternion(+0.70711,+0.00000,+0.70711,+0.00000), # RightToes
	Quaternion(+0.70711,+0.00000,+0.70711,+0.00000), # LeftEye
	Quaternion(+0.70711,+0.00000,+0.70711,+0.00000), # RightEye
	Quaternion(0,0,0,1), # Jaw
	Quaternion(+0.25516,+0.62821,+0.58070,-0.45060), # LeftThumbProximal
	Quaternion(+0.09906,+0.69392,+0.70013,-0.13590), # LeftThumbIntermediate
	Quaternion(+0.09906,+0.69392,+0.70013,-0.13590), # LeftThumbDistal
	Quaternion(+0.15036,+0.02227,+0.94561,-0.28760), # LeftIndexProximal
	Quaternion(+0.05321,+0.01854,+0.94281,-0.32854), # LeftIndexIntermediate
	Quaternion(+0.05321,+0.01854,+0.94281,-0.32854), # LeftIndexDistal
	Quaternion(+0.06963,+0.00934,+0.94994,-0.30443), # LeftMiddleProximal
	Quaternion(+0.01913,+0.00746,+0.93156,-0.36300), # LeftMiddleIntermediate
	Quaternion(+0.01913,+0.00746,+0.93156,-0.36300), # LeftMiddleDistal
	Quaternion(-0.03589,+0.00104,+0.95494,-0.29463), # LeftRingProximal
	Quaternion(+0.00600,+0.00186,+0.95500,-0.29653), # LeftRingIntermediate
	Quaternion(+0.00600,+0.00186,+0.95500,-0.29653), # LeftRingDistal
	Quaternion(-0.07607,+0.00044,+0.95380,-0.29066), # LeftLittleProximal
	Quaternion(-0.02491,-0.00770,+0.95502,-0.29538), # LeftLittleIntermediate
	Quaternion(-0.02491,-0.00770,+0.95502,-0.29538), # LeftLittleDistal
	Quaternion(+0.62827,+0.25540,+0.45053,-0.58057), # RightThumbProximal
	Quaternion(+0.69394,+0.09930,+0.13583,-0.70010), # RightThumbIntermediate
	Quaternion(+0.69394,+0.09930,+0.13583,-0.70010), # RightThumbDistal
	Quaternion(+0.02227,+0.15036,+0.28761,-0.94561), # RightIndexProximal
	Quaternion(+0.01854,+0.05320,+0.32854,-0.94281), # RightIndexIntermediate
	Quaternion(+0.01854,+0.05320,+0.32854,-0.94281), # RightIndexDistal
	Quaternion(+0.00934,+0.06962,+0.30443,-0.94994), # RightMiddleProximal
	Quaternion(+0.00746,+0.01913,+0.36299,-0.93157), # RightMiddleIntermediate
	Quaternion(+0.00746,+0.01913,+0.36299,-0.93157), # RightMiddleDistal
	Quaternion(+0.00104,-0.03589,+0.29463,-0.95494), # RightRingProximal
	Quaternion(+0.00186,+0.00599,+0.29654,-0.95500), # RightRingIntermediate
	Quaternion(+0.00186,+0.00599,+0.29654,-0.95500), # RightRingDistal
	Quaternion(+0.00044,-0.07606,+0.29066,-0.95380), # RightLittleProximal
	Quaternion(-0.00770,-0.02490,+0.29537,-0.95503), # RightLittleIntermediate
	Quaternion(-0.00770,-0.02490,+0.29537,-0.95503), # RightLittleDistal
	Quaternion(+0.56563,+0.42434,-0.56563,-0.42434), # UpperChest
]

# Reference t-pose PostQ with all bones Y-up (identity quaternion)
# CAUTION: These are **left handed**
const PostQ_VRM_Tpose: Array[Quaternion] = [
	Quaternion(+0.00000,+0.00000,+0.00000,+1.00000), # Hips
	Quaternion(-0.50952,+0.48977,-0.48105,+0.51876), # LeftUpperLeg
	Quaternion(-0.48105,+0.51876,-0.50952,+0.48977), # RightUpperLeg
	Quaternion(-0.49312,+0.50616,-0.48097,+0.51894), # LeftLowerLeg
	Quaternion(-0.48097,+0.51894,-0.49312,+0.50616), # RightLowerLeg
	Quaternion(-0.50000,+0.50000,-0.50000,+0.50000), # LeftFoot
	Quaternion(-0.50000,+0.50000,-0.50000,+0.50000), # RightFoot
	Quaternion(+0.46815,+0.52994,-0.46815,-0.52994), # Spine
	Quaternion(+0.52661,+0.47189,-0.52661,-0.47189), # Chest
	Quaternion(+0.46642,+0.53160,-0.46748,-0.53040), # Neck
	Quaternion(-0.50000,-0.50000,+0.50000,+0.50000), # Head
	Quaternion(+0.03047,+0.00261,+0.99590,-0.08517), # LeftShoulder
	Quaternion(-0.00261,-0.03047,-0.08518,+0.99590), # RightShoulder
	Quaternion(+0.00419,+0.00010,+0.99972,-0.02326), # LeftUpperArm
	Quaternion(-0.00010,-0.00419,-0.02326,+0.99972), # RightUpperArm
	Quaternion(+0.02834,+0.70648,+0.70654,-0.02988), # LeftLowerArm
	Quaternion(-0.70648,-0.02834,-0.02988,+0.70654), # RightLowerArm
	Quaternion(+0.04117,+0.00004,+0.99915,-0.00109), # LeftHand
	Quaternion(-0.00004,-0.04117,-0.00109,+0.99915), # RightHand
	Quaternion(+0.70711,+0.00000,+0.70711,+0.00000), # LeftToes
	Quaternion(+0.70711,+0.00000,+0.70711,+0.00000), # RightToes
	Quaternion(+0.70711,+0.00000,+0.70711,+0.00000), # LeftEye
	Quaternion(+0.70711,+0.00000,+0.70711,+0.00000), # RightEye
	Quaternion(0,0,0,1), # Jaw
	Quaternion(+0.25711,+0.64267,+0.65871,-0.29491), # LeftThumbProximal
	Quaternion(+0.23444,+0.65380,+0.66711,-0.26935), # LeftThumbIntermediate
	Quaternion(+0.23444,+0.65380,+0.66711,-0.26935), # LeftThumbDistal
	Quaternion(+0.07773,+0.00016,+0.99697,-0.00204), # LeftIndexProximal
	Quaternion(+0.05634,+0.00093,+0.99827,-0.01654), # LeftIndexIntermediate
	Quaternion(+0.05634,+0.00093,+0.99827,-0.01654), # LeftIndexDistal
	Quaternion(+0.03295,+0.00060,+0.99929,-0.01826), # LeftMiddleProximal
	Quaternion(+0.02051,+0.00108,+0.99839,-0.05279), # LeftMiddleIntermediate
	Quaternion(+0.02051,+0.00108,+0.99839,-0.05279), # LeftMiddleDistal
	Quaternion(+0.00251,+0.00002,+0.99997,-0.00784), # LeftRingProximal
	Quaternion(+0.00628,-0.00011,+0.99982,+0.01768), # LeftRingIntermediate
	Quaternion(+0.00628,-0.00011,+0.99982,+0.01768), # LeftRingDistal
	Quaternion(+0.00035,+0.00000,+0.99999,-0.00435), # LeftLittleProximal
	Quaternion(-0.02607,+0.00049,+0.99948,+0.01878), # LeftLittleIntermediate
	Quaternion(-0.02607,+0.00049,+0.99948,+0.01878), # LeftLittleDistal
	Quaternion(-0.64270,-0.25738,-0.29486,+0.65860), # RightThumbProximal
	Quaternion(-0.65382,-0.23468,-0.26929,+0.66703), # RightThumbIntermediate
	Quaternion(-0.65382,-0.23468,-0.26929,+0.66703), # RightThumbDistal
	Quaternion(-0.00016,-0.07773,-0.00204,+0.99697), # RightIndexProximal
	Quaternion(-0.00093,-0.05633,-0.01654,+0.99827), # RightIndexIntermediate
	Quaternion(-0.00093,-0.05633,-0.01654,+0.99827), # RightIndexDistal
	Quaternion(-0.00060,-0.03295,-0.01826,+0.99929), # RightMiddleProximal
	Quaternion(-0.00108,-0.02050,-0.05278,+0.99840), # RightMiddleIntermediate
	Quaternion(-0.00108,-0.02050,-0.05278,+0.99840), # RightMiddleDistal
	Quaternion(-0.00002,-0.00251,-0.00784,+0.99997), # RightRingProximal
	Quaternion(+0.00011,-0.00627,+0.01767,+0.99982), # RightRingIntermediate
	Quaternion(+0.00011,-0.00627,+0.01767,+0.99982), # RightRingDistal
	Quaternion(-0.00000,-0.00036,-0.00435,+0.99999), # RightLittleProximal
	Quaternion(-0.00049,+0.02606,+0.01879,+0.99948), # RightLittleIntermediate
	Quaternion(-0.00049,+0.02606,+0.01879,+0.99948), # RightLittleDistal
	Quaternion(+0.56563,+0.42434,-0.56563,-0.42434), # UpperChest
]

const Signs: Array[Vector3] = [
	Vector3(+1,+1,+1), # Hips
	Vector3(+1,+1,+1), # LeftUpperLeg
	Vector3(-1,-1,+1), # RightUpperLeg
	Vector3(+1,-1,-1), # LeftLowerLeg
	Vector3(-1,+1,-1), # RightLowerLeg
	Vector3(+1,+1,+1), # LeftFoot
	Vector3(-1,-1,+1), # RightFoot
	Vector3(+1,+1,+1), # Spine
	Vector3(+1,+1,+1), # Chest
	Vector3(+1,+1,+1), # Neck
	Vector3(+1,+1,+1), # Head
	Vector3(+1,+1,-1), # LeftShoulder
	Vector3(-1,+1,+1), # RightShoulder
	Vector3(+1,+1,-1), # LeftUpperArm
	Vector3(-1,+1,+1), # RightUpperArm
	Vector3(+1,+1,-1), # LeftLowerArm
	Vector3(-1,+1,+1), # RightLowerArm
	Vector3(+1,+1,-1), # LeftHand
	Vector3(-1,+1,+1), # RightHand
	Vector3(+1,+1,+1), # LeftToes
	Vector3(-1,-1,+1), # RightToes
	Vector3(-1,+1,-1), # LeftEye
	Vector3(+1,-1,-1), # RightEye
	Vector3(1,1,1), # Jaw
	Vector3(+1,-1,+1), # LeftThumbProximal
	Vector3(+1,-1,+1), # LeftThumbIntermediate
	Vector3(+1,-1,+1), # LeftThumbDistal
	Vector3(-1,-1,-1), # LeftIndexProximal
	Vector3(-1,-1,-1), # LeftIndexIntermediate
	Vector3(-1,-1,-1), # LeftIndexDistal
	Vector3(-1,-1,-1), # LeftMiddleProximal
	Vector3(-1,-1,-1), # LeftMiddleIntermediate
	Vector3(-1,-1,-1), # LeftMiddleDistal
	Vector3(+1,+1,-1), # LeftRingProximal
	Vector3(+1,+1,-1), # LeftRingIntermediate
	Vector3(+1,+1,-1), # LeftRingDistal
	Vector3(+1,+1,-1), # LeftLittleProximal
	Vector3(+1,+1,-1), # LeftLittleIntermediate
	Vector3(+1,+1,-1), # LeftLittleDistal
	Vector3(-1,-1,-1), # RightThumbProximal
	Vector3(-1,-1,-1), # RightThumbIntermediate
	Vector3(-1,-1,-1), # RightThumbDistal
	Vector3(+1,-1,+1), # RightIndexProximal
	Vector3(+1,-1,+1), # RightIndexIntermediate
	Vector3(+1,-1,+1), # RightIndexDistal
	Vector3(+1,-1,+1), # RightMiddleProximal
	Vector3(+1,-1,+1), # RightMiddleIntermediate
	Vector3(+1,-1,+1), # RightMiddleDistal
	Vector3(-1,+1,+1), # RightRingProximal
	Vector3(-1,+1,+1), # RightRingIntermediate
	Vector3(-1,+1,+1), # RightRingDistal
	Vector3(-1,+1,+1), # RightLittleProximal
	Vector3(-1,+1,+1), # RightLittleIntermediate
	Vector3(-1,+1,+1), # RightLittleDistal
	Vector3(+1,+1,+1), # UpperChest
]

# assert(len(BoneName) === len(MuscleFromBone))
# assert(len(MuscleName) === len(MuscleDefaultMax))
# assert(len(MuscleName) === len(MuscleDefaultMin))

const boneIndexToMono: Array[HumanBodyBones] = [ # HumanTrait.GetBoneIndexToMono (internal)
	HumanBodyBones.Hips,
	HumanBodyBones.LeftUpperLeg,
	HumanBodyBones.RightUpperLeg,
	HumanBodyBones.LeftLowerLeg,
	HumanBodyBones.RightLowerLeg,
	HumanBodyBones.LeftFoot,
	HumanBodyBones.RightFoot,
	HumanBodyBones.Spine,
	HumanBodyBones.Chest,
	HumanBodyBones.UpperChest,
	HumanBodyBones.Neck,
	HumanBodyBones.Head,
	HumanBodyBones.LeftShoulder,
	HumanBodyBones.RightShoulder,
	HumanBodyBones.LeftUpperArm,
	HumanBodyBones.RightUpperArm,
	HumanBodyBones.LeftLowerArm,
	HumanBodyBones.RightLowerArm,
	HumanBodyBones.LeftHand,
	HumanBodyBones.RightHand,
	HumanBodyBones.LeftToes,
	HumanBodyBones.RightToes,
	HumanBodyBones.LeftEye,
	HumanBodyBones.RightEye,
	HumanBodyBones.Jaw,
	HumanBodyBones.LeftThumbProximal,
	HumanBodyBones.LeftThumbIntermediate,
	HumanBodyBones.LeftThumbDistal,
	HumanBodyBones.LeftIndexProximal,
	HumanBodyBones.LeftIndexIntermediate,
	HumanBodyBones.LeftIndexDistal,
	HumanBodyBones.LeftMiddleProximal,
	HumanBodyBones.LeftMiddleIntermediate,
	HumanBodyBones.LeftMiddleDistal,
	HumanBodyBones.LeftRingProximal,
	HumanBodyBones.LeftRingIntermediate,
	HumanBodyBones.LeftRingDistal,
	HumanBodyBones.LeftLittleProximal,
	HumanBodyBones.LeftLittleIntermediate,
	HumanBodyBones.LeftLittleDistal,
	HumanBodyBones.RightThumbProximal,
	HumanBodyBones.RightThumbIntermediate,
	HumanBodyBones.RightThumbDistal,
	HumanBodyBones.RightIndexProximal,
	HumanBodyBones.RightIndexIntermediate,
	HumanBodyBones.RightIndexDistal,
	HumanBodyBones.RightMiddleProximal,
	HumanBodyBones.RightMiddleIntermediate,
	HumanBodyBones.RightMiddleDistal,
	HumanBodyBones.RightRingProximal,
	HumanBodyBones.RightRingIntermediate,
	HumanBodyBones.RightRingDistal,
	HumanBodyBones.RightLittleProximal,
	HumanBodyBones.RightLittleIntermediate,
	HumanBodyBones.RightLittleDistal,
]

static func bone_name_to_index() -> Dictionary: # String -> int
	var ret: Dictionary
	for idx in range(len(BoneName)):
		ret[BoneName[idx]] = idx
	return ret

static func muscle_name_to_index() -> Dictionary: # String -> int
	var ret: Dictionary
	for idx in range(len(MuscleName)):
		ret[MuscleName[idx]] = idx
	return ret

static func muscle_index_to_bone_and_axis() -> Array[Vector2i]: # String -> Vector2i
	var ret: Array[Vector2i]
	ret.resize(MuscleCount)
	for idx in range(len(MuscleFromBone)):
		for axis_i in range(3):
			var muscle_i : int = MuscleFromBone[idx][axis_i]
			if muscle_i != -1:
				ret[muscle_i] = Vector2i(idx, axis_i)
	return ret
	
