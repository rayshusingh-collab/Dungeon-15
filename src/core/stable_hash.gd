class_name StableHash
extends RefCounted
## Engine-independent string hashing (FNV-1a) used for seed derivation.
## Godot's built-in hash() is not guaranteed stable across engine versions;
## generation seeds must not change just because the engine was upgraded.
## All arithmetic stays below 2^63, so there is no integer overflow.

const _FNV_PRIME := 16777619
const _MASK32 := 0xFFFFFFFF
const _BASIS_A := 0x811C9DC5
const _BASIS_B := 0x9E3779B9


static func fnv1a32(text: String, basis: int = _BASIS_A) -> int:
	var h := basis
	for byte in text.to_utf8_buffer():
		h = ((h ^ byte) * _FNV_PRIME) & _MASK32
	return h


static func fnv1a32_bytes(bytes: PackedByteArray, basis: int = _BASIS_A) -> int:
	var h := basis
	for byte in bytes:
		h = ((h ^ byte) * _FNV_PRIME) & _MASK32
	return h


## Non-negative 62-bit value built from two independent 32-bit hashes.
static func hash62(text: String) -> int:
	return ((fnv1a32(text, _BASIS_A) & 0x3FFFFFFF) << 32) | fnv1a32(text, _BASIS_B)
