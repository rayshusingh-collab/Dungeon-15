extends Node3D
var arena: Node3D
var direction := Vector3.FORWARD
var life := 2.4
const SPEED := 8.0

func _ready() -> void:
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius=0.17
	sphere.height=0.34
	sphere.radial_segments=8
	sphere.rings=4
	node.mesh=sphere
	node.material_override=preload("res://src/game_3d/combat/combat_visuals.gd").material(Color(1,0.35,0.12))
	node.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(node)
	preload("res://src/game_3d/combat/combat_visuals.gd").box(self,Vector3(0.08,0.08,0.65),Vector3(0,0,0.3),node.material_override)
	look_at(global_position+direction,Vector3.UP)

func _physics_process(delta: float) -> void:
	life-=delta
	if life<=0 or arena.player.state==arena.player.State.DEAD or arena.reached_exit:
		queue_free()
		return
	var next := global_position+direction*SPEED*delta
	var query := PhysicsRayQueryParameters3D.create(global_position,next,1|2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		if hit.collider==arena.player:
			arena.player.receive_damage(1,direction*4)
		arena.contact(hit.position)
		queue_free()
	else:
		global_position=next
