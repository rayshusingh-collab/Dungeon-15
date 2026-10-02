class_name DungeonGraph
extends RefCounted
## Logical topology of one depth on a coarse macro grid: which spaces exist,
## their structural role, and how they connect. No geometry lives here, so the
## graph can be generated and tested without any scene.

enum Role { ENTRY, MAIN, SPECIAL, OBJECTIVE, BRANCH, DEAD_END }
enum LinkKind { MAIN, BRANCH, LOOP }
## COMBAT and OPTIONAL lock the room's doors; AMBUSH never locks (escape route).
enum Encounter { NONE, COMBAT, OPTIONAL, AMBUSH }
enum Purpose { NONE, REWARD, LORE, OPTIONAL_COMBAT, SECRET, RECOVERY }

## Same order as RoomShape.Side (N, E, S, W).
const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


class Space:
	var id: int
	var cell: Vector2i
	var role: int
	## Position on the main path, or -1 for branches.
	var main_index: int = -1
	var special_rule: SpecialRoomRule
	var encounter: int = 0
	var purpose: int = 0
	## RoomRole (PacingDirector); may be downgraded if no template fits.
	var tactic: int = RoomRole.TRAVERSAL
	var link_ids: Array[int] = []


class Link:
	var id: int
	var a: int
	var b: int
	var kind: int


var grid_size: Vector2i
var spaces: Array[Space] = []
var links: Array[Link] = []
## Space ids from entry (index 0) to objective (last).
var main_path: Array[int] = []
## Non-empty when construction failed (the generator retries).
var error: String = ""

var _by_cell: Dictionary = {}


func add_space(cell: Vector2i, role: int) -> Space:
	var space := Space.new()
	space.id = spaces.size()
	space.cell = cell
	space.role = role
	spaces.append(space)
	_by_cell[cell] = space.id
	return space


func connect_spaces(a: int, b: int, kind: int) -> Link:
	var link := Link.new()
	link.id = links.size()
	link.a = a
	link.b = b
	link.kind = kind
	links.append(link)
	spaces[a].link_ids.append(link.id)
	spaces[b].link_ids.append(link.id)
	return link


func space_at(cell: Vector2i) -> Space:
	return spaces[_by_cell[cell]] if _by_cell.has(cell) else null


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func is_free(cell: Vector2i) -> bool:
	return in_bounds(cell) and not _by_cell.has(cell)


func free_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		if is_free(cell + d):
			result.append(cell + d)
	return result


func are_linked(a: int, b: int) -> bool:
	for link_id in spaces[a].link_ids:
		var link := links[link_id]
		if (link.a == a and link.b == b) or (link.a == b and link.b == a):
			return true
	return false


func degree(id: int) -> int:
	return spaces[id].link_ids.size()


func other_end(link: Link, id: int) -> int:
	return link.b if link.a == id else link.a


## Index into DIRECTIONS pointing from space a to the adjacent space b.
func side_between(a: int, b: int) -> int:
	return DIRECTIONS.find(spaces[b].cell - spaces[a].cell)


func entry_id() -> int:
	return main_path[0] if not main_path.is_empty() else -1


func objective_id() -> int:
	return main_path.back() if not main_path.is_empty() else -1


func ids_with_role(role: int) -> Array[int]:
	var result: Array[int] = []
	for space in spaces:
		if space.role == role:
			result.append(space.id)
	return result


## Number of direction changes along the main path (0 = a straight chain).
func main_path_turns() -> int:
	var turns := 0
	for i in range(2, main_path.size()):
		var d1 := spaces[main_path[i - 1]].cell - spaces[main_path[i - 2]].cell
		var d2 := spaces[main_path[i]].cell - spaces[main_path[i - 1]].cell
		if d1 != d2:
			turns += 1
	return turns


func count_links(kind: int) -> int:
	var count := 0
	for link in links:
		if link.kind == kind:
			count += 1
	return count
