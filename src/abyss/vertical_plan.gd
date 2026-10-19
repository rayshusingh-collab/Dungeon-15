extends RefCounted
## Stage 2 fixed fixture, in metres. No RNG or dependency on the 2D generator.
## Ordered route sockets are also the future navigation/encounter boundary.

static func route() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(0, 0, 0), Vector3(6, 0, 0), Vector3(18, 4, 0),
		Vector3(24, 4, 0), Vector3(30, 4, 0), Vector3(36, 4, 0),
		Vector3(48, 8, 0), Vector3(54, 8, 0)])


static func validate(points: PackedVector3Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if points.size() < 2:
		errors.append("route needs entry and exit")
	for i in points.size():
		if not points[i].is_finite():
			errors.append("non-finite socket")
		if i == 0:
			continue
		var delta := points[i] - points[i - 1]
		if delta.x <= 0 or not is_zero_approx(delta.z):
			errors.append("fixture requires increasing X and aligned sockets")
		if absf(delta.y) > delta.x * 0.4:
			errors.append("slope exceeds controller-safe fixture budget")
	return errors
