extends RefCounted
## Reusable low-poly combat shapes; no generated textures, lights or transient FX nodes.
static func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color=color
	result.roughness=0.85
	return result

static func box(parent: Node3D,size: Vector3,at: Vector3,mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.material_override=mat
	node.position=at
	parent.add_child(node)
	return node

static func arc(parent: Node3D,radius: float,angle: float,color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 20:
		var a := deg_to_rad(lerpf(-angle,angle,i/20.0))
		var b := deg_to_rad(lerpf(-angle,angle,(i+1)/20.0))
		surface.add_vertex(Vector3.ZERO)
		surface.add_vertex(Vector3(sin(b),0,-cos(b))*radius)
		surface.add_vertex(Vector3(sin(a),0,-cos(a))*radius)
	var node := MeshInstance3D.new()
	node.mesh=surface.commit()
	var mat := material(color)
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	node.material_override=mat
	node.position.y=0.045
	parent.add_child(node)
	return node
