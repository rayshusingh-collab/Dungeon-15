shader_type spatial;
render_mode diffuse_burley;
varying vec3 world_position;
uniform vec4 base_color : source_color = vec4(0.33,0.35,0.38,1.0);
uniform bool masonry = false;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 p = world_position.xz;
	vec2 seam = min(mod(p,2.0),2.0-mod(p,2.0));
	float line = 1.0-smoothstep(0.025,0.06,min(seam.x,seam.y));
	if (masonry) {
		float row = floor(world_position.y/0.5);
		float mortar = min(mod(world_position.y,0.5),0.5-mod(world_position.y,0.5));
		float joint = min(mod(p.x+p.y+mod(row,2.0),2.0),2.0-mod(p.x+p.y+mod(row,2.0),2.0));
		line = max(1.0-smoothstep(0.02,0.045,mortar),1.0-smoothstep(0.02,0.055,joint));
	}
	ALBEDO = mix(base_color.rgb,base_color.rgb*0.63,line);
	ROUGHNESS = 1.0;
}
