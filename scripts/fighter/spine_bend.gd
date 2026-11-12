class_name SpineBend
extends SkeletonModifier3D
## Re-angles the upper body on top of the animation; legs and hips stay as they are, so the
## feet stay planted.
##
##   hips_source — when an upper-body clip is layered over other legs, the clip's own hip turn
##                 (often a big part of its swing) is lost. Give its hips rotation here and the
##                 upper body is turned at the waist as if the hips had turned with it.
##   turn        — extra turn at the waist (radians, positive = to the left).
## The turn is shared like a real body's: the pelvis takes PELVIS_SHARE of it over planted
## feet (the thighs turn back so the legs stay where they are), the waist the rest.
##   roll        — sideways lean (radians, positive = to the right)
##   bow         — forward bend (radians, positive = forward)
## Lean and bow are spread over the spine so it bends rather than hinges, and are taken
## around the body's own axes (from the hips), so they still mean "sideways" / "forward"
## when the body is turned mid-swing.

const ROOT_BONE := "mixamorig_Hips"
const SPINE_BONES := ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]
const LEFT_LEG := "mixamorig_LeftUpLeg"
const RIGHT_LEG := "mixamorig_RightUpLeg"
const PELVIS_SHARE := 0.5

## Hips rotation (skeleton space) of the clip driving the upper body, and how much of it to use.
var hips_source := Quaternion.IDENTITY
var hips_weight := 0.0
var turn := 0.0
var roll := 0.0
var bow := 0.0

var _hips := -1
var _legs := Vector2i(-1, -1)
var _spine: Array[int] = []


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or (hips_weight < 0.001 and absf(turn) < 0.0001 and absf(roll) < 0.0001 and absf(bow) < 0.0001):
		return
	if _spine.is_empty():
		_hips = sk.find_bone(ROOT_BONE)
		_legs = Vector2i(sk.find_bone(LEFT_LEG), sk.find_bone(RIGHT_LEG))
		for n in SPINE_BONES:
			var i := sk.find_bone(n)
			if i >= 0:
				_spine.append(i)
		if _hips < 0 or _spine.is_empty() or _legs.x < 0 or _legs.y < 0:
			return
	var to_skeleton := sk.global_basis.orthonormalized().inverse()
	var up := (to_skeleton * Vector3.UP).normalized()
	# The body's own right / forward (skeleton space), from the hips — before any changes here.
	var right := sk.get_bone_global_pose(_legs.y).origin - sk.get_bone_global_pose(_legs.x).origin
	right = (right - up * right.dot(up)).normalized()
	var body_forward := up.cross(right)

	# Turn: the whole upper body at the waist.
	var offset := Quaternion.IDENTITY
	if hips_weight > 0.001:
		var current := sk.get_bone_pose_rotation(_hips)
		offset = Quaternion.IDENTITY.slerp((hips_source * current.inverse()).normalized(), hips_weight)
	if absf(turn) > 0.0001:
		offset = Quaternion(up, turn) * offset
	# Pelvis: its share of the turn (yaw only), legs turned back so the feet stay put.
	var pelvis := Quaternion.IDENTITY.slerp(_yaw_part(offset, up), PELVIS_SHARE)
	_rotate(sk, _hips, pelvis)
	_rotate(sk, _legs.x, pelvis.inverse())
	_rotate(sk, _legs.y, pelvis.inverse())
	# Waist: the rest, so the upper body ends up turned by the full offset.
	_rotate(sk, _spine[0], offset * pelvis.inverse())

	# Lean and bow: a share at each spine bone, around the body's forward / right axes
	# (turned along with the turn above).
	if absf(roll) > 0.0001 or absf(bow) > 0.0001:
		var n := float(_spine.size())
		var lean_axis := offset * body_forward
		var bow_axis := offset * right
		# (A positive turn around the body's right axis tips the top backward, hence -bow.)
		var step := Quaternion(lean_axis, roll / n) * Quaternion(bow_axis, -bow / n)
		for b in _spine:
			_rotate(sk, b, step)


## The part of a rotation that turns around `axis` (swing-twist split).
static func _yaw_part(q: Quaternion, axis: Vector3) -> Quaternion:
	var v := Vector3(q.x, q.y, q.z)
	var p := axis * v.dot(axis)
	var t := Quaternion(p.x, p.y, p.z, q.w)
	return t.normalized() if t.length_squared() > 1e-9 else Quaternion.IDENTITY


## Apply a skeleton-space rotation to a bone (and so everything above it).
func _rotate(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	var parent_bone := sk.get_bone_parent(bone)
	if parent_bone < 0:
		sk.set_bone_pose_rotation(bone, (q * sk.get_bone_pose_rotation(bone)).normalized())
		return
	var parent := sk.get_bone_global_pose(parent_bone).basis.get_rotation_quaternion()
	var local := parent.inverse() * q * parent
	sk.set_bone_pose_rotation(bone, (local * sk.get_bone_pose_rotation(bone)).normalized())
