extends RefCounted
## Base class for unit tests: collects assertion failures instead of aborting.

var failures: PackedStringArray = []


func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func assert_eq(a: Variant, b: Variant, msg: String) -> void:
	if a != b:
		failures.append("%s (got %s, expected %s)" % [msg, str(a), str(b)])


func assert_near(a: float, b: float, eps: float, msg: String) -> void:
	if absf(a - b) > eps:
		failures.append("%s (got %f, expected %f ± %f)" % [msg, a, b, eps])
