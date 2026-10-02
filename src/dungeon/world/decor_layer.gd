class_name DecorLayer
extends Node2D
## Draws the floor's placeholder decoration (DungeonLayout.decor) in one
## static canvas item: no collision, no processing, one node for the whole
## floor, redrawn only when set up. Purely cosmetic; art later replaces these
## shapes (or this node) without touching generation or gameplay.

const CRACK_COLOR := Color(0.0, 0.0, 0.0, 0.32)
const STONE_COLOR := Color(0.62, 0.6, 0.58, 0.55)
const BONE_COLOR := Color(0.86, 0.82, 0.7, 0.7)
const TORCH_COLOR := Color(1.0, 0.62, 0.22, 0.95)
const GLOW_COLOR := Color(1.0, 0.55, 0.2, 0.12)

var _items: Array[Dictionary] = []
var _tile: float = DungeonLayout.TILE_SIZE


func setup(layout: DungeonLayout) -> void:
	name = "Decor"
	_items = layout.decor
	queue_redraw()


func _draw() -> void:
	for item in _items:
		var t: Vector2i = item.tile
		var origin := Vector2(t) * _tile
		# Small per-tile variation from the tile coordinates (stable, cosmetic).
		var h := absi(t.x * 73856093 ^ t.y * 19349663)
		var flip := 1.0 if h % 2 == 0 else -1.0
		match item.kind:
			&"crack":
				var a := origin + Vector2(6 + h % 8, 6 + (h >> 3) % 8)
				var b := a + Vector2(9 * flip, 7)
				draw_polyline(PackedVector2Array([a, b, b + Vector2(4 * flip, 9), b + Vector2(-3 * flip, 13)]), CRACK_COLOR, 1.5)
			&"stones":
				for k in 3:
					var p := origin + Vector2(8 + (h >> k) % 16, 8 + (h >> (k + 4)) % 16)
					draw_rect(Rect2(p, Vector2(3 + k, 3)), STONE_COLOR)
			&"bones", &"remains":
				var c := origin + Vector2(16, 16)
				draw_line(c + Vector2(-8, -3 * flip), c + Vector2(8, 3 * flip), BONE_COLOR, 2.5)
				draw_circle(c + Vector2(-8, -3 * flip), 2.5, BONE_COLOR)
				draw_circle(c + Vector2(8, 3 * flip), 2.5, BONE_COLOR)
				if item.kind == &"remains":
					draw_circle(c + Vector2(4, -7), 4.5, BONE_COLOR)
			&"torch":
				var c := origin + Vector2(16, 16)
				draw_circle(c, 22.0, GLOW_COLOR)
				draw_rect(Rect2(c + Vector2(-3, -2), Vector2(6, 9)), Color(0.3, 0.2, 0.12))
				draw_circle(c + Vector2(0, -4), 4.0, TORCH_COLOR)
