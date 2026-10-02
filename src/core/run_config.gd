class_name RunConfig
extends RefCounted
## Run parameters that must survive scene reloads (retry, replay, next depth).
## Static state, so no autoload is needed. On first use it reads optional
## command-line user args:  godot --path . -- --seed=12345 --depth=2
## A seed is only ever replaced when the player explicitly asks for a new one.

const MAX_SEED := 0x7FFFFFFF

static var run_seed: int = -1
static var depth: int = 1
static var _initialized: bool = false


static func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	var args := parse_args(OS.get_cmdline_user_args())
	depth = maxi(1, int(args.get("depth", 1)))
	run_seed = int(args.get("seed", -1))
	if run_seed < 0:
		run_seed = random_seed()


static func set_run(seed_value: int, depth_value: int = 1) -> void:
	_initialized = true
	run_seed = seed_value & MAX_SEED
	depth = maxi(1, depth_value)


static func new_random_run() -> void:
	set_run(random_seed(), 1)


## Picks a fresh seed. Uses its own RNG, never the global one.
static func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi() & MAX_SEED


## Parses `--seed=<text>` and `--depth=<n>`. Unknown args are ignored.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var result := {}
	for arg in args:
		if arg.begins_with("--seed="):
			var parsed := parse_seed_text(arg.trim_prefix("--seed="))
			if parsed >= 0:
				result["seed"] = parsed
		elif arg.begins_with("--depth="):
			var depth_text := arg.trim_prefix("--depth=")
			if depth_text.is_valid_int():
				result["depth"] = int(depth_text)
	return result


## Numbers are used directly; any other text is hashed (so "CRYPT" is a valid,
## shareable seed). Returns -1 for empty input.
static func parse_seed_text(text: String) -> int:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return -1
	if cleaned.is_valid_int():
		return absi(int(cleaned)) & MAX_SEED
	return StableHash.fnv1a32(cleaned.to_upper()) & MAX_SEED
