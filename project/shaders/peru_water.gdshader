shader_type spatial;
render_mode cull_disabled;
varying vec3 world_pos;
varying vec4 tint;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;tint=COLOR;}
void fragment(){
 float a=sin(world_pos.x*.53+world_pos.z*.18+TIME*1.7),b=sin(world_pos.x*.17-world_pos.z*.61+TIME*.9);
 float flow=noise(world_pos.xz*2.8+vec2(TIME*.18,-TIME*.36));
 float threads=noise(world_pos.xz*vec2(1.7,8.0)+vec2(0,-TIME*.8));
 NORMAL_MAP=vec3(.5+a*.035+(flow-.5)*.08,.5+b*.035,1.0);
 float bank=1.0-smoothstep(.02,.35,tint.a);
 vec3 shallow=mix(tint.rgb,vec3(.31,.34,.29),bank*.5);
 ALBEDO=shallow*(.88+.10*flow+.035*(a+b));
 ALBEDO=mix(ALBEDO,vec3(.55,.60,.56),bank*smoothstep(.65,.95,threads)*.38);
 ROUGHNESS=mix(.32,.70,bank);SPECULAR=.38;
}
