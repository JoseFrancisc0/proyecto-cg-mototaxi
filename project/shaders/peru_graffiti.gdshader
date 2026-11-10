shader_type spatial;
render_mode cull_disabled,depth_prepass_alpha;
uniform sampler2D paint : source_color,filter_linear_mipmap;
uniform sampler2D opacity : filter_linear_mipmap;
uniform vec3 tint : source_color=vec3(1.0);
void fragment(){
 vec4 sample_color=texture(paint,UV);
 ALBEDO=sample_color.rgb*tint;
 ALPHA=texture(opacity,UV).r*.95;
 ROUGHNESS=.98;
}
