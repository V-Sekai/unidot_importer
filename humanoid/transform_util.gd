# -!- coding: utf-8 -!-
#
# Copyright 2023 V-Sekai contributors
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

const human_trait = preload("./human_trait.gd")

static func calculate_humanoid_rotation(bone_idx: int, muscle_triplet: Vector3, from_postq: bool = false) -> Quaternion:
	var muscle_from_bone: PackedInt32Array = human_trait.MuscleFromBone[bone_idx]

	for i in range(3):
		muscle_triplet[i] *= deg_to_rad(
			human_trait.MuscleDefaultMax[muscle_from_bone[i]] if muscle_triplet[i] >= 0
			else -human_trait.MuscleDefaultMin[muscle_from_bone[i]]) * human_trait.Signs[bone_idx][i]
	var preQ : Quaternion = human_trait.preQ_exported[bone_idx]
	if from_postq:
		preQ = human_trait.postQ_inverse_exported[bone_idx].inverse().normalized()
	if not preQ.is_normalized():
		push_error("preQ is not normalized " + str(bone_idx))
	var invPostQ : Quaternion = human_trait.postQ_inverse_exported[bone_idx]
	if not invPostQ.is_normalized():
		push_error("invPostQ is not normalized " + str(bone_idx))
	var swing_res := swing_twist(muscle_triplet.x, -muscle_triplet.y, -muscle_triplet.z)
	if not swing_res.is_normalized():
		push_error("swing_res is not normalized " + str(bone_idx) + " " + str(muscle_triplet))
	var ret: Quaternion = preQ * swing_res * invPostQ
	if not ret.is_normalized():
		push_error("ret is not normalized " + str(bone_idx) + " " + str(muscle_triplet) + " " + str(preQ) + "," + str(swing_res) + "," + str(invPostQ))
	ret = ret.normalized()
	if not ret.is_normalized():
		push_error("ret is not normalized " + str(bone_idx) + " " + str(muscle_triplet) + " " + str(preQ) + "," + str(swing_res) + "," + str(invPostQ))
	return ret

'''
static func setBody(humanPositions: Array[Vector3], humanRotations: Array[Quaternion], rootT, rootQ):
	var hipsPosition := humanPositions[0]
	var hipsRotation := humanRotations[0]
	var sourceT := getMassT(humanPositions, humanRotations)
	var sourceQ := getMassQ(humanPositions)
	var targetT: Vector3 = Vector3(-1,1,1) * rootT
	var targetQ := Quaternion(rootQ.x, -rootQ.y, -rootQ.z, rootQ.w)
	var deltaQ: Quaternion = targetQ * sourceQ.inverse()
	sourceT = deltaQ * (sourceT - hipsPosition)
	hips.position = targetT - deltaQ * (sourceT - hipsPosition)
	hips.rotation = deltaQ
'''

# Based on uvw.js HumanPoseHandler.setBody
static func get_hips_rotation_delta(humanPositions: Array[Vector3], targetQ: Quaternion) -> Quaternion:
	var sourceQ := getMassQ(humanPositions)
	#return Quaternion(targetQ.x, -targetQ.y, -targetQ.z, targetQ.w) * sourceQ.inverse()
	return targetQ * sourceQ.inverse()
	# Quaternion(Vector3.UP, PI) * 

# Based on uvw.js HumanPoseHandler.setBody
# deltaQ is the result of get_hips_rotation_delta()
static func get_hips_position(humanPositions: Array[Vector3], humanRotations: Array[Quaternion], deltaQ: Quaternion, targetT: Vector3) -> Vector3:
	var hipsPosition := humanPositions[0]
	var hipsRotation := humanRotations[0]
	var sourceT := getMassT(humanPositions, humanRotations)
	sourceT = deltaQ * (sourceT - hipsPosition)
	return targetT - sourceT

static func getMassQ(humanPositions: Array[Vector3]) -> Quaternion:
	human_trait.boneIndexToMono.find(human_trait.HumanBodyBones.LeftUpperArm)
	var leftUpperArmT := humanPositions[14] # boneIndexToMono.find(LeftUpperArm)
	var rightUpperArmT := humanPositions[15] # boneIndexToMono.find(RightUpperArm)
	var leftUpperLegT := humanPositions[1] # boneIndexToMono.find(LeftUpperLeg)
	var rightUpperLegT := humanPositions[2] # boneIndexToMono.find(RightUpperLeg)
	# this interpretation of "average left/right hips/shoulders vectors" seems most accurate
	var x: Vector3 = (leftUpperArmT + leftUpperLegT) - (rightUpperArmT + rightUpperLegT)
	var y: Vector3 = (leftUpperArmT + rightUpperArmT) - (leftUpperLegT + rightUpperLegT)
	x = x.normalized()
	y = y.normalized()
	var z: Vector3 = x.cross(y).normalized()
	x = y.cross(z)
	return Basis(x, y, z).get_rotation_quaternion()

static func getMassT(humanPositions: Array[Vector3], humanRotations: Array[Quaternion]) -> Vector3:
	var sum: float = 1.0e-6
	var out := Vector3.ZERO
	for i in range(len(humanPositions)):
		# var postQ_inverse := human_trait.postQ_inverse_exported[i]
		var m_HumanBoneMass := human_trait.human_bone_mass[i] # m_HumanBoneMass
		var axisLength := human_trait.bone_lengths[i] # m_AxesArray.m_Length
		if m_HumanBoneMass:
			#var centerT := Vector3(axisLength/2, 0, 0) # GUESS: mass-center at half bone length
			#centerT = postQ_inverse.inverse() * centerT # Bring centerT from Unity coords to Godot coords
			var centerT := Vector3(0, axisLength/2, 0)
			centerT = humanPositions[i] + humanRotations[i] * centerT
			out += centerT * m_HumanBoneMass
			sum += m_HumanBoneMass
	return out / sum

static func swing_twist(x: float, y: float, z: float) -> Quaternion:
	var yz = sqrt(y*y + z*z)
	var sinc = 0.5 if abs(yz) < 1e-8 else sin(yz/2)/yz
	var swingW = cos(yz/2)
	var twistW = cos(x/2)
	var twistX = sin(x/2)
	return Quaternion(
		swingW * twistX,
		(z * twistX + y * twistW) * sinc,
		(z * twistW - y * twistX) * sinc,
		swingW * twistW)
