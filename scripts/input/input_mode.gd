class_name InputMode
## Which control scheme the player uses.
##   Touch   — iOS/Android (portrait touch layout).
##   Desktop — macOS/Windows/Linux (keyboard + mouse, landscape).
## Override for testing: `--touch` / `--desktop` on the command line, or set `forced` from code.

enum Kind { AUTO = -1, DESKTOP = 0, TOUCH = 1 }

static var forced := Kind.AUTO


static func is_touch() -> bool:
	if forced != Kind.AUTO:
		return forced == Kind.TOUCH
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if args.has("--touch"):
		return true
	if args.has("--desktop"):
		return false
	return OS.has_feature("mobile")
