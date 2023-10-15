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

const human_trait = preload("./human_trait.gd")

static func calculate_humanoid_rotation(bone_idx: int, muscle_triplet: Vector3) -> Quaternion:
	var muscle_from_bone: PackedInt32Array = human_trait.MuscleFromBone[bone_idx]

	for i in range(3):
		muscle_triplet[i] *= deg_to_rad(
			human_trait.MuscleDefaultMax[muscle_from_bone[i]] if muscle_triplet[i] >= 0
			else -human_trait.MuscleDefaultMin[muscle_from_bone[i]]) * human_trait.Signs[bone_idx][i]
	var preQ : Quaternion = human_trait.preQ_exported[bone_idx]
	var invPostQ : Quaternion = human_trait.postQ_inverse_exported[bone_idx]
	var ret: Quaternion = preQ * swing_twist(muscle_triplet.x, -muscle_triplet.y, -muscle_triplet.z) * invPostQ
	return ret.normalized()

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
