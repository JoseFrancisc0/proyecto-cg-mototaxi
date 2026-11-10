shader_type spatial;
render_mode cull_disabled;
varying vec3 world_pos;
float hash(vec2 p){p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world_pos.xz;
 // Identical aggregate, world coordinates and base colour to terrain_splat.
 // A bridge is a structural change below the road, not a new asphalt colour.
 float aggregate=noise(p*6.0);
 vec3 base=vec3(.075,.076,.079)*mix(.92,1.08,aggregate);
 ALBEDO=base;ROUGHNESS=.94;
}
