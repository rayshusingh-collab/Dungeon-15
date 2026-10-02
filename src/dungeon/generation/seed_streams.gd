class_name SeedStreams
extends RefCounted
## Named, independent RNG streams for one generation attempt.
##   seed(name, index) = StableHash.hash62("dungeon15|v<gen>|<run_seed>|<depth>|<attempt>|<name>|<index>")
## Each pipeline stage (and each room's content) draws from its own stream, so
## changing how one stage consumes numbers never reshuffles another stage.
## Never use the global randi()/randf() in generation.

var run_seed: int
var depth: int
var attempt: int
var generator_version: int


func _init(p_run_seed: int, p_depth: int, p_attempt: int, p_generator_version: int) -> void:
	run_seed = p_run_seed
	depth = p_depth
	attempt = p_attempt
	generator_version = p_generator_version


func stream(stream_name: String, index: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = StableHash.hash62("dungeon15|v%d|%d|%d|%d|%s|%d" % [
		generator_version, run_seed, depth, attempt, stream_name, index])
	return rng


## Deterministic Fisher-Yates shuffle (in place).
static func shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


## Index picked with probability proportional to its weight; -1 if all weights are 0.
static func weighted_index(weights: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= maxf(weights[i], 0.0)
		if roll < 0.0:
			return i
	return weights.size() - 1
