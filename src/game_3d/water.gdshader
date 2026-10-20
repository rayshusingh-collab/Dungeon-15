shader_type spatial;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 p = world_position.xz;
	float wave = sin(p.x*4.0+p.y*1.6+sin(p.y*2.0+TIME)*0.7-TIME*1.3);
	float crest = smoothstep(0.87,0.98,wave);
	ALBEDO = mix(vec3(0.025,0.24,0.33),vec3(0.25,0.8,0.87),crest*0.85);
	ROUGHNESS = 0.6;
}
